import AVFoundation
import Observation
import SwiftUI
import UIKit
import VisionKit

protocol AttendanceQRScannerProviding {
    @MainActor
    func currentAvailability() -> AttendanceQRScannerAvailability
    @MainActor
    func requestPermission() async -> AttendanceQRScannerAvailability
    @MainActor
    func scannerView(
        isPaused: Bool,
        onPayload: @escaping (String) -> Void,
        onUnavailable: @escaping (AttendanceQRScannerAvailability) -> Void
    ) -> AnyView
}

struct VisionKitAttendanceQRScannerProvider: AttendanceQRScannerProviding {
    func currentAvailability() -> AttendanceQRScannerAvailability {
        let authorization: AttendanceQRScannerAvailability
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: authorization = .notDetermined
        case .authorized: authorization = .ready
        case .denied: authorization = .denied
        case .restricted: authorization = .restricted
        @unknown default: authorization = .unavailable
        }
        return AttendanceQRScannerCapability.resolve(
            isSupported: DataScannerViewController.isSupported,
            isAvailable: DataScannerViewController.isAvailable,
            authorization: authorization
        )
    }

    func requestPermission() async -> AttendanceQRScannerAvailability {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return currentAvailability()
    }

    func scannerView(
        isPaused: Bool,
        onPayload: @escaping (String) -> Void,
        onUnavailable: @escaping (AttendanceQRScannerAvailability) -> Void
    ) -> AnyView {
        AnyView(AttendanceDataScannerView(
            isPaused: isPaused,
            onPayload: onPayload,
            onUnavailable: onUnavailable
        ))
    }
}

private struct AttendanceDataScannerView: UIViewControllerRepresentable {
    let isPaused: Bool
    let onPayload: (String) -> Void
    let onUnavailable: (AttendanceQRScannerAvailability) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload, onUnavailable: onUnavailable)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        Task { @MainActor in
            context.coordinator.update(paused: isPaused)
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.update(paused: isPaused)
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        scanner.delegate = nil
        coordinator.scanner = nil
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        weak var scanner: DataScannerViewController?
        private let onPayload: (String) -> Void
        private let onUnavailable: (AttendanceQRScannerAvailability) -> Void
        private var paused = true
        private var deliveredCurrentReading = false

        init(
            onPayload: @escaping (String) -> Void,
            onUnavailable: @escaping (AttendanceQRScannerAvailability) -> Void
        ) {
            self.onPayload = onPayload
            self.onUnavailable = onUnavailable
        }

        func update(paused newValue: Bool) {
            guard let scanner else { return }
            if newValue {
                scanner.stopScanning()
                paused = true
                return
            }

            if paused {
                deliveredCurrentReading = false
            }
            paused = false
            guard !scanner.isScanning else { return }
            do {
                try scanner.startScanning()
            } catch {
                onUnavailable(.unavailable)
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !paused, !deliveredCurrentReading else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      !payload.isEmpty else { continue }
                deliveredCurrentReading = true
                dataScanner.stopScanning()
                onPayload(payload)
                return
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            dataScanner.stopScanning()
            switch error {
            case .unsupported:
                onUnavailable(.unsupported)
            case .cameraRestricted:
                onUnavailable(.restricted)
            @unknown default:
                onUnavailable(.unavailable)
            }
        }
    }
}

@MainActor
@Observable
final class AttendanceQRCoordinator {
    private(set) var availability: AttendanceQRScannerAvailability
    private(set) var state: AttendanceQRScanState = .ready
    private(set) var recentScans: [AttendanceQRRecentScan] = []
    private(set) var successFeedbackToken = 0
    private(set) var duplicateFeedbackToken = 0
    private(set) var errorFeedbackToken = 0

    private let attendanceModel: AttendanceViewModel
    private let resolver: any AttendanceQRResolving
    private let scannerProvider: any AttendanceQRScannerProviding
    private var pendingResponse: AttendanceQRResolveResponse?
    private var resumeTask: Task<Void, Never>?

    init(
        attendanceModel: AttendanceViewModel,
        resolver: any AttendanceQRResolving,
        scannerProvider: any AttendanceQRScannerProviding
    ) {
        self.attendanceModel = attendanceModel
        self.resolver = resolver
        self.scannerProvider = scannerProvider
        availability = scannerProvider.currentAvailability()
    }

    var shouldScan: Bool {
        availability == .ready
            && state == .ready
            && attendanceModel.isOnline
            && attendanceModel.activeBlock?.isSigned == false
    }

