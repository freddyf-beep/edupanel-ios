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
    var actividades: [ActividadCronograma] = []
    var unidades: [CronoUnidadInfo] = []
    var isLoading = false
    var errorMessage: String?
    var saveStatus: ProfileSaveStatus = .idle

    var asignatura = "M\u{00FA}sica"
    var cursoSeleccionado = "__todos__"
    var filtroCursos: Set<String> = []
    var filtroUnidades: Set<String> = []
    var currentDate = Calendar.current.startOfDay(for: Date())

    private let dashboardRepository: DashboardRepository
    private let planificacionRepository: PlanificacionRepository
    private let cronogramaRepository: CronogramaRepository

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        self.cronogramaRepository = CronogramaRepository()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snapshot = try await dashboardRepository.fetchDashboard()
            horario = snapshot.horario

            let subjects = snapshot.preferences.asignaturasHabilitadas
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let primera = subjects.first {
                asignatura = primera
            } else {
                let especialidad = snapshot.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines)
                if !especialidad.isEmpty {
                    asignatura = especialidad
                }
            }

            cursosDisponibles = Array(Set(snapshot.academicClasses.map(\.resumen))).sorted()
            await cargarActividades()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cargarActividades() async {
        let cursos = cursoSeleccionado == "__todos__" ? cursosDisponibles : [cursoSeleccionado]
        var listaActividades: [ActividadCronograma] = []
        var listaUnidades: [CronoUnidadInfo] = []

        for curso in cursos {
            if let acts = try? await cronogramaRepository.cargarActividades(asignatura: asignatura, curso: curso) {
                listaActividades += acts.map { actividad in
                    var copia = actividad
                    copia.cursoOrigen = copia.cursoOrigen ?? curso
                    return copia
                }
            }

            if let plan = try? await planificacionRepository.cargarPlanCurso(asignatura: asignatura, curso: curso) {
                listaUnidades += plan.units.enumerated().map { index, unit in
                    CronoUnidadInfo(
                        unidadId: unidadKey(unit, index: index),
                        nombre: unit.name,
                        colorHex: unit.color,
                        curso: curso
                    )
                }
            }
        }

        actividades = listaActividades
        unidades = listaUnidades
    }

    func seleccionarCurso(_ curso: String) async {
        cursoSeleccionado = curso
        isLoading = true
        await cargarActividades()
        isLoading = false
    }

    private func unidadKey(_ unit: UnidadPlan, index: Int) -> String {
        if let curricularId = unit.unidadCurricularId?.trimmingCharacters(in: .whitespacesAndNewlines), !curricularId.isEmpty {
            return curricularId
        }
        let nombre = unit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return nombre.isEmpty ? "unidad_\(index + 1)" : slug(nombre)
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
                cursosDisponibles.forEach { grupos[$0] = [] }
                for actividad in actividades {
                    guard let curso = actividad.cursoOrigen ?? cursosDisponibles.first else { continue }
                    grupos[curso, default: []].append(actividad)
                }
                for (curso, lista) in grupos {
                    try await cronogramaRepository.guardarActividades(asignatura: asignatura, curso: curso, actividades: lista)
                }
            } else {
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
        Calendar.current.component(.year, from: currentDate)
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
