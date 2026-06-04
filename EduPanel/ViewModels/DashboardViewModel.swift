import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var snapshot: DashboardSnapshot?
    var isLoading = false
    var errorMessage: String?

    private let repository: DashboardRepository

    init(repository: DashboardRepository) {
        self.repository = repository
    }

    var progressTitle: String {
        guard let snapshot else { return "Sin clases" }
        return "\(snapshot.completedAcademicCount) de \(snapshot.totalAcademicCount) clases"
    }

    var progressValue: Double {
        snapshot?.progress ?? 0
    }

    var currentOrNextClass: ClaseHorario? {
        snapshot?.currentOrNextClass()
    }

    func load() async {
        guard snapshot == nil else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            snapshot = try await repository.fetchDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func toggleCompletion(for item: ClaseHorario) async {
        guard var snapshot else { return }
        snapshot.classState[item.id] = !(snapshot.classState[item.id] ?? false)
        self.snapshot = snapshot

        do {
            try await repository.saveClassState(snapshot.classState, for: snapshot.date)
        } catch {
            errorMessage = error.localizedDescription
            await refresh()
        }
    }
}