    var confirmedCount: Int { attendanceModel.summary.confirmedTotal }
    var totalCount: Int { attendanceModel.activeBlock?.attendance.count ?? 0 }

    func prepare() async {
        if attendanceModel.activeBlock?.isSigned == true {
            fail(.signedBlock)
            return
        }
        if !attendanceModel.isOnline {
            fail(.offline)
            return
        }

        availability = scannerProvider.currentAvailability()
        if availability == .notDetermined {
            availability = await scannerProvider.requestPermission()
        }
        if availability == .ready {
            state = .ready
        }
    }

    func process(payload: String) async {
        guard shouldScan else { return }
        guard let scope = attendanceModel.qrScope else {
            fail(.server)
            return
        }

        resumeTask?.cancel()
        pendingResponse = nil
        state = .validating

        do {
            let response = try await resolver.resolve(
                payload: payload,
                scope: scope,
                course: attendanceModel.course
            )
            guard !Task.isCancelled else { return }
            apply(response, allowingConfirmedException: false)
        } catch is CancellationError {
            return
        } catch let failure as AttendanceQRFailure {
            fail(failure)
        } catch {
            fail(.server)
        }
    }

    func confirmException() {
        guard let pendingResponse else { return }
        apply(pendingResponse, allowingConfirmedException: true)
    }

    func declineException() {
        pendingResponse = nil
        state = .ready
    }

    func retry() async {
        pendingResponse = nil
        state = .ready
        await prepare()
    }

    func scannerBecameUnavailable(_ newAvailability: AttendanceQRScannerAvailability) {
        availability = newAvailability
        errorFeedbackToken += 1
    }

    func cancel() {
        resumeTask?.cancel()
        resumeTask = nil
        pendingResponse = nil
    }

    private func apply(
        _ response: AttendanceQRResolveResponse,
        allowingConfirmedException: Bool
    ) {
        let result = attendanceModel.applyResolvedQR(
            response,
            allowingConfirmedException: allowingConfirmedException
        )
        switch result {
        case .applied(_, let studentName):
            pendingResponse = nil
            addRecent(response: response, name: studentName, outcome: .applied)
            state = .success(studentName: studentName)
            successFeedbackToken += 1
            scheduleResume(after: 1.4)
        case .duplicate(let studentName):
            pendingResponse = nil
            addRecent(response: response, name: studentName, outcome: .duplicate)
            state = .duplicate(studentName: studentName)
            duplicateFeedbackToken += 1
            scheduleResume(after: 1.0)
        case .requiresConfirmation(let studentID, let studentName, let previousStatus):
            pendingResponse = response
            state = .requiresConfirmation(
                studentID: studentID,
                studentName: studentName,
                previousStatus: previousStatus
            )
        case .signedBlock:
            fail(.signedBlock)
        case .studentNotFound:
            fail(.studentNotInActiveBlock)
        }
    }

    private func addRecent(
        response: AttendanceQRResolveResponse,
        name: String,
        outcome: AttendanceQRRecentScan.Outcome
    ) {
        recentScans.removeAll { $0.id == response.credentialId }
        recentScans.insert(
            AttendanceQRRecentScan(
                id: response.credentialId,
                studentName: name,
                outcome: outcome,
                scannedAt: Date()
            ),
            at: 0
        )
        if recentScans.count > 4 {
            recentScans.removeLast(recentScans.count - 4)
        }
    }

    private func fail(_ failure: AttendanceQRFailure) {
        pendingResponse = nil
        state = .failure(failure)
        errorFeedbackToken += 1
        if case .rateLimited(let seconds) = failure {
            scheduleResume(after: Double(max(1, seconds ?? 5)))
        }
    }

    private func scheduleResume(after seconds: Double) {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.state = .ready
            self.resumeTask = nil
        }
    }
}

enum AttendanceFullScreenDestination: String, Identifiable {
    case qrScanner

    var id: String { rawValue }
}

