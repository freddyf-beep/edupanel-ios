import SwiftUI

struct EvaluacionesShell: View {
    let dashboardRepository: DashboardRepository
    let evaluacionesRepository: EvaluacionesRepository

    @State private var viewModel: EvaluacionesViewModel
    @State private var selectedTab = "pruebas"
    @State private var hasLoaded = false

    init(
        dashboardRepository: DashboardRepository,
        evaluacionesRepository: EvaluacionesRepository = EvaluacionesRepository()
    ) {
        self.dashboardRepository = dashboardRepository
        self.evaluacionesRepository = evaluacionesRepository
        _viewModel = State(initialValue: EvaluacionesViewModel(
            dashboardRepository: dashboardRepository,
            evaluacionesRepository: evaluacionesRepository
        ))
    }

    private let tabs = [
        EPWebTab(id: "pruebas", title: "Pruebas", icon: "doc.text.fill"),
        EPWebTab(id: "guias", title: "Guías", icon: "book.pages.fill"),
        EPWebTab(id: "rubricas", title: "R\u{00FA}bricas", icon: "square.grid.2x2"),
        EPWebTab(id: "listas", title: "Listas", icon: "checklist")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                EPWebTabBar(tabs: tabs, selected: $selectedTab)

                selectorCurso

                if let error = viewModel.errorMessage {
                    EvaluacionesErrorBanner(message: error)
                }

                if viewModel.isLoading && viewModel.snapshot == nil {
                    EvaluacionesLoadingCard(texto: "Cargando evaluaciones...")
                } else if viewModel.cursos.isEmpty {
                    EPWebCard {
                        EPEmptyState(
                            icon: "graduationcap",
                            title: "Configura tus cursos en Mi Perfil",
                            message: "Para usar pruebas, guías, rúbricas y listas necesitas al menos un curso en tu horario semanal."
                        )
                    }
                } else {
                    switch selectedTab {
                    case "pruebas":
                        PruebasHubView(viewModel: viewModel)
                    case "guias":
                        GuiasHubView(viewModel: viewModel)
                    case "rubricas":
                        RubricasHubView(viewModel: viewModel)
                    case "listas":
                        ListasHubView(viewModel: viewModel)
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(EPTheme.background)
        .navigationTitle("Evaluaciones")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load()
        }
        .onAppear {
            guard hasLoaded, !viewModel.isLoading else { return }
            Task { await viewModel.loadContenido() }
        }
    }

    private var header: some View {
        EPModuleHeader(
            eyebrow: "Evaluaciones",
            title: "Pruebas, guías, rúbricas y listas",
            subtitle: "Instrumentos vinculados al currículum, aplicación por estudiante y resultados con nota chilena.",
            icon: "checkmark.seal.fill",
            accent: .evaluaciones
        )
    }

    @ViewBuilder
    private var selectorCurso: some View {
        if !viewModel.cursos.isEmpty {
            HStack(spacing: 10) {
                EvaluacionesCursoPicker(
                    cursos: viewModel.cursos,
                    seleccionado: Binding(
                        get: { viewModel.selectedCurso },
                        set: { nuevo in
                            Task { await viewModel.seleccionarCurso(nuevo) }
                        }
                    )
                )

                Menu {
                    ForEach(viewModel.availableSubjects, id: \.self) { subject in
                        Button {
                            Task { await viewModel.seleccionarAsignatura(subject) }
                        } label: {
                            if subject == viewModel.activeSubject {
                                Label(subject, systemImage: "checkmark")
                            } else {
                                Text(subject)
                            }
                        }
                    }
                } label: {
                    EPStatusPill(text: viewModel.activeSubject, icon: "book.closed.fill")
                }

                Spacer()
            }
        }
    }
}

struct EvaluacionesRetryCard: View {
    let title: String
    let message: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        EPWebCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 15, weight: .black))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: action) {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(isLoading)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

struct EvaluacionesCursoPicker: View {
    let cursos: [String]
    @Binding var seleccionado: String

    var body: some View {
        Menu {
            ForEach(cursos, id: \.self) { curso in
                Button {
                    seleccionado = curso
                } label: {
                    if curso == seleccionado {
                        Label(curso, systemImage: "checkmark")
                    } else {
                        Text(curso)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .black))
                Text(seleccionado.isEmpty ? "Sin cursos" : seleccionado)
                    .font(.system(size: 12, weight: .black))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
            }
            .foregroundStyle(EPTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EPTheme.primary.opacity(0.1), in: Capsule())
        }
    }
}

struct EvaluacionesErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EvaluacionesLoadingCard: View {
    let texto: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(texto)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .epCardSurface()
    }
}
