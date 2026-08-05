import Foundation
import SwiftUI

private enum DashboardTabKey: String, CaseIterable, Identifiable {
    case hoy
    case pendientes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoy: return "Hoy"
        case .pendientes: return "Pendientes"
        }
    }

    var systemImage: String {
        switch self {
        case .hoy: return "sun.max.fill"
        case .pendientes: return "bell.fill"
        }
    }
}

private enum DashboardVoiceSheet: String, Identifiable {
    case rapido
    case guiado
    case borradores

    var id: String { rawValue }
}

private enum DashboardVoiceLinkError: LocalizedError {
    case missingContext
    case unavailableBlock
    case signedBlock
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .missingContext:
            return "Falta curso, asignatura o fecha para vincular esta nota. Puedes conservarla como borrador."
        case .unavailableBlock:
            return "No encontramos el bloque de clase. Conservamos la nota para que puedas intentarlo después."
        case .signedBlock:
            return "El leccionario está firmado. Reábrelo antes de vincular esta nota."
        case .saveFailed:
            return "No pudimos guardar la nota en la clase. Quedó disponible en Notas sin vincular."
        }
    }
}

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var selectedTab: DashboardTabKey = .hoy
    @State private var newReminder = ""
    @State private var reminderColor: ReminderColor = .amarillo
    @State private var voiceSheet: DashboardVoiceSheet?
    @State private var voiceDraftCount = 0
    @State private var voiceDraftError: String?
    @AppStorage("edupanel_dashboard_reminders") private var remindersData = "[]"
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.auto.rawValue
    @AppStorage("edupanel_dashboard_date_button") private var showDashboardDateButton = true
    @Environment(\.displayMode) private var displayMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let repository: DashboardRepository
    let user: AuthenticatedUser
    let onOpenProfile: () -> Void
    let onOpenPlanificaciones: () -> Void

    init(
        repository: DashboardRepository,
        user: AuthenticatedUser,
        onOpenProfile: @escaping () -> Void = {},
        onOpenPlanificaciones: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: DashboardViewModel(repository: repository))
        self.repository = repository
        self.user = user
        self.onOpenProfile = onOpenProfile
        self.onOpenPlanificaciones = onOpenPlanificaciones
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    loadingState
                } else if let snapshot = viewModel.snapshot {
                    dashboardContent(snapshot)
                } else {
                    emptyState
                }

                // El dictado sigue disponible aunque el panel remoto falle o
                // todavía esté cargando; las notas se guardan localmente.
                quickActions
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .tabBarPageBottomPadding()
        }
        .reportsTabBarScroll()
        .background(EPTheme.background)
        .navigationTitle("Inicio")
        .task {
            await viewModel.load()
            await refreshVoiceDraftCount()
        }
        .refreshable { await viewModel.refresh() }
        .sheet(item: $voiceSheet, onDismiss: {
            Task { await refreshVoiceDraftCount() }
        }) { destination in
            voiceSheetContent(destination)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(EPTheme.primary)
            .frame(width: 32, height: 32)
            .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dashboardContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            heroCard(snapshot)

            if snapshot.horario.isEmpty {
                noScheduleCard
            } else if displayMode.isSimple {
                todayTimeline(snapshot)
            } else {
                dashboardTabs(snapshot)

                switch selectedTab {
                case .hoy:
                    todayTimeline(snapshot)
                    if !decodedReminders.isEmpty {
                        remindersReadCard
                    }
                case .pendientes:
                    pendingPanel(snapshot)
                    remindersEditorCard
                }
            }
        }
    }

    // MARK: - Hero

    private func heroCard(_ snapshot: DashboardSnapshot) -> some View {
        let greeting = greetingInfo
        let currentOrNext = snapshot.currentOrNextClass()
        let isCurrent = currentOrNext.map { isClassCurrent($0, now: Date()) } ?? false
        let progress = currentOrNext.map { blockProgress($0, now: Date()) } ?? 0

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(greeting.greet),")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(user.firstName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Control opcional de apariencia junto a la fecha.
                if showDashboardDateButton {
                    Button {
                        let current = AppTheme(rawValue: appThemeRaw) ?? .auto
                        appThemeRaw = (current == .oscuro ? AppTheme.claro : .oscuro).rawValue
                    } label: {
                        Image(systemName: greeting.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(EPTheme.primary)
                            .frame(width: 46, height: 46)
                            .background(EPTheme.primaryLight, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: appThemeRaw)
                    .accessibilityLabel("Cambiar apariencia")
                    .accessibilityHint("Alterna entre modo claro y oscuro")
                }
            }

            Text(formattedHeroDate)
                .font(.system(size: 11, weight: .black))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(.white.opacity(0.09))
                    .frame(width: 180, height: 180)
                    .offset(x: 65, y: -85)

                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 24)
                    .frame(width: 120, height: 120)
                    .offset(x: 58, y: 82)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(
                            currentOrNext == nil ? "Resumen del día" : (isCurrent ? "Ahora" : "A continuación"),
                            systemImage: isCurrent ? "flame.fill" : "clock.fill"
                        )
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white.opacity(0.88))
                        Spacer()
                        if let item = currentOrNext {
                            Text(item.timeRange)
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }

                    if let item = currentOrNext {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(item.asignatura ?? item.tipo.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        if isCurrent {
                            ProgressView(value: progress)
                                .tint(.white)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                    } else {
                        Text(snapshot.academicTodayClasses.isEmpty ? "Hoy no tienes clases programadas" : "Jornada finalizada")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    if !displayMode.isSimple {
                        HStack(spacing: 10) {
                            HeroKPI(
                                label: "Clases hoy",
                                value: "\(snapshot.completedAcademicCount)/\(snapshot.totalAcademicCount)",
                                subtitle: "\(Int(snapshot.progress * 100))% completadas"
                            )
                            HeroKPI(
                                label: "Pendientes",
                                value: "\(snapshot.pendingClasses.count)",
                                subtitle: snapshot.pendingClasses.isEmpty ? "Todo en orden" : "Por registrar"
                            )
                        }
                    }
                }
            }
            .padding(20)
            .background(
                LinearGradient(colors: [EPTheme.primaryDark, EPTheme.primary, EPTheme.rose], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: EPTheme.primary.opacity(0.22), radius: 18, y: 10)
        }
        .scrollTransition(axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .opacity(phase.isIdentity ? 1 : 0.75)
        }
    }

    // MARK: - Tabs internos

    private func dashboardTabs(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 6) {
            ForEach(DashboardTabKey.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(EPTheme.spring) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11, weight: .black))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .black))
                        if tab == .pendientes && !snapshot.pendingClasses.isEmpty {
                            Text("\(snapshot.pendingClasses.count)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? .white.opacity(0.3) : .red, in: Capsule())
                        }
                    }
                    .foregroundStyle(isSelected ? EPTheme.primary : EPTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        isSelected ? AnyShapeStyle(EPTheme.primaryLight) : AnyShapeStyle(EPTheme.card),
                        in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous)
                            .stroke(isSelected ? EPTheme.primary.opacity(0.16) : EPTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - Timeline de hoy

    private func todayTimeline(_ snapshot: DashboardSnapshot) -> some View {
        let today = DateHelpers.weekdayName(for: Date())
        let classes = today.map { dia in
            snapshot.horario.filter { $0.dia == dia }.sorted { $0.horaInicio < $1.horaInicio }
        } ?? []

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tu día", systemImage: "sun.max.fill")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text(today ?? "Fin de semana")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if classes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(today == nil ? "Es fin de semana. Descansa." : "Sin bloques programados para hoy.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(classes) { item in
                        TimelineClassRow(
                            item: item,
                            isToday: true,
                            isCompleted: snapshot.classState[item.id] == true,
                            studentCount: snapshot.studentCount(forCourseID: item.courseID, name: item.resumen),
                            route: AppRoute.classDetail(id: item.id, title: routeTitle(for: item))
                        ) {
                            Task { await viewModel.toggleCompletion(for: item) }
                        }
                    }
                }
            }
        }
        .webCard()
    }

    // MARK: - Acciones rápidas

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hazlo rápido")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "bolt.fill")
                    .foregroundStyle(EPTheme.primary)
            }

            voiceModeActions

            Button {
                voiceSheet = .borradores
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notas sin vincular")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(voiceDraftSummary)
                            .font(.caption)
                            .foregroundStyle(voiceDraftError == nil ? Color.secondary : Color.orange)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(EPTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EPTheme.border, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre borradores guardados en este dispositivo")

            if !displayMode.isSimple {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickAction(title: "Planificar", icon: "square.and.pencil", colors: [.purple, EPTheme.primary], kind: .action(onOpenPlanificaciones))
                    QuickAction(title: "Mi Perfil", icon: "person.crop.circle.fill", colors: [.indigo, .purple], kind: .action(onOpenProfile))
                }
            }
            }
        }
    }

    @ViewBuilder
    private var voiceModeActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                quickVoiceAction
                guidedVoiceAction
            }
        } else {
            HStack(spacing: 10) {
                quickVoiceAction
                guidedVoiceAction
            }
        }
    }

    private var quickVoiceAction: some View {
        VoiceDashboardAction(
            title: "Dictado rápido",
            subtitle: "Empieza al instante",
            icon: "mic.fill",
            tint: EPTheme.primary
        ) {
            voiceSheet = .rapido
        }
    }

    private var guidedVoiceAction: some View {
        VoiceDashboardAction(
            title: "Dictado guiado",
            subtitle: "Contexto opcional",
            icon: "list.bullet.clipboard",
            tint: .indigo
        ) {
            voiceSheet = .guiado
        }
    }

    @ViewBuilder
    private func voiceSheetContent(_ destination: DashboardVoiceSheet) -> some View {
        switch destination {
        case .rapido:
            if let snapshot = viewModel.snapshot {
                DictadoModalView(
                    ownerID: user.id,
                    mode: .rapido,
                    context: dictationTarget(in: snapshot).map { voiceContext(for: $0, snapshot: snapshot) } ?? VoiceNoteContext(),
                    linkOptions: voiceLinkOptions(in: snapshot),
                    startsAutomatically: true,
                    linkAction: { draft in
                        try await linkVoiceNote(draft, snapshot: snapshot)
                    }
                )
            } else {
                DictadoModalView(
                    ownerID: user.id,
                    mode: .rapido,
                    startsAutomatically: true
                )
            }
        case .guiado:
            if let snapshot = viewModel.snapshot {
                DictadoModalView(
                    ownerID: user.id,
                    mode: .guiado,
                    context: dictationTarget(in: snapshot).map { voiceContext(for: $0, snapshot: snapshot) } ?? VoiceNoteContext(),
                    linkOptions: voiceLinkOptions(in: snapshot),
                    linkAction: { draft in
                        try await linkVoiceNote(draft, snapshot: snapshot)
                    }
                )
            } else {
                DictadoModalView(ownerID: user.id, mode: .guiado)
            }
        case .borradores:
            if let snapshot = viewModel.snapshot {
                VoiceNotesInboxView(
                    ownerID: user.id,
                    linkOptions: voiceLinkOptions(in: snapshot),
                    linkAction: { draft in
                        try await linkVoiceNote(draft, snapshot: snapshot)
                    }
                )
            } else {
                VoiceNotesInboxView(ownerID: user.id, linkOptions: [], linkAction: nil)
            }
        }
    }

    private func voiceLinkOptions(in snapshot: DashboardSnapshot) -> [VoiceNoteLinkOption] {
        let calendar = CronoDateHelpers.civilCalendar
        let reference = calendar.startOfDay(for: snapshot.date)

        return (-14...14).flatMap { offset -> [VoiceNoteLinkOption] in
            guard let date = calendar.date(byAdding: .day, value: offset, to: reference),
                  let weekday = DateHelpers.weekdayName(for: date) else { return [] }
            let schedule = AcademicCalendarResolver.effectiveSchedule(
                periods: snapshot.schedulePeriods,
                legacy: snapshot.legacySchedule,
                events: snapshot.academicCalendarEvents,
                for: date
            )
            return schedule.compactMap { item in
                guard item.isAcademic, item.dia == weekday else { return nil }
                let context = voiceContext(for: item, snapshot: snapshot, date: date)
                guard context.isLinkedToClass else { return nil }
                let students = snapshot.students(forCourseID: item.courseID, name: item.resumen).map {
                    VoiceNoteStudentOption(id: $0.id, name: $0.nombre)
                }
                return VoiceNoteLinkOption(
                    title: "\(voiceDateLabel(date)) · \(item.resumen) · \(item.horaInicio)",
                    subtitle: item.asignatura ?? "Sin asignatura",
                    context: context,
                    students: students
                )
            }
        }
    }

    private func voiceContext(
        for item: ClaseHorario,
        snapshot: DashboardSnapshot,
        date: Date? = nil
    ) -> VoiceNoteContext {
        let course = snapshot.course(id: item.courseID, named: item.resumen)
        return VoiceNoteContext(
            courseID: item.courseID ?? course?.courseID,
            courseName: item.resumen,
            courseKind: course?.kind,
            subjectID: item.subjectID,
            subjectName: item.asignatura,
            classID: item.id,
            classTitle: routeTitle(for: item),
            dateKey: DateHelpers.dateKey(for: date ?? snapshot.date)
        )
    }

    private func voiceDateLabel(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Locale(identifier: "es_CL"))
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
        )
    }

    @MainActor
    private func linkVoiceNote(_ draft: VoiceNoteDraft, snapshot: DashboardSnapshot) async throws {
        let context = draft.context
        guard let classID = context.classID,
              let course = context.courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !course.isEmpty,
              let subject = context.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty,
              let dateKey = context.dateKey,
              let date = AttendanceDate.parse(dateKey) else {
            throw DashboardVoiceLinkError.missingContext
        }

        let model = AttendanceViewModel(
            course: course,
            subject: subject,
            date: date,
            initialBlockID: classID,
            dashboardRepository: repository
        )
        await model.load(forceRefresh: false)
        guard model.loadState == .loaded, let block = model.activeBlock, block.id == classID else {
            throw DashboardVoiceLinkError.unavailableBlock
        }
        guard !block.isSigned else { throw DashboardVoiceLinkError.signedBlock }

        let rendered = renderedVoiceNote(draft, snapshot: snapshot)
        switch model.appendVoiceNote(
            rendered,
            noteID: draft.id,
            metadata: draft.context.attendanceMetadata
        ) {
        case .appended, .metadataUpdated, .duplicate:
            break
        case .contentChanged:
            throw VoiceNoteLinkingError.contentChanged
        case .signedBlock:
            throw DashboardVoiceLinkError.signedBlock
        case .unavailableBlock, .emptyContent:
            throw DashboardVoiceLinkError.unavailableBlock
        }
        guard await model.save(providesFeedback: true) else {
            throw DashboardVoiceLinkError.saveFailed
        }
    }

    private func renderedVoiceNote(_ draft: VoiceNoteDraft, snapshot: DashboardSnapshot) -> String {
        var sections = [draft.text.trimmingCharacters(in: .whitespacesAndNewlines)]
        let selectedNames = snapshot.students(
            forCourseID: draft.context.courseID,
            name: draft.context.courseName ?? ""
        )
        .filter { draft.context.studentIDs.contains($0.id) }
        .map(\.nombre)
        if !selectedNames.isEmpty {
            sections.append("Estudiante\(selectedNames.count == 1 ? "" : "s"): \(selectedNames.joined(separator: ", "))")
        }
        if let value = draft.context.topic, !value.isEmpty { sections.append("Tema: \(value)") }
        if let value = draft.context.observationType, !value.isEmpty { sections.append("Observación: \(value)") }
        if let value = draft.context.outcome, !value.isEmpty { sections.append("Resultado: \(value)") }
        if let value = draft.context.nextStep, !value.isEmpty { sections.append("Próximo paso: \(value)") }
        if let value = draft.context.classSummary, !value.isEmpty { sections.append("Resumen: \(value)") }
        return sections.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    @MainActor
    private func refreshVoiceDraftCount() async {
        do {
            let drafts = try await VoiceNoteDraftStore.shared.load(ownerID: user.id)
            voiceDraftCount = drafts.filter { $0.status != .vinculada }.count
            voiceDraftError = nil
        } catch {
            voiceDraftCount = 0
            voiceDraftError = "No pudimos leer las notas guardadas"
        }
    }

    private var voiceDraftSummary: String {
        if let voiceDraftError { return voiceDraftError }
        return voiceDraftCount == 0 ? "Nada pendiente" : "\(voiceDraftCount) por revisar o vincular"
    }

    private func dictationTarget(in snapshot: DashboardSnapshot, now: Date = Date()) -> ClaseHorario? {
        let currentMinutes = DateHelpers.minutesSinceMidnight(for: now)
        let classes = snapshot.academicTodayClasses.filter {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if let current = classes.first(where: { item in
            currentMinutes >= DateHelpers.minutes(from: item.horaInicio)
                && currentMinutes < DateHelpers.minutes(from: item.horaFin)
        }) {
            return current
        }

        return classes.first { currentMinutes < DateHelpers.minutes(from: $0.horaInicio) }
    }

    // MARK: - Pendientes

    private func pendingPanel(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pendientes de hoy", systemImage: "bell.fill")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(snapshot.pendingClasses.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(snapshot.pendingClasses.isEmpty ? Color.green : Color.orange, in: Capsule())
            }

            if snapshot.pendingClasses.isEmpty {
                Label("Todo en orden. No tienes pendientes para hoy.", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.pendingClasses) { item in
                        NavigationLink(value: AppRoute.classDetail(id: item.id, title: routeTitle(for: item))) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.resumen) sin marcar como dictada")
                                        .font(.footnote.weight(.black))
                                    Text("\(item.dia) \(item.timeRange)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .webCard()
    }

    // MARK: - Recordatorios

    private var remindersReadCard: some View {
        let reminders = decodedReminders

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recordatorios", systemImage: "note.text")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(reminders.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(reminders) { reminder in
                    ReminderRow(reminder: reminder) {
                        removeReminder(reminder.id)
                    }
                }
            }
        }
        .webCard()
    }

    private var remindersEditorCard: some View {
        let reminders = decodedReminders

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recordatorios", systemImage: "note.text")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(reminders.count)/10")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(ReminderColor.allCases) { color in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            reminderColor = color
                        }
                    } label: {
                        Circle()
                            .fill(color.background)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(reminderColor == color ? EPTheme.primary : Color.clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Agregar recordatorio...", text: $newReminder)
                    .textFieldStyle(.plain)
                    .font(.footnote)
                    .padding(11)
                    .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))

                Button {
                    addReminder()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.white)
                        .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(newReminder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reminders.count >= 10)
            }

            if reminders.isEmpty {
                Text("Sin recordatorios. Agrégalos para tenerlos a mano durante el día.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(reminders) { reminder in
                        ReminderRow(reminder: reminder) {
                            removeReminder(reminder.id)
                        }
                    }
                }
            }
        }
        .webCard()
    }

    // MARK: - Estados

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var noScheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title)
                .foregroundStyle(EPTheme.primary)
            Text("Configura tu horario")
                .font(.title3.bold())
            Text("Cuando agregues tus bloques en Mi Perfil, EduPanel los mostrará aquí para seguir tu jornada.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                onOpenProfile()
            } label: {
                Label("Ir a Mi Perfil", systemImage: "person.crop.circle.fill")
                    .font(.footnote.weight(.black))
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        }
        .webCard()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sin datos para mostrar", systemImage: "tray")
        } description: {
            Text("Revisa tu conexión e inténtalo de nuevo.")
        } actions: {
            Button("Reintentar") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando tu jornada...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Helpers

    private var greetingInfo: GreetingInfo {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 {
            return GreetingInfo(greet: "Buenos días", icon: "sunrise.fill")
        }
        if hour >= 12 && hour < 19 {
            return GreetingInfo(greet: "Buenas tardes", icon: "sun.max.fill")
        }
        return GreetingInfo(greet: "Buenas noches", icon: "moon.fill")
    }

    private var formattedHeroDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return formatter.string(from: Date()).capitalized
    }

    private var decodedReminders: [ReminderNote] {
        guard let data = remindersData.data(using: .utf8),
              let items = try? JSONDecoder().decode([ReminderNote].self, from: data) else {
            return []
        }
        return items
    }

    private func storeReminders(_ items: [ReminderNote]) {
        guard let data = try? JSONEncoder().encode(items),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        remindersData = raw
    }

    private func addReminder() {
        let clean = newReminder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var items = decodedReminders
        items.insert(ReminderNote(text: clean, color: reminderColor), at: 0)
        storeReminders(Array(items.prefix(10)))
        newReminder = ""
    }

    private func removeReminder(_ id: String) {
        storeReminders(decodedReminders.filter { $0.id != id })
    }

    private func routeTitle(for item: ClaseHorario) -> String {
        let title = item.resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.tipo.label : title
    }

    private func isClassCurrent(_ item: ClaseHorario, now: Date) -> Bool {
        guard item.dia == DateHelpers.weekdayName(for: now) else { return false }
        let current = DateHelpers.minutesSinceMidnight(for: now)
        return current >= DateHelpers.minutes(from: item.horaInicio) && current < DateHelpers.minutes(from: item.horaFin)
    }

    private func blockProgress(_ item: ClaseHorario, now: Date) -> Double {
        let start = DateHelpers.minutes(from: item.horaInicio)
        let end = DateHelpers.minutes(from: item.horaFin)
        guard end > start else { return 0 }
        let current = DateHelpers.minutesSinceMidnight(for: now)
        let raw = Double(current - start) / Double(end - start)
        return min(1, max(0, raw))
    }
}

