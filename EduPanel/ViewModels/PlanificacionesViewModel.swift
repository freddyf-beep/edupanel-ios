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
    
    private let dashboardRepository: DashboardRepository
    private let planificacionRepository: PlanificacionRepository
    private static let defaultSubject = "M\u{00FA}sica"
    
    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
    }
    
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snap = try await dashboardRepository.fetchDashboard()
            self.snapshot = snap

            do {
                let subject = subject(from: snap)
                let loadedPlanes = try await planificacionRepository.listarPlanesCurso(asignatura: subject)
                self.planes = loadedPlanes
                self.cronogramasByUnit = await planificacionRepository.cargarCronogramas(asignatura: subject, planes: loadedPlanes)
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
        subject(from: snapshot)
    }

    private func subject(from snapshot: DashboardSnapshot?) -> String {
        if let subject = snapshot?.preferences.asignaturasHabilitadas
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return subject
        }

        let specialty = snapshot?.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return specialty.isEmpty ? Self.defaultSubject : specialty
    }
}
