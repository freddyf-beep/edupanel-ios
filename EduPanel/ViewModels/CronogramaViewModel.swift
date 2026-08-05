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
    static let timeZoneIdentifier = "America/Santiago"

    static var santiagoTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "es_CL")
        calendar.timeZone = santiagoTimeZone
        return calendar
    }

    static var civilCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_CL")
        calendar.timeZone = santiagoTimeZone
        return calendar
    }

    static let diasSemana = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
    static let diasIndice: [String: Int] = [
        "Lunes": 0,
        "Martes": 1,
        "Miércoles": 2,
        "Jueves": 3,
        "Viernes": 4,
        "Sábado": 5
    ]

    static func semanaISO(_ date: Date) -> Int {
        isoCalendar.component(.weekOfYear, from: date)
    }

    static func anioISO(_ date: Date) -> Int {
        isoCalendar.component(.yearForWeekOfYear, from: date)
    }

    static func inicioDia(_ date: Date) -> Date {
        civilCalendar.startOfDay(for: date)
    }

    static func pertenece(_ actividad: ActividadCronograma, alAnioISO anio: Int) -> Bool {
        actividad.anioISO == anio
    }

    static func fecha(de actividad: ActividadCronograma) -> Date {
        let lunes = lunesDeSemana(actividad.semana, anio: actividad.anioISO)
        return fechaReal(lunes: lunes, dia: actividad.dia)
    }

    /// La vista mensual usa año y mes civiles. Una semana ISO puede comenzar en
    /// diciembre y pertenecer al año ISO siguiente (o terminar en enero y
    /// pertenecer al anterior), por lo que no sirve filtrar primero por un solo
    /// `yearForWeekOfYear`.
    static func pertenece(_ actividad: ActividadCronograma, alMesCivilDe date: Date) -> Bool {
        civilCalendar.isDate(fecha(de: actividad), equalTo: date, toGranularity: .month)
    }

    static func lunes(de date: Date) -> Date {
        let calendar = isoCalendar
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2
        return calendar.date(from: components) ?? inicioDia(date)
    }

    static func lunesDeSemana(_ semana: Int, anio: Int) -> Date {
        let calendar = isoCalendar
        var components = DateComponents()
        components.yearForWeekOfYear = anio
        components.weekOfYear = max(1, min(numeroSemanasISO(en: anio), semana))
        components.weekday = 2
        return calendar.date(from: components) ?? Date()
    }

    static func numeroSemanasISO(en anio: Int) -> Int {
        var components = DateComponents()
        components.year = anio
        components.month = 12
        components.day = 28
        components.hour = 12
        guard let december28 = civilCalendar.date(from: components) else { return 52 }
        return isoCalendar.component(.weekOfYear, from: december28)
    }

    static func fechaReal(lunes: Date, dia: String) -> Date {
        let offset = diasIndice[dia] ?? 0
        return isoCalendar.date(byAdding: .day, value: offset, to: lunes) ?? lunes
    }

    static func nombreDia(_ date: Date) -> String? {
        let weekday = isoCalendar.component(.weekday, from: date)
        switch weekday {
        case 2: return "Lunes"
        case 3: return "Martes"
        case 4: return "Miércoles"
        case 5: return "Jueves"
        case 6: return "Viernes"
        case 7: return "Sábado"
        default: return nil
        }
    }

    static func etiquetaSemana(_ lunes: Date) -> String {
        let sabado = isoCalendar.date(byAdding: .day, value: 5, to: lunes) ?? lunes
        let formatter = DateFormatter()
        formatter.calendar = civilCalendar
        formatter.locale = Locale(identifier: "es_CL")
        formatter.timeZone = santiagoTimeZone
        formatter.dateFormat = "MMMM"
        let mes = formatter.string(from: sabado)
        let diaLunes = civilCalendar.component(.day, from: lunes)
        let diaSabado = civilCalendar.component(.day, from: sabado)
        return "\(diaLunes) – \(diaSabado) \(mes.capitalized)"
    }

    static func tituloMes(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = civilCalendar
        formatter.locale = Locale(identifier: "es_CL")
        formatter.timeZone = santiagoTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
}