// MARK: - Subvistas

private struct GreetingInfo {
    let greet: String
    let icon: String
}

private struct HeroKPI: View {
    let label: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct QuickAction: View {
    enum Kind {
        case route(AppRoute)
        case action(() -> Void)
    }

    let title: String
    let icon: String
    let colors: [Color]
    var detail = "Abrir"
    let kind: Kind

    var body: some View {
        switch kind {
        case .route(let route):
            NavigationLink(value: route) {
                label
            }
            .buttonStyle(.plain)
        case .action(let action):
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(colors.first ?? EPTheme.primary)
                .frame(width: 38, height: 38)
                .background((colors.first ?? EPTheme.primary).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack {
                Text(detail)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 118, alignment: .leading)
        .padding(14)
        .background(EPTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EPTheme.border, lineWidth: 0.75))
    }
}

private struct VoiceDashboardAction: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(14)
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct TimelineClassRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: ClaseHorario
    let isToday: Bool
    let isCompleted: Bool
    let studentCount: Int
    let route: AppRoute
    let onToggle: () -> Void

    private var isCurrent: Bool {
        guard isToday else { return false }
        let current = DateHelpers.minutesSinceMidnight(for: Date())
        return current >= DateHelpers.minutes(from: item.horaInicio) && current < DateHelpers.minutes(from: item.horaFin)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.5)
        }
    }

    private var compactLayout: some View {
        HStack(spacing: 12) {
            Text(String(item.horaInicio.prefix(5)))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 48, height: 44)
                .background(Color(hex: item.colorHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                        .font(.footnote.weight(.black))
                        .lineLimit(1)

                    statusBadge
                }

                HStack(spacing: 6) {
                    Text(item.timeRange)
                    if item.isAcademic {
                        Label("\(studentCount)", systemImage: "person.2.fill")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if item.isAcademic {
                completionButton

                NavigationLink(value: route) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(EPTheme.subtle, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.timeRange)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Color(hex: item.colorHex),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                Spacer(minLength: 4)
                statusBadge
            }

            Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                .font(.headline.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            if item.isAcademic {
                Label("\(studentCount) estudiantes", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    completionButton

                    NavigationLink(value: route) {
                        Label("Abrir clase", systemImage: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if item.tipo.isFreeBlock {
            BadgeLabel(text: "No lectivo", color: .secondary)
        } else if isCompleted {
            BadgeLabel(text: "Dictada", color: .green)
        } else if isCurrent {
            BadgeLabel(text: "EN CURSO", color: EPTheme.primary)
        }
    }

    private var completionButton: some View {
        Button(action: onToggle) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isCompleted ? .green : Color(.systemGray3))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompleted ? "Marcar como pendiente" : "Marcar como dictada")
    }
}

private struct BadgeLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct ReminderRow: View {
    let reminder: ReminderNote
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(reminder.text)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.black))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .foregroundStyle(reminder.color.foreground)
        .background(reminder.color.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(reminder.color.foreground.opacity(0.18), lineWidth: 1)
        )
    }
}

private enum ReminderColor: String, Codable, CaseIterable, Identifiable {
    case rosa
    case amarillo
    case verde
    case azul

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .rosa: return .pink.opacity(0.16)
        case .amarillo: return .yellow.opacity(0.2)
        case .verde: return .green.opacity(0.16)
        case .azul: return .blue.opacity(0.16)
        }
    }

    var foreground: Color {
        switch self {
        case .rosa: return .pink
        case .amarillo: return .orange
        case .verde: return .green
        case .azul: return .blue
        }
    }
}

private struct ReminderNote: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let color: ReminderColor

    init(id: String = UUID().uuidString, text: String, color: ReminderColor) {
        self.id = id
        self.text = text
        self.color = color
    }
}

private extension View {
    func webCard() -> some View {
        self.padding(16)
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
                    .stroke(EPTheme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 5, y: 1)
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else {
            self = .pink
            return
        }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else {
            self = .pink
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
