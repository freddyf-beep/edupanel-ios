import Observation
import SwiftUI

enum ProfileSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case error

    var title: String {
        switch self {
        case .idle: return ""
        case .saving: return "Guardando"
        case .saved: return "Guardado"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .saving: return .blue
        case .saved: return .green
        case .error: return .red
        }
    }
}

@MainActor
@Observable
final class ProfileViewModel {
    var snapshot: DashboardSnapshot?
    var draftProfile = PerfilUsuario.empty
    var draftSchool = InfoColegio.empty
    var draftPreferences = PreferenciasUsuario.empty
    var draftNivelMapping: [String: String] = [:]
    var draftCursoTipos: [String: TipoCurricular] = [:]
    var isLoading = false
    var errorMessage: String?
    var operationMessage: String?
    var saveProfileStatus: ProfileSaveStatus = .idle
    var saveSchoolStatus: ProfileSaveStatus = .idle
    var savePreferencesStatus: ProfileSaveStatus = .idle
    var saveMappingStatus: ProfileSaveStatus = .idle
    var saveHorarioStatus: ProfileSaveStatus = .idle
    var saveStudentsStatus: ProfileSaveStatus = .idle

    let repository: DashboardRepository

    @ObservationIgnored private var horarioSaveTask: Task<Void, Never>?
    @ObservationIgnored private var mappingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesSaveTask: Task<Void, Never>?
    @ObservationIgnored private var schoolSaveTask: Task<Void, Never>?

    init(repository: DashboardRepository) {
        self.repository = repository
    }

