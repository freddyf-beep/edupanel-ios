import Foundation
import Observation

@MainActor
@Observable
final class PlanificacionesViewModel {
    var snapshot: DashboardSnapshot?
    var planes: [PlanificacionCurso] = []
    var isLoading = false
    var errorMessage: String? = nil
    
    private let dashboardRepository: DashboardRepository
    private let planificacionRepository: PlanificacionRepository
    
    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
    }
    
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let snap = try await dashboardRepository.fetchDashboard()
            self.snapshot = snap
            
            let subject = snap.preferences.asignaturasHabilitadas.first ?? "Música"
            self.planes = try await planificacionRepository.listarPlanesCurso(asignatura: subject)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func refresh() async {
        await load()
    }
    
    var activeSubject: String {
        snapshot?.preferences.asignaturasHabilitadas.first ?? "Música"
    }
}
