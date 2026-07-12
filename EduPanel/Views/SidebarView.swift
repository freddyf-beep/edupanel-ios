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
}

struct SidebarView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.displayMode) private var displayMode

    let repository: DashboardRepository
    let user: AuthenticatedUser
    
    @Binding var selectedRoute: AppRoute
    @Binding var selectedTab: AppTab
    @Binding var isSidebarOpen: Bool
    @Binding var navigationPath: NavigationPath
    
    @State private var viewModel: SidebarViewModel
    
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
            // Header: User Profile
            VStack(spacing: 12) {
                // User Avatar
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
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(EPTheme.heroGradient, lineWidth: 2.5)
                        .padding(-3.5)
                )
                .shadow(color: EPTheme.primary.opacity(0.18), radius: 10, y: 4)

                // User Names
                VStack(spacing: 4) {
                    Text(userShortName)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Color(.label))

                    HStack(spacing: 5) {
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .bold))
                        Text(viewModel.snapshot?.profile.tipoProfesor.isEmpty == false ? viewModel.snapshot!.profile.tipoProfesor : "Profesor")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(EPTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(EPTheme.primary.opacity(0.1), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 58)
            .padding(.bottom, 22)
            .border(width: 1, edges: [.bottom], color: Color(.separator).opacity(0.2))
            
            // Scrollable Navigation List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    // Main Nav
                    navButton(route: .module(.inicio), label: "Inicio", systemName: "house.fill")
                    navButton(route: .module(.planificaciones), label: "Mis planificaciones", systemName: "book.closed.fill")
                    
                    // Tools Header
                    Text("Herramientas")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .padding(.horizontal, 14)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    
                    // Tools Nav
                    navButton(route: .cronograma, label: "Cronograma", systemName: "calendar")
                    navButton(route: .actividades, label: "Actividades de clase", systemName: "lightbulb.fill")
                    navButton(route: .module(.clases), label: "Libro de clases", systemName: "calendar.badge.clock")
                    navButton(route: .calificaciones, label: "Calificaciones", systemName: "checkmark.clipboard.fill")
                    navButton(route: .module(.evaluaciones), label: "Evaluaciones", systemName: "checklist.checked")
                    navButton(route: .perfil360, label: "Perfil 360", systemName: "person.2.fill")
                    navButton(route: .ayuda, label: "Ayuda", systemName: "questionmark.circle.fill")
                    navButton(route: .module(.perfil), label: "Mi Perfil", systemName: "person.crop.circle.fill")
                    navButton(route: .settings, label: "Configuración", systemName: "gearshape.fill")
                    
                    // Courses Header
                    Text("Mis cursos")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .padding(.horizontal, 14)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    
                    // Courses list
                    if viewModel.isLoading && viewModel.snapshot == nil {
                        ProgressView()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else if viewModel.courses.isEmpty {
                        Text("Configura tu horario en Mi Perfil")
                            .font(.system(size: 11, weight: .medium).italic())
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.courses, id: \.name) { course in
                            courseButton(courseName: course.name, colorHex: course.colorHex)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 16)
            }
            
            // Footer: App version info
            Text("EduPanel v1.0.18")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
                .border(width: 1, edges: [.top], color: Color(.separator).opacity(0.25))
        }
        .background(Color(.systemBackground))
        .task {
            await viewModel.load()
        }
    }
    
    // Helpers & Subviews
    private var avatarFallback: some View {
        ZStack {
            EPTheme.heroGradient
            Text(String((user.displayName ?? "P").prefix(1)).uppercased())
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
        }
    }
    
    private var userShortName: String {
        guard let name = user.displayName, !name.isEmpty else { return "Profesor" }
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            return "\(parts[0]) \(parts[1])"
        }
        return parts.first ?? "Profesor"
    }
    
    private func navButton(route: AppRoute, label: String, systemName: String) -> some View {
        let isActive = selectedRoute == route

        return Button {
            navigateTo(route)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? .white : Color(.secondaryLabel))
                    .frame(width: 30, height: 30)
                    .background(
                        isActive ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(Color(.systemGray6)),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                Text(label)
                    .font(.system(size: 13, weight: isActive ? .bold : .medium))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, displayMode.isSimple ? 4 : 7)
            .foregroundStyle(isActive ? EPTheme.primary : Color(.label))
            .background(isActive ? EPTheme.primary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private func courseButton(courseName: String, colorHex: String) -> some View {
        let route = AppRoute.coursePlanificaciones(curso: courseName, asignatura: nil)
        let isActive = selectedRoute == route

        return Button {
            navigateTo(route)
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .fill(EPTheme.color(hex: colorHex))
                    .frame(width: 9, height: 9)
                    .frame(width: 30, alignment: .center)

                Text(courseName)
                    .font(.system(size: 12, weight: isActive ? .bold : .medium))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? EPTheme.primary : Color(.secondaryLabel))
            .background(isActive ? EPTheme.primary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isActive)
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

// Border modifier helper for header and footer separators
private struct BorderModifier: ViewModifier {
    var width: CGFloat
    var edges: [Edge]
    var color: Color

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                ZStack {
                    ForEach(edges, id: \.self) { edge in
                        self.border(edge: edge, geometry: geometry)
                    }
                }
            }
        )
    }

    private func border(edge: Edge, geometry: GeometryProxy) -> some View {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat

        switch edge {
        case .top:
            x = 0
            y = 0
            w = geometry.size.width
            h = width
        case .bottom:
            x = 0
            y = geometry.size.height - width
            w = geometry.size.width
            h = width
        case .leading:
            x = 0
            y = 0
            w = width
            h = geometry.size.height
        case .trailing:
            x = geometry.size.width - width
            y = 0
            w = width
            h = geometry.size.height
        }

        return Rectangle()
            .fill(color)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}

private extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        modifier(BorderModifier(width: width, edges: edges, color: color))
    }
}
