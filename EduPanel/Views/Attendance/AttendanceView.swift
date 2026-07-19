import SwiftUI
import UIKit

struct AttendanceView: View {
    @State private var model: AttendanceViewModel
    @State private var presentedSheet: AttendanceSheetDestination?
    @State private var presentedFullScreen: AttendanceFullScreenDestination?

    private let qrResolver: any AttendanceQRResolving
    private let scannerProvider: any AttendanceQRScannerProviding

    init(
        course: String,
        subject: String,
        date: Date,
        initialBlockID: String?,
        dashboardRepository: DashboardRepository,
        apiClient: APIClient,
        repository: any AttendanceRepositoryProtocol = AttendanceRepository(),
        scannerProvider: any AttendanceQRScannerProviding = VisionKitAttendanceQRScannerProvider()
    ) {
        _model = State(initialValue: AttendanceViewModel(
            course: course,
            subject: subject,
            date: date,
            initialBlockID: initialBlockID,
            dashboardRepository: dashboardRepository,
            repository: repository
        ))
        qrResolver = AttendanceQRAPIResolver(client: apiClient)
        self.scannerProvider = scannerProvider
    }

    #if DEBUG
    init(
        previewModel: AttendanceViewModel,
        startsWithQRScanner: Bool = false,
        qrResolver: any AttendanceQRResolving = AttendanceQRPreviewResolver(),
        scannerProvider: any AttendanceQRScannerProviding = AttendanceQRPreviewScannerProvider()
    ) {
        _model = State(initialValue: previewModel)
        _presentedFullScreen = State(initialValue: startsWithQRScanner ? .qrScanner : nil)
        self.qrResolver = qrResolver
        self.scannerProvider = scannerProvider
    }
    #endif