@MainActor
@Observable
final class CronogramaViewModel {
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
    var currentDate = CronoDateHelpers.inicioDia(Date())

    private let dashboardRepository: DashboardRepository
    private let planificacionRepository: PlanificacionRepository
    private let cronogramaRepository: CronogramaRepository

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var schedulePeriods: [SchedulePeriod] = []
    @ObservationIgnored private var legacySchedule: [ClaseHorario] = []
    /// Preparado para conectar el calendario académico cuando exista un
    /// contrato remoto verificado. El resolver no materializa clases.
    @ObservationIgnored private var academicCalendarEvents: [AcademicCalendarEvent] = []
    @ObservationIgnored private var loadedActivityCourses: Set<String> = []
    @ObservationIgnored private var dirtyActivityCourses: Set<String> = []
    @ObservationIgnored private var activityMutationGeneration = 0
    @ObservationIgnored private var activityLoadToken = UUID()
    @ObservationIgnored private var persistenceInFlight = false
    @ObservationIgnored private var persistenceWaiters: [CheckedContinuation<Void, Never>] = []

    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        self.cronogramaRepository = CronogramaRepository()
    }

    func load() async {
        if !dirtyActivityCourses.isEmpty {
            await guardarAhora()
        }
        guard dirtyActivityCourses.isEmpty else {
            errorMessage = "Hay cambios del cronograma sin guardar. Reintenta antes de recargar."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await dashboardRepository.fetchDashboard()
            schedulePeriods = snapshot.schedulePeriods
            legacySchedule = snapshot.legacySchedule
            academicCalendarEvents = snapshot.academicCalendarEvents

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
            if cursoSeleccionado == "__todos__" {
                selectedCourseID = nil
                selectedSubjectID = nil
            } else if let selected = snapshot.course(id: selectedCourseID, named: cursoSeleccionado) {
                selectedCourseID = selected.courseID
                selectedSubjectID = selected.subjects.first {
                    Self.subjectKey($0.label) == Self.subjectKey(asignatura)
                }?.id
            }
            await cargarActividades()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cargarActividades() async {
        guard dirtyActivityCourses.isEmpty else {
            errorMessage = "Hay cambios del cronograma sin guardar. Reintenta antes de cambiar la vista."
            isLoading = false
            return
        }
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
                    // La colección/documento ya define el curso. Conservar un
                    // `cursoOrigen` embebido y obsoleto podría hacer que una
                    // edición se guardara en el documento equivocado.
                    copia.cursoOrigen = curso
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
        dirtyActivityCourses.removeAll()
        if !failedCourses.isEmpty {
            errorMessage = "No se pudo cargar el cronograma de: \(failedCourses.joined(separator: ", ")). No se sobrescribirán esos cursos."
        }
        isLoading = false
    }

    func seleccionarCurso(_ curso: String) async {
        if !dirtyActivityCourses.isEmpty {
            await guardarAhora()
        }
        guard dirtyActivityCourses.isEmpty else {
            errorMessage = "No se cambió de curso porque quedan cambios sin guardar."
            return
        }
        cursoSeleccionado = curso
        if curso == "__todos__" {
            selectedCourseID = nil
            selectedSubjectID = nil
        } else {
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
        if !dirtyActivityCourses.isEmpty {
            await guardarAhora()
        }
        guard dirtyActivityCourses.isEmpty else {
            errorMessage = "No se cambió de asignatura porque quedan cambios sin guardar."
            return
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

    @discardableResult
    func upsert(_ actividad: ActividadCronograma) -> Bool {
        var normalized = actividad
        normalized.semana = max(
            1,
            min(CronoDateHelpers.numeroSemanasISO(en: normalized.anioISO), normalized.semana)
        )

        let previousActivity = actividades.first { $0.id == normalized.id }
        let affectedCourses = Set([
            previousActivity.flatMap(activityCourse(for:)),
            activityCourse(for: normalized)
        ].compactMap { $0 })
        guard validateWritableCourses(affectedCourses) else { return false }

        if let index = actividades.firstIndex(where: { $0.id == normalized.id }) {
            if let previousCourse = activityCourse(for: actividades[index]) {
                dirtyActivityCourses.insert(previousCourse)
            }
            actividades[index] = normalized
        } else {
            actividades.append(normalized)
        }
        if let course = activityCourse(for: normalized) {
            dirtyActivityCourses.insert(course)
        }
        activityMutationGeneration += 1
        scheduleSave()
        return true
    }

    @discardableResult
    func eliminar(id: String) -> Bool {
        guard let activity = actividades.first(where: { $0.id == id }),
              let course = activityCourse(for: activity),
              validateWritableCourses([course]) else { return false }
        dirtyActivityCourses.insert(course)
        actividades.removeAll { $0.id == id }
        activityMutationGeneration += 1
        scheduleSave()
        return true
    }

    private func activityCourse(for activity: ActividadCronograma) -> String? {
        let raw = activity.cursoOrigen
            ?? (cursoSeleccionado == "__todos__" ? nil : cursoSeleccionado)
        let clean = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? nil : clean
    }

    private func validateWritableCourses(_ courses: Set<String>) -> Bool {
        guard !courses.isEmpty else {
            errorMessage = "Selecciona un curso cuyo cronograma haya terminado de cargar."
            saveStatus = .error
            return false
        }
        let unavailable = courses.subtracting(loadedActivityCourses)
        guard unavailable.isEmpty else {
            errorMessage = "No se puede guardar en \(unavailable.sorted().joined(separator: ", ")) porque su cronograma no terminó de cargar. Recarga e inténtalo nuevamente."
            saveStatus = .error
            return false
        }
        return true
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveStatus = .saving
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            await self?.requestPersistence()
        }
    }

    func guardarAhora() async {
        saveTask?.cancel()
        saveTask = nil
        await requestPersistence()
    }

    /// Mantiene una sola escritura remota en vuelo. Cancelar el debounce no
    /// cancela un commit de Firestore que ya comenzó; esta compuerta evita que
    /// un snapshot antiguo termine después de uno nuevo y lo sobrescriba.
    private func requestPersistence() async {
        guard !dirtyActivityCourses.isEmpty else { return }
        if persistenceInFlight {
            await withCheckedContinuation { continuation in
                persistenceWaiters.append(continuation)
            }
            return
        }

        persistenceInFlight = true
        defer {
            persistenceInFlight = false
            let waiters = persistenceWaiters
            persistenceWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        while !dirtyActivityCourses.isEmpty {
            guard await persistCurrentSnapshot() else { return }
        }

        saveStatus = .saved
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, self.saveStatus == .saved else { return }
            self.saveStatus = .idle
        }
    }

    private func persistCurrentSnapshot() async -> Bool {
        let generation = activityMutationGeneration
        let unavailableCourses = dirtyActivityCourses.subtracting(loadedActivityCourses)
        guard unavailableCourses.isEmpty else {
            errorMessage = "Quedan cambios asociados a cursos que no terminaron de cargar: \(unavailableCourses.sorted().joined(separator: ", ")). Recarga el cronograma e inténtalo nuevamente."
            saveStatus = .error
            return false
        }
        saveStatus = .saving

        do {
            if cursoSeleccionado == "__todos__" {
                var grupos: [String: [ActividadCronograma]] = [:]
                let targetCourses = dirtyActivityCourses.intersection(loadedActivityCourses)
                guard !targetCourses.isEmpty else {
                    errorMessage = "No hay un curso cargado donde guardar estos cambios."
                    saveStatus = .error
                    return false
                }
                targetCourses.forEach { grupos[$0] = [] }
                for actividad in actividades {
                    guard let curso = activityCourse(for: actividad),
                          targetCourses.contains(curso) else { continue }
                    grupos[curso, default: []].append(actividad)
                }
                try await cronogramaRepository.guardarActividades(
                    asignatura: asignatura,
                    actividadesPorCurso: grupos
                )
                if generation == activityMutationGeneration {
                    dirtyActivityCourses.subtract(targetCourses)
                }
            } else {
                guard loadedActivityCourses.contains(cursoSeleccionado) else {
                    errorMessage = "No se guardó porque el cronograma de este curso no terminó de cargar."
                    saveStatus = .error
                    return false
                }
                try await cronogramaRepository.guardarActividades(asignatura: asignatura, curso: cursoSeleccionado, actividades: actividades)
                if generation == activityMutationGeneration {
                    dirtyActivityCourses.remove(cursoSeleccionado)
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            saveStatus = .error
            return false
        }
    }

    // MARK: - Derivados

    private var actividadesAplicandoFiltros: [ActividadCronograma] {
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

    var actividadesFiltradas: [ActividadCronograma] {
        actividadesAplicandoFiltros.filter {
            CronoDateHelpers.pertenece($0, alAnioISO: anioActual)
        }
    }

    var actividadesDelMes: [ActividadCronograma] {
        actividadesAplicandoFiltros.filter {
            CronoDateHelpers.pertenece($0, alMesCivilDe: currentDate)
        }
    }

    var hasUnsavedChanges: Bool { !dirtyActivityCourses.isEmpty }

    var cursosEditables: [String] {
        cursosDisponibles.filter(loadedActivityCourses.contains)
    }

    var puedeCrearActividad: Bool {
        if cursoSeleccionado == "__todos__" {
            return !cursosEditables.isEmpty
        }
        return loadedActivityCourses.contains(cursoSeleccionado)
    }

    var horarioVisible: [ClaseHorario] {
        horarioVisible(on: currentDate)
    }

    /// Resuelve el horario para la fecha que realmente se está mostrando.
    /// Antes se reutilizaba el snapshot de hoy al navegar a otra semana o mes.
    func horarioVisible(on date: Date) -> [ClaseHorario] {
        effectiveSchedule(for: date).filter { bloque in
            guard bloque.isAcademic else { return false }
            guard cursoSeleccionado != "__todos__" else { return true }
            if let selectedCourseID {
                if bloque.courseID == selectedCourseID { return true }
                // Compatibilidad con bloques legacy que aún no tienen ID.
                if bloque.courseID == nil { return bloque.resumen == cursoSeleccionado }
                return false
            }
            return bloque.resumen == cursoSeleccionado
        }
    }

    var horario: [ClaseHorario] {
        effectiveSchedule(for: currentDate)
    }

    private func effectiveSchedule(for date: Date) -> [ClaseHorario] {
        AcademicCalendarResolver.effectiveSchedule(
            periods: schedulePeriods,
            legacy: legacySchedule,
            events: academicCalendarEvents,
            for: date
        )
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
        CronoDateHelpers.fecha(de: actividad)
    }

    func cambiarSemana(_ delta: Int) {
        if let nueva = CronoDateHelpers.isoCalendar.date(byAdding: .day, value: delta * 7, to: currentDate) {
            currentDate = nueva
        }
    }

    func cambiarMes(_ delta: Int) {
        if let nueva = CronoDateHelpers.civilCalendar.date(byAdding: .month, value: delta, to: currentDate) {
            currentDate = nueva
        }
    }

    func irAHoy() {
        currentDate = CronoDateHelpers.inicioDia(Date())
    }

    func nuevaActividad(dia: String, hora: String) -> ActividadCronograma? {
        let cursoNueva = cursoSeleccionado == "__todos__" ? (cursosEditables.first ?? "") : cursoSeleccionado
        guard loadedActivityCourses.contains(cursoNueva) else {
            errorMessage = "Espera a que el cronograma del curso termine de cargar antes de crear una actividad."
            saveStatus = .error
            return nil
        }
        let primeraUnidad = unidades.first { $0.curso == cursoNueva }
        return ActividadCronograma(
            id: "act_\(Int(Date().timeIntervalSince1970 * 1000))",
            nombre: "Nueva actividad",
            tipo: "actividad",
            dia: dia,
            semana: semanaActual,
            anioISO: anioActual,
            hora: hora,
            duracion: "45 min",
            unidad: primeraUnidad?.unidadId ?? "",
            color: primeraUnidad?.colorHex ?? "#F03E6E",
            cursoOrigen: cursoSeleccionado == "__todos__" ? cursoNueva : nil
        )
    }
}
