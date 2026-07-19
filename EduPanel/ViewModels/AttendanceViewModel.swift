import FirebaseAuth
import Foundation
import Observation

protocol AttendanceDashboardProviding {
    func fetchDashboard(for date: Date, forceRefresh: Bool) async throws -> DashboardSnapshot
}

extension DashboardRepository: AttendanceDashboardProviding {}

@MainActor
@Observable
final class AttendanceViewModel {
    let course: String
    let subject: String

    private(set) var date: Date
    private(set) var blocks: [AttendanceBlock] = []
    var selectedBlockID: String?
    private(set) var loadState: AttendanceLoadState = .idle
    private(set) var saveState: AttendanceSaveState = .idle
    private(set) var isDirty = false
    var actionError: String?

    private(set) var markFeedbackToken = 0
    private(set) var completionFeedbackToken = 0
    private(set) var saveFeedbackToken = 0
    private(set) var signFeedbackToken = 0
    private(set) var errorFeedbackToken = 0

    let connectivity: AttendanceConnectivity

    private let initialBlockID: String?
    private let dashboardRepository: any AttendanceDashboardProviding
    private let repository: any AttendanceRepositoryProtocol
    private let contextRepository: any AttendanceContextRepositoryProtocol
    private let uidProvider: () -> String?
    private var scope: AttendanceDataScope?
    private var editVersion = 0
    private var autoSaveTask: Task<Void, Never>?
    private var loadToken = UUID()

    init(
        course: String,
        subject: String,
        date: Date,
        initialBlockID: String?,
        dashboardRepository: any AttendanceDashboardProviding,
        repository: any AttendanceRepositoryProtocol = AttendanceRepository(),
        contextRepository: any AttendanceContextRepositoryProtocol = AttendanceContextRepository(),
        connectivity: AttendanceConnectivity? = nil,
        uidProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.course = course
        self.subject = subject
        self.date = Calendar.current.startOfDay(for: date)
        self.initialBlockID = initialBlockID
        self.selectedBlockID = initialBlockID
        self.dashboardRepository = dashboardRepository
        self.repository = repository
        self.contextRepository = contextRepository
        self.connectivity = connectivity ?? AttendanceConnectivity()
        self.uidProvider = uidProvider
    }

    var activeBlock: AttendanceBlock? {
        guard let selectedBlockID else { return blocks.first }
        return blocks.first { $0.id == selectedBlockID } ?? blocks.first
    }

    var activeBlockIndex: Int? {
        guard let activeBlock else { return nil }
        return blocks.firstIndex { $0.id == activeBlock.id }
    }

    var summary: AttendanceSummary {
        activeBlock.map(AttendanceRules.summary) ?? AttendanceSummary()
    }

    var canSignActiveBlock: Bool {
        activeBlock.map(AttendanceRules.canSign) ?? false
    }

    var isOnline: Bool { connectivity.isOnline }

    var qrScope: AttendanceDataScope? { scope }

    var dateKey: String { DateHelpers.dateKey(for: date) }

    var dateLabel: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var objective: String {
        get { activeBlock?.objective ?? "" }
        set { updateActiveBlock { $0.objective = newValue } }
    }

    var activity: String {
        get { activeBlock?.activity ?? "" }
        set { updateActiveBlock { $0.activity = newValue } }
    }

