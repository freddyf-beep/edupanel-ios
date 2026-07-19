import SwiftUI

@MainActor
@Observable
final class SidebarViewModel {
    var snapshot: DashboardSnapshot?
    var isLoading = false
    var errorMessage: String?

    private let repository: DashboardRepository

    init(repository: DashboardRepository) {
        self.repository = repository
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

    var courses: [(name: String, colorHex: String)] {
        guard let snapshot else { return [] }
        let academic = snapshot.horario.filter(\.isAcademic)
        let names = Array(Set(academic.map(\.resumen))).sorted()
        return names.map { name in
            let color = academic.first { $0.resumen == name }?.colorHex ?? "#F03E6E"
            return (name: name, colorHex: color)
        }
    }

    var courseCount: Int { courses.count }

    var subjectCount: Int {
        guard let snapshot else { return 0 }
        let academic = snapshot.horario.filter(\.isAcademic)
        return Set(academic.compactMap(\.asignatura).filter { !$0.isEmpty }).count
    }
}

// MARK: - Sidebar estilo Twitter/X
//
// Estructura replica el menu lateral de X en iOS:
// header con avatar + nombre + handle + contadores, filas de navegacion
// limpias (icono outline + texto), secciones expandibles con chevron y
// barra inferior con toggle de apariencia.
struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.auto.rawValue

    let repository: DashboardRepository
    let user: AuthenticatedUser

    @Binding var selectedRoute: AppRoute
    @Binding var selectedTab: AppTab
    @Binding var isSidebarOpen: Bool
    @Binding var navigationPath: NavigationPath

    @State private var viewModel: SidebarViewModel
    @State private var isCoursesExpanded = false
    @State private var isSupportExpanded = false

    init(repository: DashboardRepository, user: AuthenticatedUser, selectedRoute: Binding<AppRoute>, selectedTab: Binding<AppTab>, isSidebarOpen: Binding<Bool>, navigationPath: Binding<NavigationPath>) {
        self.repository = repository
        self.user = user
        self._selectedRoute = selectedRoute
        self._selectedTab = selectedTab
        self._isSidebarOpen = isSidebarOpen
        self._navigationPath = navigationPath
        self._viewModel = State(initialValue: SidebarViewModel(repository: repository))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    profileHeader

                    Divider()
                        .padding(.vertical, 4)

                    navRow(route: .module(.perfil), label: "Mi Perfil", systemName: "person")
                    navRow(route: .module(.planificaciones), label: "Mis planificaciones", systemName: "book.closed")
                    navRow(route: .cronograma, label: "Cronograma", systemName: "calendar")
                    navRow(route: .actividades, label: "Actividades de clase", systemName: "lightbulb")
                    navRow(route: .module(.clases), label: "Asistencia", systemName: "person.3.sequence")
                    navRow(route: .calificaciones, label: "Calificaciones", systemName: "checkmark.clipboard")
                    navRow(route: .module(.evaluaciones), label: "Evaluaciones", systemName: "checklist")
                    navRow(route: .perfil360, label: "Perfil 360", systemName: "person.2")

                    Divider()
                        .padding(.vertical, 4)

                    coursesDisclosure
                    supportDisclosure
                }
                .padding(.top, 62)
                .padding(.bottom, 12)
            }

            footerBar
        }
        .background(Color(.systemBackground))
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Header (perfil estilo X)

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                navigateTo(.module(.perfil))
            } label: {
                Group {
                    if let url = user.photoURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .scaledToFill()
                            default:
                                avatarFallback
                            }
                        }
                    } else {
                        avatarFallback
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir mi perfil")

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(.label))

                Text(handleText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }

            HStack(spacing: 16) {
                statCount(viewModel.courseCount, label: "Cursos")
                statCount(viewModel.subjectCount, label: "Asignaturas")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func statCount(_ value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(.label))
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    // MARK: - Filas de navegacion (estilo X: icono outline + texto)

    private func navRow(route: AppRoute, label: String, systemName: String) -> some View {
        let isActive = selectedRoute == route

        return Button {
            navigateTo(route)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                    .frame(width: 26, alignment: .center)

                Text(label)
                    .font(.system(size: 17, weight: isActive ? .bold : .medium))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .foregroundStyle(isActive ? EPTheme.primary : Color(.label))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secciones expandibles (estilo "Settings & Support" de X)

    private var coursesDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureRow(label: "Mis cursos", isExpanded: isCoursesExpanded) {
                withAnimation(EPTheme.spring) {
                    isCoursesExpanded.toggle()
                }
            }

            if isCoursesExpanded {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    ProgressView()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                } else if viewModel.courses.isEmpty {
                    Text("Configura tu horario en Mi Perfil")
                        .font(.system(size: 14).italic())
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                } else {
                    ForEach(viewModel.courses, id: \.name) { course in
                        courseRow(courseName: course.name, colorHex: course.colorHex)
                    }
                }
            }
        }
    }

    private var supportDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureRow(label: "Configuración y soporte", isExpanded: isSupportExpanded) {
                withAnimation(EPTheme.spring) {
                    isSupportExpanded.toggle()
                }
            }

            if isSupportExpanded {
                subNavRow(route: .settings, label: "Configuración")
                subNavRow(route: .ayuda, label: "Ayuda")
            }
        }
    }

    private func disclosureRow(label: String, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(.label))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subNavRow(route: AppRoute, label: String) -> some View {
        let isActive = selectedRoute == route

        return Button {
            navigateTo(route)
        } label: {
            Text(label)
                .font(.system(size: 15, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? EPTheme.primary : Color(.label))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func courseRow(courseName: String, colorHex: String) -> some View {
        let route = AppRoute.coursePlanificaciones(curso: courseName, asignatura: nil)
        let isActive = selectedRoute == route

        return Button {
            navigateTo(route)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(EPTheme.color(hex: colorHex))
                    .frame(width: 8, height: 8)

                Text(courseName)
                    .font(.system(size: 15, weight: isActive ? .bold : .medium))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .foregroundStyle(isActive ? EPTheme.primary : Color(.label))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Barra inferior (toggle de apariencia, como X)

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Button {
                    let current = AppTheme(rawValue: appThemeRaw) ?? .auto
                    appThemeRaw = (current == .oscuro ? AppTheme.claro : .oscuro).rawValue
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color(.label))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: appThemeRaw)
                .accessibilityLabel("Alternar entre modo claro y oscuro")

                Spacer()

                Text("EduPanel v1.0.18")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Helpers

    private var avatarFallback: some View {
        ZStack {
            EPTheme.heroGradient
            Text(String((user.displayName ?? "P").prefix(1)).uppercased())
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
        }
    }

    private var displayName: String {
        guard let name = user.displayName, !name.isEmpty else { return "Profesor" }
        return name
    }

    private var handleText: String {
        if let email = user.email, !email.isEmpty {
            return email
        }
        let tipo = viewModel.snapshot?.profile.tipoProfesor ?? ""
        return tipo.isEmpty ? "Profesor" : tipo
    }

    private func navigateTo(_ route: AppRoute) {
        // Reset current active navigation path to root when switching
        navigationPath = NavigationPath()

        selectedRoute = route

        switch route {
        case .module(let tab):
            selectedTab = tab
        case .coursePlanificaciones:
            selectedTab = .planificaciones
        default:
            // For sub-tools (like cronograma, calificaciones), push onto the active stack
            navigationPath.append(route)
        }

        // Close sidebar with animation
        withAnimation(EPTheme.spring) {
            isSidebarOpen = false
        }
    }
}
