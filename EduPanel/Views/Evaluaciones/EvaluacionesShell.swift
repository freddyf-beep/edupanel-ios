import SwiftUI

struct EvaluacionesShell: View {
    let dashboardRepository: DashboardRepository
    let evaluacionesRepository: EvaluacionesRepository

    @State private var viewModel: EvaluacionesViewModel
    @State private var selectedTab = "pruebas"
    @State private var hasLoaded = false

    init(
        dashboardRepository: DashboardRepository,
        evaluacionesRepository: EvaluacionesRepository = EvaluacionesRepository(),
        apiClient: APIClient? = nil
    ) {
        self.dashboardRepository = dashboardRepository
        self.evaluacionesRepository = evaluacionesRepository
        _viewModel = State(initialValue: EvaluacionesViewModel(
            dashboardRepository: dashboardRepository,
            evaluacionesRepository: evaluacionesRepository,
            apiClient: apiClient
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

                selectorCurso

                Text("Elige cómo evaluar")
                    .font(.headline.weight(.black))

                EvaluacionesInstrumentSwitcher(tabs: tabs, selected: $selectedTab)

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
            .tabBarPageBottomPadding()
        }
        .reportsTabBarScroll()
        .background(EPTheme.background)
        .navigationTitle("Evaluaciones")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load()
        }
        .onAppear {
            guard hasLoaded, !viewModel.isLoading else { return }
            Task {
                async let classicContent: Void = viewModel.loadContenido()
                async let newEngineContent: Void = viewModel.refreshExamForge()
                _ = await (classicContent, newEngineContent)
            }
        }
        .refreshable {
            async let classicContent: Void = viewModel.loadContenido()
            async let newEngineContent: Void = viewModel.refreshExamForge()
            _ = await (classicContent, newEngineContent)
        }
    }

    private var header: some View {
        EPPageHeader(
            eyebrow: "Evaluaciones",
            title: "Evaluar con claridad",
            subtitle: "Primero elige el curso. Después abre el instrumento que necesitas preparar o aplicar.",
            icon: "checkmark.seal.fill"
        )
    }

    @ViewBuilder
    private var selectorCurso: some View {
        if !viewModel.cursos.isEmpty {
            EPWebCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    EPSectionHeader(
                        title: "Contexto de trabajo",
                        subtitle: "Todo lo que veas abajo corresponde a esta selección.",
                        icon: "person.text.rectangle.fill"
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            coursePicker
                            subjectPicker
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            coursePicker
                            subjectPicker
                        }
                    }

                    if viewModel.isLoadingContenido {
                        Label("Actualizando instrumentos…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var coursePicker: some View {
        EvaluacionesCursoPicker(
            cursos: viewModel.cursos,
            seleccionado: Binding(
                get: { viewModel.selectedCurso },
                set: { nuevo in
                    Task { await viewModel.seleccionarCurso(nuevo) }
                }
            )
        )
    }

    private var subjectPicker: some View {
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
            HStack(spacing: 7) {
                Image(systemName: "book.closed.fill")
                Text(viewModel.activeSubject)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.black))
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(EPTheme.primary)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Asignatura: \(viewModel.activeSubject)")
    }
}

private struct EvaluacionesInstrumentSwitcher: View {
    let tabs: [EPWebTab]
    @Binding var selected: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tabs) { tab in
                        let isSelected = selected == tab.id
                        Button {
                            withAnimation(EPTheme.spring) {
                                selected = tab.id
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 19, weight: .bold))
                                    .symbolVariant(isSelected ? .fill : .none)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        isSelected ? Color.white.opacity(0.18) : EPTheme.subtle,
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tab.title)
                                        .font(.subheadline.weight(.black))
                                    Text(description(for: tab.id))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.body.weight(.bold))
                                }
                            }
                        }
                        .foregroundStyle(isSelected ? .white : .primary)
                        .frame(width: 210, alignment: .leading)
                        .frame(minHeight: 72, alignment: .leading)
                        .padding(12)
                        .background(
                            isSelected ? EPTheme.primary : EPTheme.card,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isSelected ? Color.clear : EPTheme.border, lineWidth: 0.75)
                        }
                        .shadow(color: isSelected ? EPTheme.primary.opacity(0.18) : .clear, radius: 10, y: 5)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(tab.id)
                    }
                }
            }
            // A selected instrument must be brought fully into view. Without this,
            // switching after a horizontal swipe leaves the previous card clipped.
            .onChange(of: selected) { _, newValue in
                withAnimation(EPTheme.spring) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func description(for id: String) -> String {
        switch id {
        case "pruebas": return "Preparar y corregir"
        case "guias": return "Practicar y acompañar"
        case "rubricas": return "Valorar desempeño"
        case "listas": return "Observar criterios"
        default: return "Abrir instrumentos"
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
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Curso: \(seleccionado)")
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