    func load() async {
        guard snapshot == nil else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard(forceRefresh: true)
            snapshot = next
            draftProfile = next.profile
            draftSchool = next.school
            draftPreferences = next.preferences
            draftNivelMapping = next.nivelMapping
            draftCursoTipos = next.cursoTipos
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Guardado de documentos simples

    func saveProfile() async {
        saveProfileStatus = .saving
        do {
            try await repository.saveProfile(draftProfile)
            if var snapshot {
                snapshot.profile = draftProfile
                self.snapshot = snapshot
            }
            saveProfileStatus = .saved
            resetLater(\.saveProfileStatus)
        } catch {
            errorMessage = error.localizedDescription
            saveProfileStatus = .error
        }
    }

    func saveSchool() async {
        saveSchoolStatus = .saving
        do {
            try await repository.saveSchool(draftSchool)
            if var snapshot {
                snapshot.school = draftSchool
                self.snapshot = snapshot
            }
            saveSchoolStatus = .saved
            resetLater(\.saveSchoolStatus)
        } catch {
            errorMessage = error.localizedDescription
            saveSchoolStatus = .error
        }
    }

    func saveSchoolDebounced() {
        schoolSaveTask?.cancel()
        saveSchoolStatus = .saving
        schoolSaveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.8))
            } catch {
                return
            }
            await saveSchool()
        }
    }

    func savePreferences() async {
        savePreferencesStatus = .saving
        do {
            try await repository.savePreferences(draftPreferences)
            if var snapshot {
                snapshot.preferences = draftPreferences
                self.snapshot = snapshot
            }
            savePreferencesStatus = .saved
            resetLater(\.savePreferencesStatus)
        } catch {
            errorMessage = error.localizedDescription
            savePreferencesStatus = .error
        }
    }

    func savePreferencesDebounced() {
        preferencesSaveTask?.cancel()
        savePreferencesStatus = .saving
        preferencesSaveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            await savePreferences()
        }
    }

    func saveLevelMapping() async {
        saveMappingStatus = .saving
        do {
            try await repository.saveLevelMapping(draftNivelMapping, cursoTipos: draftCursoTipos)
            if var snapshot {
                snapshot.nivelMapping = draftNivelMapping
                snapshot.cursoTipos = draftCursoTipos
                self.snapshot = snapshot
            }
            saveMappingStatus = .saved
            resetLater(\.saveMappingStatus)
        } catch {
            errorMessage = error.localizedDescription
            saveMappingStatus = .error
        }
    }

    func saveMappingDebounced() {
        mappingSaveTask?.cancel()
        saveMappingStatus = .saving
        mappingSaveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            await saveLevelMapping()
        }
    }

    func toggleConnection(type: String, isConnected: Bool) async {
        var calConn = draftPreferences.googleCalendarConnected
        var drvConn = draftPreferences.googleDriveConnected

        if type == "calendar" {
            calConn = isConnected
        } else if type == "drive" {
            drvConn = isConnected
        }

        do {
            try await repository.saveConnections(googleCalendarConnected: calConn, googleDriveConnected: drvConn)
            draftPreferences.googleCalendarConnected = calConn
            draftPreferences.googleDriveConnected = drvConn
            if var snapshot {
                snapshot.preferences = draftPreferences
                self.snapshot = snapshot
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Horario (bloques)

    var horarioActual: [ClaseHorario] {
        snapshot?.horario ?? []
    }

    func upsertBloque(_ bloque: ClaseHorario) {
        guard var snap = snapshot else { return }
        if let index = snap.horario.firstIndex(where: { $0.id == bloque.id }) {
            snap.horario[index] = bloque
        } else {
            snap.horario.append(bloque)
        }
        snapshot = snap
        scheduleHorarioSave()
    }

    func upsertBloques(_ bloques: [ClaseHorario]) async -> Bool {
        guard var snap = snapshot else { return false }
        do {
            let replacing = Set(bloques.map(\.id))
            let existing = snap.horario.filter { !replacing.contains($0.id) }
            try AcademicContract.validateBatch(existing: existing, candidates: bloques, journey: snap.journey)
            snap.horario = existing + bloques
            if let activeID = snap.activeSchedulePeriodID,
               let index = snap.schedulePeriods.firstIndex(where: { $0.periodID == activeID }) {
                snap.schedulePeriods[index].blocks = snap.horario
            }
            snapshot = snap
            saveHorarioStatus = .saving
            try await repository.saveHorario(snap.horario)
            saveHorarioStatus = .saved
            resetLater(\.saveHorarioStatus)
            return true
        } catch {
            errorMessage = error.localizedDescription
            saveHorarioStatus = .error
            return false
        }
    }

    func removeBloque(id: String) {
        guard var snap = snapshot else { return }
        snap.horario.removeAll { $0.id == id }
        snapshot = snap
        scheduleHorarioSave()
    }

    func removeCurso(_ curso: String) {
        guard var snap = snapshot else { return }
        snap.horario.removeAll { $0.resumen == curso && !$0.tipo.isFreeBlock }
        snapshot = snap
        if draftNivelMapping.removeValue(forKey: curso) != nil || draftCursoTipos.removeValue(forKey: curso) != nil {
            saveMappingDebounced()
        }
        scheduleHorarioSave()
    }

    func renameCurso(_ oldName: String, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != oldName, var snap = snapshot else { return }

        if let index = snap.courseCatalog.firstIndex(where: { $0.name == oldName }) {
            guard snap.courseCatalog[index].kind == .taller else { return }
            snap.courseCatalog[index].name = clean
            snap.courseCatalog[index].workshopName = clean
            let updatedCourse = snap.courseCatalog[index]
            snap.horario = snap.horario.map { block in
                block.courseID == updatedCourse.courseID || block.resumen == oldName ? block.copia(resumen: clean) : block
            }
            snapshot = snap
            Task {
                await saveCourse(updatedCourse)
                try? await repository.saveHorario(snap.horario)
            }
            return
        }

        snap.horario = snap.horario.map { bloque in
            bloque.resumen == oldName ? bloque.copia(resumen: clean) : bloque
        }

        if let students = snap.studentsByCourse.removeValue(forKey: oldName) {
            snap.studentsByCourse[clean] = students
            snap.studentCounts.removeValue(forKey: oldName)
            snap.studentCounts[clean] = students.count
            Task {
                try? await repository.saveStudents(students, for: clean)
            }
        }

        var mappingChanged = false
        if let nivel = draftNivelMapping.removeValue(forKey: oldName) {
            draftNivelMapping[clean] = nivel
            mappingChanged = true
        }
        if let tipo = draftCursoTipos.removeValue(forKey: oldName) {
            draftCursoTipos[clean] = tipo
            mappingChanged = true
        }

        snapshot = snap
        scheduleHorarioSave()
        if mappingChanged {
            saveMappingDebounced()
        }
    }

    func saveCourse(_ course: AcademicCourse) async {
        do {
            let previous = snapshot?.courseCatalog.first(where: { $0.courseID == course.courseID })
            try await repository.saveCourse(course, previousDataKey: previous?.dataKey)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func curriculumSubjects(for level: String) async -> [CurriculumSubjectOption] {
        do {
            return try await repository.getCurriculumSubjectsForLevel(level)
        } catch {
            errorMessage = error.localizedDescription
            return AcademicContract.subjects(for: level)
        }
    }

    func archiveCourse(_ courseID: String) async {
        guard let snap = snapshot, let course = snap.courseCatalog.first(where: { $0.courseID == courseID }) else { return }
        do {
            try await repository.archiveCourse(course, currentSchedule: snap.horario)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreCourse(_ courseID: String) async {
        guard let course = snapshot?.courseCatalog.first(where: { $0.courseID == courseID }) else { return }
        do {
            let result = try await repository.restoreCourse(course)
            operationMessage = result.conflicts == 0
                ? "Curso restaurado con \(result.restored) bloque(s)."
                : "Curso restaurado. \(result.conflicts) bloque(s) quedaron pendientes por conflictos de horario."
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletionImpactSummary(for course: AcademicCourse) async -> String? {
        guard course.isDeleteEligible, let snapshot else { return nil }
        do {
            let config: AppConfig
            switch AppConfig.load() {
            case .success(let value): config = value
            case .failure(let issue): throw issue
            }
            let client = APIClient(config: config)
            let response = try await client.postJSONObject(
                "/api/courses/\(course.courseID)/preview-delete",
                body: ["schoolId": snapshot.schoolID]
            )
            guard let impact = response["impact"] as? [String: Any] else {
                throw APIClientError.invalidResponse
            }
            let blocks = impact["scheduleBlocks"] as? Int ?? 0
            let periods = impact["schedulePeriods"] as? Int ?? 0
            let rosters = impact["studentRosters"] as? Int ?? 0
            let documents = impact["totalDocuments"] as? Int ?? 0
            return "Se eliminarán \(documents) documentos, \(blocks) bloques en \(periods) periodos y \(rosters) listas de estudiantes. No se tocarán sistemas externos."
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func permanentlyDeleteCourse(_ course: AcademicCourse, exactName: String) async -> Bool {
        guard course.isDeleteEligible, exactName == course.name, let snapshot else { return false }
        do {
            let config: AppConfig
            switch AppConfig.load() {
            case .success(let value): config = value
            case .failure(let issue): throw issue
            }
            let client = APIClient(config: config)
            struct Request: Encodable { let schoolId: String; let exactName: String }
            struct Response: Decodable { let success: Bool }
            let response: Response = try await client.delete(
                "/api/courses/\(course.courseID)",
                body: Request(schoolId: snapshot.schoolID, exactName: exactName)
            )
            if response.success { await refresh() }
            return response.success
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importLegacyCourses() async {
        guard let snapshot else { return }
        do {
            _ = try await repository.importLegacyCourses(
                schedule: snapshot.horario,
                levelMapping: snapshot.nivelMapping,
                courseKinds: snapshot.cursoTipos
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveJourney(_ journey: JourneyConfig) async -> Bool {
        do {
            try await repository.saveJourney(journey)
            if var snapshot { snapshot.journey = journey; self.snapshot = snapshot }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveSchedulePeriod(_ period: SchedulePeriod) async -> Bool {
        guard var snapshot else { return false }
        do {
            try AcademicContract.validatePublishedPeriod(period, among: snapshot.schedulePeriods)
            try await repository.saveSchedule(period, schoolID: snapshot.schoolID, journey: snapshot.journey)
            if let index = snapshot.schedulePeriods.firstIndex(where: { $0.periodID == period.periodID }) {
                snapshot.schedulePeriods[index] = period
            } else {
                snapshot.schedulePeriods.append(period)
            }
            snapshot.activeSchedulePeriodID = AcademicContract.resolvePublishedPeriod(snapshot.schedulePeriods, for: snapshot.date)?.periodID
            if snapshot.activeSchedulePeriodID == period.periodID { snapshot.horario = period.blocks }
            self.snapshot = snapshot
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func recolorCurso(_ curso: String, colorHex: String) {
        guard var snap = snapshot else { return }
        if let index = snap.courseCatalog.firstIndex(where: { $0.name == curso }) {
            snap.courseCatalog[index].colorHex = colorHex
            let updated = snap.courseCatalog[index]
            snap.horario = snap.horario.map { block in
                block.courseID == updated.courseID || block.resumen == curso ? block.copia(colorHex: colorHex) : block
            }
            snapshot = snap
            Task {
                await saveCourse(updated)
                try? await repository.saveHorario(snap.horario)
            }
            return
        }
        snap.horario = snap.horario.map { bloque in
            bloque.resumen == curso ? bloque.copia(colorHex: colorHex) : bloque
        }
        snapshot = snap
        scheduleHorarioSave()
    }

    private func scheduleHorarioSave() {
        horarioSaveTask?.cancel()
        saveHorarioStatus = .saving
        horarioSaveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.4))
            } catch {
                return
            }
            await persistHorario()
        }
    }

    private func persistHorario() async {
        guard let horario = snapshot?.horario else { return }
        do {
            try await repository.saveHorario(horario)
            saveHorarioStatus = .saved
            resetLater(\.saveHorarioStatus)
        } catch {
            errorMessage = error.localizedDescription
            saveHorarioStatus = .error
        }
    }

    // MARK: - Estudiantes

    func students(for curso: String) -> [EstudiantePerfil] {
        guard let snapshot else { return [] }
        let key = snapshot.course(id: nil, named: curso)?.courseID ?? curso
        return (snapshot.studentsByCourse[key] ?? snapshot.studentsByCourse[curso] ?? []).sorted {
            if $0.orden != $1.orden { return $0.orden < $1.orden }
            return $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending
        }
    }

    func updateStudents(curso: String, _ transform: ([EstudiantePerfil]) -> [EstudiantePerfil]) {
        guard var snap = snapshot else { return }
        let key = snap.course(id: nil, named: curso)?.courseID ?? curso
        let next = transform(snap.studentsByCourse[key] ?? snap.studentsByCourse[curso] ?? [])
        snap.studentsByCourse[key] = next
        snap.studentCounts[key] = next.count
        snapshot = snap
    }

    func saveStudents(curso: String) async {
        guard let snapshot else { return }
        let key = snapshot.course(id: nil, named: curso)?.courseID ?? curso
        guard let list = snapshot.studentsByCourse[key] ?? snapshot.studentsByCourse[curso] else { return }
        saveStudentsStatus = .saving
        do {
            try await repository.saveStudents(list, for: curso)
            saveStudentsStatus = .saved
            resetLater(\.saveStudentsStatus)
        } catch {
            errorMessage = error.localizedDescription
            saveStudentsStatus = .error
        }
    }

    // MARK: - Helpers

    private func resetLater(_ keyPath: ReferenceWritableKeyPath<ProfileViewModel, ProfileSaveStatus>) {
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if self[keyPath: keyPath] == .saved {
                self[keyPath: keyPath] = .idle
            }
        }
    }
}

extension ProfileViewModel {
    func courseSummaries(for snapshot: DashboardSnapshot) -> [ProfileCourseSummary] {
        let configured: [(String, AcademicCourse?)] = snapshot.courseCatalog.isEmpty
            ? snapshot.courses.map { ($0, nil) }
            : snapshot.courseCatalog.map { ($0.name, $0) }
        return configured.map { course, config in
            let blocks = snapshot.academicClasses.filter { $0.courseID == config?.courseID || $0.resumen == course }
            let minutes = blocks.reduce(0) { total, item in
                total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            }
            let students = snapshot.students(forCourseID: config?.courseID, name: course)
            let subjects = config?.subjects.map(\.label) ?? Array(Set(blocks.compactMap(\.asignatura))).sorted()
            let type: TipoCurricular = config?.kind == .taller ? .taller : (draftCursoTipos[course] ?? .oficial)
            return ProfileCourseSummary(
                courseID: config?.courseID ?? course,
                dataKey: config?.dataKey ?? DashboardRepository.buildCursoId(course),
                name: course,
                colorHex: blocks.first?.colorHex ?? "#EC4899",
                blocks: blocks.count,
                minutes: minutes,
                students: students.count,
                pie: students.filter(\.pie).count,
                level: config?.level ?? draftNivelMapping[course],
                type: type,
                subjects: subjects,
                weeklyBlocks: blocks.sorted {
                    let leftDay = DateHelpers.scheduleDays.firstIndex(of: $0.dia) ?? 0
                    let rightDay = DateHelpers.scheduleDays.firstIndex(of: $1.dia) ?? 0
                    if leftDay != rightDay { return leftDay < rightDay }
                    return $0.horaInicio < $1.horaInicio
                },
                studentsList: students.sorted { $0.orden < $1.orden },
                academicKind: config?.kind,
                status: config?.status ?? .active
            )
        }.filter { $0.status == .active }
    }
}

extension ClaseHorario {
    func copia(
        resumen: String? = nil,
        dia: String? = nil,
        horaInicio: String? = nil,
        horaFin: String? = nil,
        colorHex: String? = nil,
        tipo: TipoHorario? = nil,
        asignatura: String?? = nil
    ) -> ClaseHorario {
        ClaseHorario(
            id: id,
            resumen: resumen ?? self.resumen,
            dia: dia ?? self.dia,
            horaInicio: horaInicio ?? self.horaInicio,
            horaFin: horaFin ?? self.horaFin,
            colorHex: colorHex ?? self.colorHex,
            tipo: tipo ?? self.tipo,
            asignatura: asignatura ?? self.asignatura,
            courseID: courseID,
            subjectID: subjectID,
            moduleID: moduleID,
            exceptional: exceptional
        )
    }
}
