import Foundation
import Network
import Observation

@MainActor
@Observable
final class AttendanceConnectivity {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "cl.edupanel.attendance-connectivity")

    private(set) var isOnline = true

    init(startMonitoring: Bool = true) {
        monitor = NWPathMonitor()
        guard startMonitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