struct AttendanceQRScannerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let scannerProvider: any AttendanceQRScannerProviding
    private let onQuickMode: () -> Void
    @State private var coordinator: AttendanceQRCoordinator

    init(
        attendanceModel: AttendanceViewModel,
        resolver: any AttendanceQRResolving,
        scannerProvider: any AttendanceQRScannerProviding,
        onQuickMode: @escaping () -> Void
    ) {
        self.scannerProvider = scannerProvider
        self.onQuickMode = onQuickMode
        _coordinator = State(initialValue: AttendanceQRCoordinator(
            attendanceModel: attendanceModel,
            resolver: resolver,
            scannerProvider: scannerProvider
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            scannerProvider.scannerView(
                isPaused: !coordinator.shouldScan,
                onPayload: { payload in
                    Task { await coordinator.process(payload: payload) }
                },
                onUnavailable: { availability in
                    coordinator.scannerBecameUnavailable(availability)
                }
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            LinearGradient(
                colors: [.black.opacity(0.48), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            overlay
        }
        .task { await coordinator.prepare() }
        .onDisappear { coordinator.cancel() }
        .sensoryFeedback(.success, trigger: coordinator.successFeedbackToken)
        .sensoryFeedback(.selection, trigger: coordinator.duplicateFeedbackToken)
        .sensoryFeedback(.error, trigger: coordinator.errorFeedbackToken)
        .interactiveDismissDisabled(coordinator.state == .validating)
    }

    @ViewBuilder
    private var overlay: some View {
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassOverlay
        } else {
            fallbackOverlay
        }
#else
        fallbackOverlay
#endif
    }

#if compiler(>=6.2)
    @available(iOS 26, *)
    private var glassOverlay: some View {
        GlassEffectContainer(spacing: 18) {
            overlayLayout(useGlass: true)
        }
    }
#endif

    private var fallbackOverlay: some View {
        overlayLayout(useGlass: false)
    }

    private func overlayLayout(useGlass: Bool) -> some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    scannerHeader(useGlass: useGlass)

                    Spacer(minLength: 10)

                    scannerStatus(useGlass: useGlass)

                    Spacer(minLength: 10)

                    if !coordinator.recentScans.isEmpty {
                        recentScansPanel(useGlass: useGlass)
                    }

                    scannerControls(useGlass: useGlass)
                }
                .frame(minHeight: max(0, proxy.size.height - 22))
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func scannerHeader(useGlass: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Escanear asistencia")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(coordinator.confirmedCount) de \(coordinator.totalCount) confirmados")
                        .font(.caption.weight(.semibold))
                        .opacity(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finalizar escaneo")
            }

            ProgressView(
                value: Double(coordinator.confirmedCount),
                total: Double(max(1, coordinator.totalCount))
            )
            .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(14)

        if useGlass {
#if compiler(>=6.2)
            if #available(iOS 26, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
#endif
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func scannerStatus(useGlass: Bool) -> some View {
        let content = VStack(spacing: 12) {
            statusIcon
                .font(.system(size: 34, weight: .bold))

            Text(statusTitle)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(statusMessage)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            statusActions
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: 330)

        if useGlass {
#if compiler(>=6.2)
            if #available(iOS 26, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
#endif
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if coordinator.availability != .ready {
            Image(systemName: availabilityIcon)
        } else {
            switch coordinator.state {
            case .ready:
                Image(systemName: "viewfinder")
            case .validating:
                ProgressView().controlSize(.large).tint(.white)
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .duplicate:
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
            case .requiresConfirmation:
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.orange)
            case .failure:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    private var statusTitle: String {
        guard coordinator.availability == .ready else { return availabilityTitle }
        switch coordinator.state {
        case .ready: return "Listo para escanear"
        case .validating: return "Validando tarjeta"
        case .success(let name): return "\(name) está presente"
        case .duplicate(let name): return "\(name) ya estaba presente"
        case .requiresConfirmation: return "¿Cambiar a presente?"
        case .failure: return "No se pudo aplicar el QR"
        }
    }

    private var statusMessage: String {
        guard coordinator.availability == .ready else { return availabilityMessage }
        switch coordinator.state {
        case .ready:
            return "Acerca una tarjeta QR al recuadro. La validaremos online antes de cambiar la lista."
        case .validating:
            return "Espera un momento. La asistencia todavía no ha cambiado."
        case .success:
            return "Registro confirmado con QR. Puedes continuar con otra tarjeta."
        case .duplicate:
            return "No hicimos una segunda modificación. Puedes continuar."
        case .requiresConfirmation(_, let name, let previousStatus):
            return "\(name) figura como \(previousStatus.title.lowercased()). Confirma el cambio antes de continuar."
        case .failure(let failure):
            return failure.localizedDescription
        }
    }

    @ViewBuilder
    private var statusActions: some View {
        if coordinator.availability == .denied {
            Button("Abrir Configuración") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        } else if coordinator.availability == .unavailable {
            Button("Comprobar cámara") {
                Task { await coordinator.retry() }
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        } else if coordinator.availability == .ready {
            switch coordinator.state {
            case .requiresConfirmation:
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 10) { exceptionButtons }
                    } else {
                        HStack(spacing: 10) { exceptionButtons }
                    }
                }
            case .failure(let failure):
                VStack(spacing: 8) {
                    if failure != .signedBlock {
                        Button("Intentar nuevamente") {
                            Task { await coordinator.retry() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EPTheme.primary)
                    }
                    if failure == .offline || failure == .timeout || failure == .temporarilyUnavailable {
                        Button("Usar modo rápido", action: onQuickMode)
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var exceptionButtons: some View {
                    Button("Mantener estado") { coordinator.declineException() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Cambiar a presente") { coordinator.confirmException() }
                        .buttonStyle(.borderedProminent)
                        .tint(EPTheme.primary)
    }

    @ViewBuilder
    private func recentScansPanel(useGlass: Bool) -> some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            Text("Últimas lecturas")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))

            ForEach(coordinator.recentScans) { scan in
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) { recentScanContent(scan) }
                    } else {
                        HStack(spacing: 8) { recentScanContent(scan) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)

        if useGlass {
#if compiler(>=6.2)
            if #available(iOS 26, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
#endif
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder
    private func recentScanContent(_ scan: AttendanceQRRecentScan) -> some View {
                    Image(systemName: scan.outcome == .applied ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(.green)
                    Text(scan.studentName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(scan.outcome == .applied ? "Presente" : "Duplicado")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
    }

    @ViewBuilder
    private func scannerControls(useGlass: Bool) -> some View {
        let content = Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { scannerControlButtons }
            } else {
                HStack(spacing: 12) { scannerControlButtons }
            }
        }
        .padding(10)

        if useGlass {
#if compiler(>=6.2)
            if #available(iOS 26, *) {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            }
#endif
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private var scannerControlButtons: some View {
            Button(action: onQuickMode) {
                Label("Modo rápido", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button {
                dismiss()
            } label: {
                Label("Finalizar", systemImage: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
    }

    private var availabilityTitle: String {
        switch coordinator.availability {
        case .notDetermined: return "Preparando la cámara"
        case .denied: return "Permiso de cámara desactivado"
        case .restricted: return "Cámara restringida"
        case .unavailable: return "Cámara no disponible"
        case .unsupported: return "Escáner no compatible"
        case .ready: return "Listo para escanear"
        }
    }

    private var availabilityMessage: String {
        switch coordinator.availability {
        case .notDetermined:
            return "EduPanel solicitará permiso para leer las tarjetas de asistencia."
        case .denied:
            return "Activa la cámara en Configuración para escanear tarjetas. La lista manual sigue disponible."
        case .restricted:
            return "Las restricciones de este iPhone impiden usar la cámara. Puedes continuar con el modo rápido."
        case .unavailable:
            return "Otra app puede estar usando la cámara. Ciérrala y vuelve a comprobar."
        case .unsupported:
            return "Este dispositivo no admite el escáner nativo. Usa la lista o el modo rápido."
        case .ready:
            return "Acerca una tarjeta QR para comenzar."
        }
    }

    private var availabilityIcon: String {
        switch coordinator.availability {
        case .notDetermined: return "camera.fill"
        case .denied: return "camera.fill.badge.ellipsis"
        case .restricted: return "lock.fill"
        case .unavailable: return "camera.fill.badge.xmark"
        case .unsupported: return "iphone.slash"
        case .ready: return "viewfinder"
        }
    }
}

#if DEBUG
struct AttendanceQRPreviewScannerProvider: AttendanceQRScannerProviding {
    func currentAvailability() -> AttendanceQRScannerAvailability { .ready }
    func requestPermission() async -> AttendanceQRScannerAvailability { .ready }

    func scannerView(
        isPaused: Bool,
        onPayload: @escaping (String) -> Void,
        onUnavailable: @escaping (AttendanceQRScannerAvailability) -> Void
    ) -> AnyView {
        AnyView(AttendanceQRPreviewCamera(isPaused: isPaused, onPayload: onPayload))
    }
}

private struct AttendanceQRPreviewCamera: View {
    let isPaused: Bool
    let onPayload: (String) -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.8), Color.black, EPTheme.primary.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(isPaused ? 0.25 : 0.85), style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .frame(width: 230, height: 230)
                .overlay {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 84, weight: .thin))
                        .foregroundStyle(.white.opacity(0.72))
                }

            VStack {
                HStack(spacing: 10) {
                    Button("Diego") { onPayload("preview-valid") }
                    Button("Excepción") { onPayload("preview-exception") }
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(isPaused)
                .padding(.top, 165)

                Spacer()
            }
        }
    }
}
#endif
