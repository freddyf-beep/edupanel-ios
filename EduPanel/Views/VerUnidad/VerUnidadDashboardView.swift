import SwiftUI

private enum UnitWorkspaceTab: String, CaseIterable, Identifiable {
    case unidad
    case cronograma
    case clases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unidad: return "Unidad"
        case .cronograma: return "Cronograma"
        case .clases: return "Clases"
        }
    }

    var systemImage: String {
        switch self {
        case .unidad: return "target"
        case .cronograma: return "calendar"
        case .clases: return "text.book.closed"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .unidad: return "Define el propósito y el currículum de la unidad"
        case .cronograma: return "Distribuye fechas y objetivos entre las clases"
        case .clases: return "Planifica y utiliza cada clase de la unidad"
        }
    }

    init(initialValue: String) {
        self = UnitWorkspaceTab(rawValue: initialValue) ?? .unidad
    }
}

struct VerUnidadDashboardView: View {
    let curso: String
    let asignatura: String?
    let unidadId: String
    let unidadNombre: String
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    @State private var viewModel: VerUnidadViewModel
    @State private var selectedTab: UnitWorkspaceTab

    init(
        curso: String,
        asignatura: String? = nil,
        unidadId: String,
        unidadNombre: String,
        initialTab: String,
        dashboardRepository: DashboardRepository,
        planificacionRepository: PlanificacionRepository
    ) {
        self.curso = curso
        self.asignatura = asignatura
        self.unidadId = unidadId
        self.unidadNombre = unidadNombre
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        _selectedTab = State(initialValue: UnitWorkspaceTab(initialValue: initialTab))
        _viewModel = State(initialValue: VerUnidadViewModel(
            dashboardRepository: dashboardRepository,
            planificacionRepository: planificacionRepository
        ))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            workspaceState
        }
        .navigationTitle(unidadNombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveButton
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .sensoryFeedback(.success, trigger: displayedSaveStatus) { _, newValue in
            !newValue.isEmpty && !newValue.contains("Error") && !newValue.contains("Guardando")
        }
        .task {
            await viewModel.load(curso: curso, unidadId: unidadId, asignatura: asignatura)
        }
    }

    @ViewBuilder
    private var workspaceState: some View {
        if viewModel.isLoading {
            UnitWorkspaceLoadingView()
        } else if let loadErrorMessage = viewModel.loadErrorMessage {
            UnitWorkspaceLoadErrorView(
                message: loadErrorMessage,
                isRetrying: viewModel.isLoading || viewModel.isSaving,
                onRetry: retryLoad
            )
        } else {
            VStack(spacing: 0) {
                UnitWorkspaceChrome(
                    course: curso,
                    subject: viewModel.activeSubject,
                    summary: workspaceSummary,
                    saveStatus: displayedSaveStatus,
                    selectedTab: $selectedTab
                )

                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .unidad:
            VerUnidadBaseView(viewModel: viewModel)
        case .cronograma:
            VerUnidadCronogramaView(viewModel: viewModel, selectedTab: legacySelectedTab)
        case .clases:
            VerUnidadClasesView(viewModel: viewModel)
        }
    }

    private var saveButton: some View {
        Button(action: saveAll) {
            Group {
                if viewModel.isSaving || viewModel.isReloadingActivities {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.black))
                        .foregroundStyle(EPTheme.primary)
                }
            }
            .frame(width: 34, height: 34)
            .background(EPTheme.primary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(
            viewModel.isSaving ||
            viewModel.isLoading ||
            viewModel.isReloadingActivities ||
            viewModel.loadErrorMessage != nil
        )
        .accessibilityLabel("Guardar unidad")
        .accessibilityHint("Guarda la unidad, el cronograma y las clases modificadas")
        .accessibilityIdentifier("guardar-unidad")
    }

    private var legacySelectedTab: Binding<String> {
        Binding(
            get: { selectedTab.rawValue },
            set: { selectedTab = UnitWorkspaceTab(initialValue: $0) }
        )
    }

    private var workspaceSummary: String {
        guard let verUnidad = viewModel.verUnidad, let cronograma = viewModel.cronograma else {
            return "Propósito, secuencia y clases en un solo lugar"
        }

        let selectedOAs = verUnidad.oas.filter(\.seleccionado).count
        let plannedClasses = viewModel.clasesActividades.values.filter { activity in
            !RichTextHTML.plainText(from: activity.objetivo).isEmpty ||
            !RichTextHTML.plainText(from: activity.desarrollo).isEmpty
        }.count

        return "\(selectedOAs) OA · \(cronograma.totalClases) clases · \(plannedClasses) planificadas"
    }

    private var displayedSaveStatus: String {
        viewModel.saveStatus.isEmpty ? viewModel.activitySyncStatus : viewModel.saveStatus
    }

    private func saveAll() {
        Task { await viewModel.saveAll() }
    }

    private func retryLoad() {
        Task { await viewModel.retryLoad() }
    }
}

private struct UnitWorkspaceChrome: View {
    let course: String
    let subject: String
    let summary: String
    let saveStatus: String
    @Binding var selectedTab: UnitWorkspaceTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(subject.uppercased()) · \(course.uppercased())")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.9)
                        .foregroundStyle(EPTheme.primary)
                    Text(summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !saveStatus.isEmpty {
                    EPStatusPill(
                        text: saveStatus,
                        icon: saveStatus.contains("Error") ? "xmark.octagon.fill" : "checkmark.circle.fill",
                        tint: saveStatus.contains("Error") ? .red : .green
                    )
                }
            }

            UnitWorkspaceTabBar(selectedTab: $selectedTab)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.12))
                .frame(height: 1)
        }
    }
}

private struct UnitWorkspaceTabBar: View {
    @Binding var selectedTab: UnitWorkspaceTab
    @Namespace private var selectionNamespace

    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabContent
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 17))
        } else {
            fallbackTabBar
        }
#else
        fallbackTabBar
#endif
    }

    private var fallbackTabBar: some View {
        tabContent
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            }
    }

    private var tabContent: some View {
        HStack(spacing: 4) {
            ForEach(UnitWorkspaceTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
    }

    private func tabButton(_ tab: UnitWorkspaceTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(EPTheme.spring) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(EPTheme.primary)
                        .matchedGeometryEffect(id: "unit-workspace-tab", in: selectionNamespace)
                }

                Label(tab.title, systemImage: tab.systemImage)
                    .font(.system(size: 11.5, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ver-unidad-tab-\(tab.rawValue)")
    }
}

private struct UnitWorkspaceLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Preparando la unidad…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparando la unidad")
    }
}

private struct UnitWorkspaceLoadErrorView: View {
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No se pudo cargar esta unidad", systemImage: "exclamationmark.icloud.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Reintentar", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(isRetrying)
                .accessibilityIdentifier("reintentar-carga-unidad")
        }
    }
}
