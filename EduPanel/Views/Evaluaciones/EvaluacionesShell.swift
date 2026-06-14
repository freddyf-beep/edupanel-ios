import SwiftUI

struct EvaluacionesShell: View {
    let dashboardRepository: DashboardRepository

    @State private var viewModel: EvaluacionesViewModel
    @State private var selectedTab = "rubricas"
    @State private var hasLoaded = false

    init(dashboardRepository: DashboardRepository) {
        self.dashboardRepository = dashboardRepository
        _viewModel = State(initialValue: EvaluacionesViewModel(dashboardRepository: dashboardRepository))
    }

    private let tabs = [
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
                            message: "Para crear r\u{00FA}bricas y listas necesitas al menos un curso en tu horario semanal."
                        )
                    }
                } else if selectedTab == "rubricas" {
                    RubricasHubView(viewModel: viewModel)
                } else {
                    ListasHubView(viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .black))
                Text("EVALUACIONES")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.2)
            }
            .foregroundStyle(.white.opacity(0.9))

            Text("R\u{00FA}bricas y listas de cotejo")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Crea instrumentos vinculados al curr\u{00ED}culum, eval\u{00FA}a por grupos y revisa resultados con nota chilena.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
        .shadow(color: EPTheme.primary.opacity(0.25), radius: 12, y: 5)
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
                            viewModel.selectedCurso = nuevo
                            Task { await viewModel.loadContenido() }
                        }
                    )
                )

                if viewModel.availableSubjects.count > 1 {
                    Menu {
                        ForEach(viewModel.availableSubjects, id: \.self) { subject in
                            Button(subject) {
                                viewModel.selectedSubject = subject
                                Task { await viewModel.loadContenido() }
                            }
                        }
                    } label: {
                        EPStatusPill(text: viewModel.activeSubject, icon: "book.closed.fill")
                    }
                } else {
                    EPStatusPill(text: viewModel.activeSubject, icon: "book.closed.fill")
                }

                Spacer()
            }
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
