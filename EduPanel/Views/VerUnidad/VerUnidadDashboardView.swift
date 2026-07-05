import SwiftUI

struct VerUnidadDashboardView: View {
    let curso: String
    let asignatura: String?
    let unidadId: String
    let unidadNombre: String
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    @State private var viewModel: VerUnidadViewModel
    @State private var selectedTab: String

    @Environment(\.displayMode) private var displayMode

    private let tabs = [
        EPWebTab(id: "unidad", title: "Unidad", icon: "text.alignleft"),
        EPWebTab(id: "cronograma", title: "Cronograma", icon: "calendar"),
        EPWebTab(id: "clases", title: "Clases", icon: "book.closed")
    ]

    init(curso: String, asignatura: String? = nil, unidadId: String, unidadNombre: String, initialTab: String, dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.curso = curso
        self.asignatura = asignatura
        self.unidadId = unidadId
        self.unidadNombre = unidadNombre
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        self._selectedTab = State(initialValue: initialTab)
        self._viewModel = State(initialValue: VerUnidadViewModel(
            dashboardRepository: dashboardRepository,
            planificacionRepository: planificacionRepository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando detalles...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    switch selectedTab {
                    case "unidad":
                        VerUnidadBaseView(viewModel: viewModel, selectedTab: $selectedTab)
                    case "cronograma":
                        VerUnidadCronogramaView(viewModel: viewModel, selectedTab: $selectedTab)
                    case "clases":
                        VerUnidadClasesView(viewModel: viewModel)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(unidadNombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.saveAll() }
                } label: {
                    Group {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(EPTheme.primary)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .disabled(viewModel.isSaving)
                .accessibilityLabel("Guardar unidad")
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.saveStatus) { _, newValue in
            !newValue.isEmpty && !newValue.contains("Error")
        }
        .task {
            await viewModel.load(curso: curso, unidadId: unidadId, asignatura: asignatura)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(EPTheme.heroGradient)
                    .frame(width: 5, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.activeSubject.uppercased()) · \(curso.uppercased())")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(EPTheme.primary)
                    Text(unidadNombre)
                        .font(.system(size: displayMode.isSimple ? 22 : 26, weight: .black, design: .rounded))
                        .lineLimit(2)
                    if !displayMode.isSimple {
                        Text(headerSubtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if !viewModel.saveStatus.isEmpty {
                    EPStatusPill(
                        text: viewModel.saveStatus,
                        icon: viewModel.saveStatus.contains("Error") ? "xmark.octagon.fill" : "checkmark.circle.fill",
                        tint: viewModel.saveStatus.contains("Error") ? .red : .green
                    )
                }
            }

            EPWebTabBar(tabs: tabs, selected: $selectedTab)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.12))
                .frame(height: 1)
        }
    }

    private var headerSubtitle: String {
        guard let verUnidad = viewModel.verUnidad, let crono = viewModel.cronograma else {
            return "Plan de unidad, cronograma y clases"
        }
        let selectedOAs = verUnidad.oas.filter(\.seleccionado).count
        return "\(verUnidad.horas) horas · \(crono.totalClases) clases · \(selectedOAs) OA seleccionados"
    }
}
