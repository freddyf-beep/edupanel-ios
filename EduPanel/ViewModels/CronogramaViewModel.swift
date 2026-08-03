import Foundation
import Observation

struct CronoUnidadInfo: Identifiable, Hashable {
    let unidadId: String
    let nombre: String
    let colorHex: String
    let curso: String

    var id: String { "\(curso)::\(unidadId)" }
}

enum CronoDateHelpers {
    static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "es_CL")
        return calendar
    }

    static let diasSemana = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes"]
    static let diasIndice: [String: Int] = ["Lunes": 0, "Martes": 1, "Miércoles": 2, "Jueves": 3, "Viernes": 4]

    static func semanaISO(_ date: Date) -> Int {
        isoCalendar.component(.weekOfYear, from: date)
    }

    static func anioISO(_ date: Date) -> Int {
        isoCalendar.component(.yearForWeekOfYear, from: date)
    }

    static func lunes(de date: Date) -> Date {
        let calendar = isoCalendar
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    static func lunesDeSemana(_ semana: Int, anio: Int) -> Date {
        let calendar = isoCalendar
        var components = DateComponents()
        components.yearForWeekOfYear = anio
        components.weekOfYear = max(1, min(53, semana))
        components.weekday = 2
        return calendar.date(from: components) ?? Date()
    }

    static func fechaReal(lunes: Date, dia: String) -> Date {
        let offset = diasIndice[dia] ?? 0
        return isoCalendar.date(byAdding: .day, value: offset, to: lunes) ?? lunes
    }

    static func nombreDia(_ date: Date) -> String? {
        let weekday = Calendar.current.component(.weekday, from: date)
        switch weekday {
        case 2: return "Lunes"
        case 3: return "Martes"
        case 4: return "Miércoles"
        case 5: return "Jueves"
        case 6: return "Viernes"
        default: return nil
        }
    }

    static func etiquetaSemana(_ lunes: Date) -> String {
        let viernes = isoCalendar.date(byAdding: .day, value: 4, to: lunes) ?? lunes
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "MMMM"
        let mes = formatter.string(from: viernes)
        let diaLunes = Calendar.current.component(.day, from: lunes)
        let diaViernes = Calendar.current.component(.day, from: viernes)
        return "\(diaLunes) – \(diaViernes) \(mes.capitalized)"
    }

    static func tituloMes(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
}

@MainActor
@Observable
final class CronogramaViewModel {
    var horario: [ClaseHorario] = []
    var cursosDisponibles: [String] = []
    var asignaturasDisponibles: [String] = []
    var actividades: [ActividadCronograma] = []
    var unidades: [CronoUnidadInfo] = []
    var isLoading = false
    var errorMessage: String?
    var saveStatus: ProfileSaveStatus = .idle

    var asignatura = "M\u{00FA}sica"
    var selectedCourseID: String?
    var selectedSubjectID: String?
    var cursoSeleccionado = "__todos__"
    var filtroCursos: Set<String> = []
    var filtroUnidades: Set<String> = []
    var currentDate = Calendar.current.startOfDay(for: Date())

    private let dashboardRepository: DashboardRepository
    private let planificacionRepository: PlanificacionRepository
    private let cronogramaRepository: CronogramaRepository

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loadedActivityCourses: Set<String> = []
    @ObservationIgnored private var activityLoadToken = UUID()

    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        self.cronogramaRepository = CronogramaRepository()
    }

    func load() async {
        if saveStatus == .saving {
            await guardarAhora()
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await dashboardRepository.fetchDashboard()
            horario = snapshot.horario

            let configuredSubjects = snapshot.activeCourses.flatMap(\.subjects).map(\.label)
            let subjects = Self.dedupeSubjects(
                configuredSubjects.isEmpty ? snapshot.preferences.asignaturasHabilitadas : configuredSubjects
            )
            asignaturasDisponibles = subjects
            if let current = subjects.first(where: { Self.subjectKey($0) == Self.subjectKey(asignatura) }) {
                asignatura = current
            } else if let preferred = subjects.first(where: { Self.subjectKey($0) == Self.subjectKey("Música") }) {
                asignatura = preferred
            } else if let primera = subjects.first {
                asignatura = primera
            } else {
                let especialidad = snapshot.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines)
                if !especialidad.isEmpty {
                    asignatura = especialidad
                }
            }

            cursosDisponibles = snapshot.courses
            await cargarActividades()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cargarActividades() async {
        let token = UUID()
        activityLoadToken = token
        let requestedSubject = asignatura
        let requestedCourse = cursoSeleccionado
        let cursos = requestedCourse == "__todos__" ? cursosDisponibles : [requestedCourse]
        var listaActividades: [ActividadCronograma] = []
        var listaUnidades: [CronoUnidadInfo] = []
        var successfullyLoadedCourses = Set<String>()
        var failedCourses: [String] = []

        for curso in cursos {
            let plan = try? await planificacionRepository.cargarPlanCurso(
                asignatura: requestedSubject,
                curso: curso
            )
            guard !Task.isCancelled, activityLoadToken == token else { return }
            var aliasesUnidad: [String: String] = [:]

            if let plan {
                for (index, unit) in plan.units.enumerated() {
                    let localID = String(unit.id)
                    var candidates = PlanificacionRepository.unidadIdCandidates(
                        unit: unit,
                        index: index
                    )
                    candidates.append(slug(unit.name))
                    let rawName = unit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rawName.isEmpty { candidates.append(rawName) }
                    for alias in candidates where !alias.isEmpty {
                        aliasesUnidad[alias] = localID
                    }
                }

                listaUnidades += plan.units.enumerated().map { index, unit in
                    CronoUnidadInfo(
                        unidadId: unidadKey(unit),
                        nombre: unit.name,
                        colorHex: unit.color,
                        curso: curso
                    )
                }
            }

            do {
                let acts = try await cronogramaRepository.cargarActividades(
                    asignatura: requestedSubject,
                    curso: curso
                )
                guard !Task.isCancelled, activityLoadToken == token else { return }
                successfullyLoadedCourses.insert(curso)
                listaActividades += acts.map { actividad in
                    var copia = actividad
                    copia.cursoOrigen = copia.cursoOrigen ?? curso
                    copia.unidad = aliasesUnidad[copia.unidad] ??
                        aliasesUnidad[slug(copia.unidad)] ??
                        copia.unidad
                    return copia
                }
            } catch {
                failedCourses.append(curso)
            }
        }

        guard !Task.isCancelled, activityLoadToken == token else { return }
        actividades = listaActividades
        unidades = listaUnidades
        loadedActivityCourses = successfullyLoadedCourses
        if !failedCourses.isEmpty {
            errorMessage = "No se pudo cargar el cronograma de: \(failedCourses.joined(separator: ", ")). No se sobrescribirán esos cursos."
        }
        isLoading = false
    }

    func seleccionarCurso(_ curso: String) async {
        if saveStatus == .saving {
            await guardarAhora()
        }
        cursoSeleccionado = curso
        if curso != "__todos__" {
            let snapshot = try? await dashboardRepository.fetchDashboard()
            selectedCourseID = snapshot?.course(id: nil, named: curso)?.courseID
            selectedSubjectID = snapshot?.course(id: selectedCourseID, named: curso)?.subjects.first {
                Self.subjectKey($0.label) == Self.subjectKey(asignatura)
            }?.id
        }
        isLoading = true
        await cargarActividades()
    }

    func seleccionarAsignatura(_ nuevaAsignatura: String) async {
        let trimmed = nuevaAsignatura.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.subjectKey(trimmed) != Self.subjectKey(asignatura) else { return }
        if saveStatus == .saving {
            await guardarAhora()
        }
        asignatura = trimmed
        selectedCourseID = nil
        selectedSubjectID = nil
        isLoading = true
        await cargarActividades()
    }

    private func unidadKey(_ unit: UnidadPlan) -> String {
        String(unit.id)
    }

    private func slug(_ texto: String) -> String {
        let folded = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL")).lowercased()
        let mapped = folded.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            let esAlfanumerico = (48...57).contains(value) || (97...122).contains(value)
            return esAlfanumerico ? Character(scalar) : "_"
        }
        return String(mapped)
    }

    private static func dedupeSubjects(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(subjectKey(value)).inserted else { return nil }
            return value
        }
        .sorted { subjectKey($0).localizedStandardCompare(subjectKey($1)) == .orderedAscending }
    }

    private static func subjectKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "_")
    }

    // MARK: - CRUD

    func upsert(_ actividad: ActividadCronograma) {
        if let index = actividades.firstIndex(where: { $0.id == actividad.id }) {
            actividades[index] = actividad
        } else {
            actividades.append(actividad)
        }
        scheduleSave()
    }

    func eliminar(id: String) {
        actividades.removeAll { $0.id == id }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveStatus = .saving
        saveTask = Task {
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            await persist()
        }
    }

    func guardarAhora() async {
        saveTask?.cancel()
        await persist()
    }

    private func persist() async {
        do {
            if cursoSeleccionado == "__todos__" {
                var grupos: [String: [ActividadCronograma]] = [:]
                loadedActivityCourses.forEach { grupos[$0] = [] }
                for actividad in actividades {
                    guard let curso = actividad.cursoOrigen ?? cursosDisponibles.first else { continue }
                    guard loadedActivityCourses.contains(curso) else { continue }
                    grupos[curso, default: []].append(actividad)
                }
                for (curso, lista) in grupos {
                    try await cronogramaRepository.guardarActividades(asignatura: asignatura, curso: curso, actividades: lista)
                }
            } else {
                guard loadedActivityCourses.contains(cursoSeleccionado) else {
                    errorMessage = "No se guardó porque el cronograma de este curso no terminó de cargar."
                    saveStatus = .error
                    return
                }
                try await cronogramaRepository.guardarActividades(asignatura: asignatura, curso: cursoSeleccionado, actividades: actividades)
            }
            saveStatus = .saved
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                if saveStatus == .saved {
                    saveStatus = .idle
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            saveStatus = .error
        }
    }

    // MARK: - Derivados

    var actividadesFiltradas: [ActividadCronograma] {
        actividades.filter { actividad in
            if !filtroCursos.isEmpty, !filtroCursos.contains(actividad.cursoOrigen ?? "") {
                return false
            }
            if !filtroUnidades.isEmpty, !filtroUnidades.contains(actividad.unidad) {
                return false
            }
            return true
        }
    }

    var horarioVisible: [ClaseHorario] {
        horario.filter { bloque in
            guard bloque.isAcademic else { return false }
            return cursoSeleccionado == "__todos__" || bloque.resumen == cursoSeleccionado
        }
    }

    var semanaActual: Int {
        CronoDateHelpers.semanaISO(currentDate)
    }

    var lunesActual: Date {
        CronoDateHelpers.lunes(de: currentDate)
    }

    var anioActual: Int {
        CronoDateHelpers.anioISO(currentDate)
    }

    var unidadesConActividades: Int {
        Set(actividadesFiltradas.map { $0.unidad.isEmpty ? "(sin unidad)" : $0.unidad }).count
    }

    var hayFiltrosActivos: Bool {
        !filtroCursos.isEmpty || !filtroUnidades.isEmpty
    }

    func colorUnidad(_ unidadId: String?) -> String {
        guard let unidadId, !unidadId.isEmpty else { return "#9CA3AF" }
        return unidades.first { $0.unidadId == unidadId }?.colorHex ?? "#F03E6E"
    }

    func nombreUnidad(_ unidadId: String?) -> String {
        guard let unidadId, !unidadId.isEmpty else { return "Sin unidad" }
        return unidades.first { $0.unidadId == unidadId }?.nombre ?? unidadId
    }

    func fecha(de actividad: ActividadCronograma) -> Date {
        let lunes = CronoDateHelpers.lunesDeSemana(actividad.semana, anio: anioActual)
        return CronoDateHelpers.fechaReal(lunes: lunes, dia: actividad.dia)
    }

    func cambiarSemana(_ delta: Int) {
        if let nueva = Calendar.current.date(byAdding: .day, value: delta * 7, to: currentDate) {
            currentDate = nueva
        }
    }

    func cambiarMes(_ delta: Int) {
        if let nueva = Calendar.current.date(byAdding: .month, value: delta, to: currentDate) {
            currentDate = nueva
        }
    }

    func irAHoy() {
        currentDate = Calendar.current.startOfDay(for: Date())
    }

    func nuevaActividad(dia: String, hora: String) -> ActividadCronograma {
        let cursoNueva = cursoSeleccionado == "__todos__" ? (cursosDisponibles.first ?? "") : cursoSeleccionado
        let primeraUnidad = unidades.first { $0.curso == cursoNueva }
        return ActividadCronograma(
            id: "act_\(Int(Date().timeIntervalSince1970 * 1000))",
            nombre: "Nueva actividad",
            tipo: "actividad",
            dia: dia,
            semana: semanaActual,
            hora: hora,
            duracion: "45 min",
            unidad: primeraUnidad?.unidadId ?? "",
            color: primeraUnidad?.colorHex ?? "#F03E6E",
            cursoOrigen: cursoSeleccionado == "__todos__" ? cursoNueva : nil
        )
    }
}
