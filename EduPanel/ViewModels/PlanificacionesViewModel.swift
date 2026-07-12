import Foundation
import Observation

@MainActor
@Observable
final class PlanificacionesViewModel {
    var snapshot: DashboardSnapshot?
    var planes: [PlanificacionCurso] = []
    var cronogramasByUnit: [String: CronogramaUnidadData] = [:]
    var isLoading = false
    var errorMessage: String? = nil
    var selectedSubject: String? = nil
    
    private let dashboardRepository: DashboardRepository
    private let planificacionRepository: PlanificacionRepository
    private static let defaultSubject = "M\u{00FA}sica"
    
    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
    }
    
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snap = try await dashboardRepository.fetchDashboard()
            self.snapshot = snap

            do {
                let profileSubjects = subjects(from: snap)
                let posiblesCursos = Array(Set(snap.courses + Array(snap.studentsByCourse.keys)))
                let loadedPlanes = try await planificacionRepository.listarTodosPlanesCurso(
                    posiblesCursos: posiblesCursos,
                    posiblesAsignaturas: profileSubjects
                )
                var cronogramas: [String: CronogramaUnidadData] = [:]
                let subjects = Set(profileSubjects + loadedPlanes.map(\.asignatura))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                for subject in subjects {
                    let subjectPlanes = loadedPlanes.filter { $0.asignatura == subject }
                    let subjectCronogramas = await planificacionRepository.cargarCronogramas(asignatura: subject, planes: subjectPlanes)
                    cronogramas.merge(subjectCronogramas) { _, new in new }
                }

                self.cronogramasByUnit = cronogramas
                self.planes = Self.enrichPlansWithCronogramaDates(loadedPlanes, cronogramasByUnit: cronogramas)
            } catch {
                self.planes = []
                self.cronogramasByUnit = [:]
                self.errorMessage = "No se pudieron cargar las planificaciones guardadas. Puedes seguir viendo tus cursos."
            }
        } catch {
            self.snapshot = nil
            self.planes = []
            self.cronogramasByUnit = [:]
            self.errorMessage = error.localizedDescription
        }
    }
    
    func refresh() async {
        await load()
    }
    
    var activeSubject: String {
        selectedSubject ?? defaultSubjectFromSnapshot
    }

    var availableSubjects: [String] {
        subjects(from: snapshot)
    }

    private var defaultSubjectFromSnapshot: String {
        subjects(from: snapshot).first ?? Self.defaultSubject
    }

    private func subjects(from snapshot: DashboardSnapshot?) -> [String] {
        if let subject = snapshot?.preferences.asignaturasHabilitadas
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
           !subject.isEmpty {
            return subject
        }

        let specialty = snapshot?.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [specialty.isEmpty ? Self.defaultSubject : specialty]
    }

    private static func enrichPlansWithCronogramaDates(
        _ planes: [PlanificacionCurso],
        cronogramasByUnit: [String: CronogramaUnidadData]
    ) -> [PlanificacionCurso] {
        planes.map { plan in
            var nextPlan = plan
            nextPlan.units = plan.units.map { unit in
                guard !unit.hasDates else { return unit }
                let key = PlanificacionRepository.cronogramaKey(asignatura: plan.asignatura, curso: plan.curso, unidadId: String(unit.id))
                guard let crono = cronogramasByUnit[key],
                      let range = dateRange(from: crono.clases) else {
                    return unit
                }
                var nextUnit = unit
                nextUnit.start = range.start
                nextUnit.end = range.end
                return nextUnit
            }
            return nextPlan
        }
    }

    private static func dateRange(from clases: [ClaseCronograma]) -> (start: String, end: String)? {
        let dates = clases.compactMap { parseDDMMYYYY($0.fecha) }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        return (toISODate(first), toISODate(last))
    }

    private static func parseDDMMYYYY(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func toISODate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