    var signBlockingMessage: String? {
        guard let block = activeBlock else { return "No hay un bloque disponible." }
        if block.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Falta escribir el objetivo de la clase."
        }
        if block.activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Falta registrar la actividad realizada."
        }
        if block.attendance.isEmpty { return "Este curso no tiene estudiantes cargados." }
        if block.attendance.contains(where: { !$0.status.isValid }) {
            return "Hay estados de asistencia inválidos que debes revisar."
        }
        if summary.pending > 0 {
            return "Falta confirmar a \(summary.pending) estudiante\(summary.pending == 1 ? "" : "s")."
        }
        return nil
    }

    func load(forceRefresh: Bool = false) async {
        let token = UUID()
        loadToken = token
        autoSaveTask?.cancel()
        loadState = .loading
        actionError = nil

        do {
            let snapshot = try await dashboardRepository.fetchDashboard(for: date, forceRefresh: forceRefresh)
            guard !Task.isCancelled, loadToken == token else { return }
            let resolvedScope = AttendanceDataScope.resolve(
                activeSchoolID: snapshot.preferences.colegioActivoId,
                date: date
            )
            async let savedRequest = repository.load(
                scope: resolvedScope,
                subject: subject,
                course: course,
                dateKey: dateKey
            )
            async let contextRequest = contextRepository.load(
                scope: resolvedScope,
                course: course
            )
            let saved = try await savedRequest
            let scopedContext = try await contextRequest
            guard !Task.isCancelled, loadToken == token else { return }

            let legacySchedule = snapshot.horario.map {
                AttendanceScheduleBlock(
                    id: $0.id,
                    course: $0.resumen,
                    weekday: $0.dia,
                    startTime: $0.horaInicio,
                    endTime: $0.horaFin,
                    isFree: $0.tipo == .libre
                )
            }
            let legacyStudents = (snapshot.studentsByCourse[course] ?? [])
                .sorted { $0.orden < $1.orden }
                .map { AttendanceRosterStudent(id: $0.id, name: $0.nombre) }
            let schedule = scopedContext.schedule ?? legacySchedule
            let students = scopedContext.students ?? legacyStudents

            blocks = AttendanceRules.reconcileBlocks(
                saved: saved?.blocks,
                course: course,
                dateKey: dateKey,
                schedule: schedule,
                students: students
            )
            scope = resolvedScope
            selectInitialBlock()
            isDirty = false
            editVersion = 0
            saveState = saved == nil ? .idle : .saved
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard loadToken == token else { return }
            loadState = .failed(error.localizedDescription)
            actionError = error.localizedDescription
            errorFeedbackToken += 1
        }
    }

    func selectBlock(_ id: String) {
        guard blocks.contains(where: { $0.id == id }) else { return }
        selectedBlockID = id
    }

    @discardableResult
    func changeDate(to newDate: Date) async -> Bool {
        let normalized = Calendar.current.startOfDay(for: newDate)
        guard normalized != date else { return true }
        if isDirty, !(await save()) { return false }
        date = normalized
        selectedBlockID = nil
        blocks = []
        scope = nil
        await load(forceRefresh: true)
        return loadState == .loaded
    }

    func refresh() async {
        if isDirty, !(await save()) { return }
        await load(forceRefresh: true)
    }

    func confirmAllPresent() {
        guard var block = activeBlock, !block.isSigned else { return }
        block.attendance = AttendanceRules.confirmAll(block.attendance)
        replaceActiveBlock(with: block)
        completionFeedbackToken += 1
    }

    func mark(studentID: String, as status: AttendanceStatus, method: AttendanceMethod = .manual) {
        guard var block = activeBlock, !block.isSigned,
              let index = block.attendance.firstIndex(where: { $0.id == studentID }) else { return }
        let wasComplete = AttendanceRules.summary(for: block).allConfirmed
        block.attendance[index] = AttendanceRules.mark(
            block.attendance[index],
            status: status,
            method: method
        )
        replaceActiveBlock(with: block)
        if !wasComplete, AttendanceRules.summary(for: block).allConfirmed {
            completionFeedbackToken += 1
        } else {
            markFeedbackToken += 1
        }
    }

    @discardableResult
    func applyResolvedQR(
        _ response: AttendanceQRResolveResponse,
        allowingConfirmedException: Bool = false,
        markedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> AttendanceQRApplicationResult {
        guard let index = activeBlockIndex else { return .studentNotFound }
        let wasComplete = AttendanceRules.summary(for: blocks[index]).allConfirmed
        let result = AttendanceRules.applyQR(
            to: blocks[index],
            studentID: response.studentId,
            allowingConfirmedException: allowingConfirmedException,
            markedAt: markedAt
        )

        if case .applied(let updatedBlock, _) = result {
            blocks[index] = updatedBlock
            markEdited()
            if !wasComplete, AttendanceRules.summary(for: updatedBlock).allConfirmed {
                completionFeedbackToken += 1
            } else {
                markFeedbackToken += 1
            }
        }
        return result
    }

    func copyPreviousBlock() {
        guard let index = activeBlockIndex, index > 0, !blocks[index].isSigned else { return }
        blocks[index].attendance = AttendanceRules.copyForConfirmation(blocks[index - 1].attendance)
        markEdited()
    }

    @discardableResult
    func save(providesFeedback: Bool = false) async -> Bool {
        guard loadState == .loaded, let scope else { return false }
        guard isDirty else {
            if saveState != .saved { saveState = .saved }
            return true
        }
        guard isOnline else {
            saveState = .pendingSync
            return false
        }

        autoSaveTask?.cancel()
        saveState = .saving
        let versionAtStart = editVersion
        let book = AttendanceBook(subject: subject, course: course, dateKey: dateKey, blocks: blocks)
        do {
            try await repository.save(book, scope: scope)
            if editVersion == versionAtStart {
                isDirty = false
                saveState = .saved
                if providesFeedback { saveFeedbackToken += 1 }
            } else {
                saveState = .idle
                scheduleAutoSave()
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            saveState = .failed(error.localizedDescription)
            actionError = error.localizedDescription
            errorFeedbackToken += 1
            return false
        }
    }

    func signActiveBlock() async -> Bool {
        guard isOnline else {
            showError("Conéctate a internet para firmar este bloque de forma segura.")
            saveState = .pendingSync
            return false
        }
        guard let index = activeBlockIndex else { return false }
        do {
            let previous = blocks[index]
            let wasDirty = isDirty
            blocks[index] = try AttendanceRules.sign(previous, uid: uidProvider())
            markEdited(scheduleSave: false)
            guard await save() else {
                restoreAfterFailedProtectedAction(
                    block: previous,
                    at: index,
                    wasDirty: wasDirty
                )
                return false
            }
            signFeedbackToken += 1
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    func reopenActiveBlock(reason: String) async -> Bool {
        guard isOnline else {
            showError("Conéctate a internet para reabrir este bloque y guardar la trazabilidad.")
            saveState = .pendingSync
            return false
        }
        guard let index = activeBlockIndex else { return false }
        do {
            let previous = blocks[index]
            let wasDirty = isDirty
            blocks[index] = try AttendanceRules.reopen(previous, reason: reason, uid: uidProvider())
            markEdited(scheduleSave: false)
            guard await save() else {
                restoreAfterFailedProtectedAction(
                    block: previous,
                    at: index,
                    wasDirty: wasDirty
                )
                return false
            }
            signFeedbackToken += 1
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    func connectivityChanged() {
        if isOnline, isDirty {
            scheduleAutoSave(delay: .milliseconds(150))
        } else if !isOnline, isDirty {
            saveState = .pendingSync
        }
    }

    func dismissError() {
        actionError = nil
    }

    func reportSignBlocker() {
        showError(signBlockingMessage ?? "Todavía no es posible firmar este bloque.")
    }

    private func selectInitialBlock() {
        if let selectedBlockID, blocks.contains(where: { $0.id == selectedBlockID }) { return }
        if let initialBlockID, blocks.contains(where: { $0.id == initialBlockID }) {
            selectedBlockID = initialBlockID
            return
        }
        if Calendar.current.isDateInToday(date) {
            let currentMinutes = DateHelpers.minutesSinceMidnight(for: Date())
            if let current = blocks.first(where: {
                currentMinutes >= DateHelpers.minutes(from: $0.startTime)
                    && currentMinutes < DateHelpers.minutes(from: $0.endTime)
            }) {
                selectedBlockID = current.id
                return
            }
        }
        selectedBlockID = blocks.first?.id
    }

    private func replaceActiveBlock(with block: AttendanceBlock) {
        guard let index = activeBlockIndex else { return }
        blocks[index] = block
        markEdited()
    }

    private func updateActiveBlock(_ update: (inout AttendanceBlock) -> Void) {
        guard let index = activeBlockIndex, !blocks[index].isSigned else { return }
        update(&blocks[index])
        markEdited()
    }

    private func markEdited(scheduleSave: Bool = true) {
        editVersion += 1
        isDirty = true
        saveState = isOnline ? .idle : .pendingSync
        if scheduleSave { scheduleAutoSave() }
    }

    private func scheduleAutoSave(delay: Duration = .seconds(1.2)) {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.autoSaveTask = nil
            _ = await self.save()
        }
    }

    /// Revierte el bloqueo/desbloqueo local cuando Firestore no confirmó la
    /// operación. Si ya había ediciones pendientes, se conservan como tales;
    /// de lo contrario la copia local vuelve a coincidir con lo persistido.
    private func restoreAfterFailedProtectedAction(
        block: AttendanceBlock,
        at index: Int,
        wasDirty: Bool
    ) {
        autoSaveTask?.cancel()
        blocks[index] = block
        editVersion += 1
        isDirty = wasDirty
        if !wasDirty {
            saveState = .saved
        }
    }

    private func showError(_ message: String) {
        actionError = message
        errorFeedbackToken += 1
    }
}

#if DEBUG
private struct AttendancePreviewDashboard: AttendanceDashboardProviding {
    func fetchDashboard(for date: Date, forceRefresh: Bool) async throws -> DashboardSnapshot {
        throw CancellationError()
    }
}

private struct AttendancePreviewRepository: AttendanceRepositoryProtocol {
    func load(
        scope: AttendanceDataScope,
        subject: String,
        course: String,
        dateKey: String
    ) async throws -> AttendanceBook? {
        nil
    }

    func save(_ book: AttendanceBook, scope: AttendanceDataScope) async throws {}
}

extension AttendanceViewModel {
    static func preview(isSigned: Bool, allConfirmed: Bool) -> AttendanceViewModel {
        let date = Date()
        let model = AttendanceViewModel(
            course: "5° Básico A",
            subject: "Lenguaje y Comunicación",
            date: date,
            initialBlockID: "bloque-preview",
            dashboardRepository: AttendancePreviewDashboard(),
            repository: AttendancePreviewRepository(),
            connectivity: AttendanceConnectivity(startMonitoring: false),
            uidProvider: { "docente_preview" }
        )
        let names = [
            "Antonia González", "Benjamín Soto", "Catalina Muñoz",
            "Diego Contreras", "Emilia Rojas", "Facundo Silva"
        ]
        let attendance = names.enumerated().map { index, name in
            StudentAttendance(
                id: "est_\(index + 1)",
                name: name,
                status: index == 2 ? .absent : (index == 4 ? .late : .present),
                confirmed: allConfirmed || index < 3,
                method: allConfirmed || index < 3 ? .manual : nil,
                markedAt: allConfirmed || index < 3 ? "2026-07-18T13:30:00Z" : nil
            )
        }
        model.blocks = [
            AttendanceBlock(
                id: "bloque-preview",
                label: "Bloque 2",
                startTime: "09:30",
                endTime: "10:15",
                objective: "Identificar las ideas principales de un texto informativo.",
                activity: "Lectura guiada y conversación en parejas sobre las ideas centrales.",
                isSigned: isSigned,
                attendance: attendance,
                attendanceSchemaVersion: 2,
                signedAt: isSigned ? "2026-07-18T14:20:00Z" : nil,
                signedByUID: isSigned ? "docente_preview" : nil,
                reopenedAt: nil,
                reopenedByUID: nil,
                reopeningReason: nil
            )
        ]
        model.selectedBlockID = "bloque-preview"
        model.scope = .init(schoolID: "principal", yearID: "2026")
        model.loadState = .loaded
        model.saveState = .saved
        return model
    }
}
#endif