    var body: some View {
        content
            .background(EPTheme.background)
            .navigationTitle("Asistencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { attendanceToolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.loadState == .loaded, model.activeBlock != nil {
                    AttendanceActionBar(model: model, presentedSheet: $presentedSheet)
                }
            }
            .sheet(item: $presentedSheet) { destination in
                AttendanceSheetHost(destination: destination, model: model)
            }
            .fullScreenCover(item: $presentedFullScreen) { destination in
                switch destination {
                case .qrScanner:
                    AttendanceQRScannerScreen(
                        attendanceModel: model,
                        resolver: qrResolver,
                        scannerProvider: scannerProvider,
                        onQuickMode: openQuickModeFromScanner
                    )
                }
            }
            .alert(
                "No pudimos completar la acción",
                isPresented: Binding(
                    get: { model.actionError != nil },
                    set: { isPresented in if !isPresented { model.dismissError() } }
                )
            ) {
                Button("Entendido") { model.dismissError() }
            } message: {
                Text(model.actionError ?? "Intenta nuevamente.")
            }
            .task {
                if model.loadState == .idle { await model.load() }
            }
            .onChange(of: model.connectivity.isOnline) { _, _ in
                model.connectivityChanged()
            }
            .sensoryFeedback(.selection, trigger: model.markFeedbackToken)
            .sensoryFeedback(.success, trigger: model.completionFeedbackToken)
            .sensoryFeedback(.success, trigger: model.saveFeedbackToken)
            .sensoryFeedback(.success, trigger: model.signFeedbackToken)
            .sensoryFeedback(.error, trigger: model.errorFeedbackToken)
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ScrollView {
                AttendanceLoadingView()
                    .padding(16)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("No pudimos cargar la asistencia", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Intentar nuevamente") {
                    Task { await model.load(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
            }
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !model.isOnline {
                    offlineBanner
                }

                if let block = model.activeBlock {
                    AttendanceContextCard(
                        course: model.course,
                        subject: model.subject,
                        dateLabel: model.dateLabel,
                        block: block,
                        summary: model.summary
                    )

                    HStack {
                        AttendanceSaveBadge(state: model.saveState)
                        Spacer(minLength: 0)
                    }

                    AttendanceProgressCard(
                        block: block,
                        summary: model.summary,
                        onScanQR: { presentedFullScreen = .qrScanner },
                        onConfirmAll: {
                            model.confirmAllPresent()
                            UIAccessibility.post(
                                notification: .announcement,
                                argument: "Todos los estudiantes quedaron presentes y confirmados"
                            )
                        },
                        onQuickMode: { presentedSheet = .quickMode }
                    )

                    AttendanceSummaryGrid(summary: model.summary)

                    studentSection(block)

                    AttendanceLessonCard(
                        block: block,
                        onOpen: { presentedSheet = .lesson }
                    )
                } else {
                    ContentUnavailableView(
                        "Sin bloques para esta fecha",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Cambia la fecha o revisa la configuración de tu horario.")
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .refreshable { await model.refresh() }
    }

    private func openQuickModeFromScanner() {
        presentedFullScreen = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            presentedSheet = .quickMode
        }
    }

    private func studentSection(_ block: AttendanceBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Estudiantes")
                        .font(.title3.bold())
                    Text(block.isSigned ? "Consulta de la lista firmada" : "Toca el estado para registrar una excepción")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(block.attendance.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if block.attendance.isEmpty {
                ContentUnavailableView {
                    Label("Sin estudiantes", systemImage: "person.3.fill")
                } description: {
                    Text("Carga la nómina del curso en Mi Perfil antes de firmar asistencia.")
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
            } else {
                ForEach(block.attendance) { student in
                    AttendanceStudentRow(
                        student: student,
                        blockSigned: block.isSigned,
                        onSelect: { status in
                            model.mark(studentID: student.id, as: status)
                            UIAccessibility.post(
                                notification: .announcement,
                                argument: "\(student.name), \(status.title), confirmado"
                            )
                        }
                    )
                }
            }
        }
    }

    private var offlineBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sin conexión")
                    .font(.subheadline.bold())
                Text("Puedes revisar la lista, pero los cambios quedarán pendientes hasta recuperar internet.")
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "icloud.slash.fill")
                .font(.title3)
        }
        .foregroundStyle(EPTheme.statusAmber)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(EPTheme.statusAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ToolbarContentBuilder
    private var attendanceToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if model.blocks.count > 1 {
                Menu {
                    ForEach(model.blocks) { block in
                        Button {
                            model.selectBlock(block.id)
                        } label: {
                            Label(
                                "\(block.label) · \(block.timeRange)",
                                systemImage: model.selectedBlockID == block.id ? "checkmark" : "clock"
                            )
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text("Asistencia")
                            .font(.headline)
                        Text(model.activeBlock.map { "\($0.label) · \($0.timeRange)" } ?? "Elegir bloque")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Cambiar bloque")
                .accessibilityValue(model.activeBlock?.label ?? "Sin bloque")
            } else {
                VStack(spacing: 1) {
                    Text("Asistencia")
                        .font(.headline)
                    if let block = model.activeBlock {
                        Text("\(block.label) · \(block.timeRange)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                presentedSheet = .date
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Cambiar fecha")

            if let index = model.activeBlockIndex, index > 0, model.activeBlock?.isSigned == false {
                Menu {
                    Button {
                        model.copyPreviousBlock()
                    } label: {
                        Label("Copiar estados del bloque anterior", systemImage: "doc.on.doc")
                    }
                    Button {
                        presentedSheet = .lesson
                    } label: {
                        Label("Editar objetivo y actividad", systemImage: "book.pages")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Más opciones de asistencia")
            }
        }
    }
}

private struct AttendanceActionBar: View {
    let model: AttendanceViewModel
    @Binding var presentedSheet: AttendanceSheetDestination?

    var body: some View {
        Group {
#if compiler(>=6.2)
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 12) {
                    buttons
                }
            } else {
                fallbackButtons
            }
#else
            fallbackButtons
#endif
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var fallbackButtons: some View {
        buttons
            .padding(10)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
    }

    @ViewBuilder
    private var buttons: some View {
        if model.activeBlock?.isSigned == true {
            Button {
                presentedSheet = .reopen
            } label: {
                Label("Reabrir bloque con motivo", systemImage: "lock.open.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .attendancePrimaryButtonStyle()
        } else {
            HStack(spacing: 12) {
                Button {
                    Task { _ = await model.save(providesFeedback: true) }
                } label: {
                    Label("Guardar", systemImage: "square.and.arrow.down.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(minHeight: 48)
                }
                .attendanceSecondaryButtonStyle()
                .disabled(!model.isDirty || model.saveState == .saving)

                Button {
                    if model.canSignActiveBlock {
                        presentedSheet = .signReview
                    } else {
                        model.reportSignBlocker()
                    }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        actionLabel("Revisar y firmar")
                        actionLabel("Revisar")
                    }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .attendancePrimaryButtonStyle()
                .accessibilityLabel("Revisar y firmar")
            }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "signature")
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

#if DEBUG
#Preview("Asistencia pendiente") {
    NavigationStack {
        AttendanceView(previewModel: AttendanceViewModel.preview(isSigned: false, allConfirmed: false))
    }
}

#Preview("Asistencia firmada") {
    NavigationStack {
        AttendanceView(previewModel: AttendanceViewModel.preview(isSigned: true, allConfirmed: true))
    }
    .preferredColorScheme(.dark)
}
#endif
