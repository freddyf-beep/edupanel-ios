import SwiftUI

enum AppRoute: Hashable {
    case calificaciones
    case cronograma
    case actividades
    case perfil360
    case planificacionNueva
    case evaluacionNueva
    case claseDetalle(String)
    case perfilAction(String)
    case module(AppTab)

    var title: String {
        switch self {
        case .calificaciones: return "Calificaciones"
        case .cronograma: return "Cronograma"
        case .actividades: return "Actividades de clase"
        case .perfil360: return "Perfil 360"
        case .planificacionNueva: return "Nueva planificacion"
        case .evaluacionNueva: return "Nueva evaluacion"
        case .claseDetalle: return "Detalle de clase"
        case .perfilAction(let title): return title
        case .module(let tab): return tab.title
        }
    }

    var systemImage: String {
        switch self {
        case .calificaciones: return "checkmark.clipboard.fill"
        case .cronograma: return "calendar.badge.clock"
        case .actividades: return "lightbulb.fill"
        case .perfil360: return "person.crop.circle.fill"
        case .planificacionNueva: return "book.closed.fill"
        case .evaluacionNueva: return "checklist.checked"
        case .claseDetalle: return "calendar"
        case .perfilAction: return "arrow.right.circle.fill"
        case .module(let tab): return tab.systemImage
        }
    }
}

struct AppShell: View {
    @Environment(AuthSession.self) private var authSession

    let user: AuthenticatedUser
    let dashboardRepository: DashboardRepository

    @State private var selectedTab: AppTab = .inicio

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    repository: dashboardRepository,
                    user: user,
                    onOpenProfile: { selectedTab = .perfil }
                )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await authSession.signOut() }
                            } label: {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            .accessibilityLabel("Cerrar sesion")
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        RoutePlaceholderView(route: route)
                    }
            }
            .tabItem { Label(AppTab.inicio.title, systemImage: AppTab.inicio.systemImage) }
            .tag(AppTab.inicio)

            ForEach(AppTab.allCases.filter { $0 != .inicio && $0 != .perfil }) { tab in
                NavigationStack {
                    PlaceholderModuleView(tab: tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            RoutePlaceholderView(route: route)
                        }
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }

            NavigationStack {
                ProfileView(repository: dashboardRepository, user: user)
                    .navigationDestination(for: AppRoute.self) { route in
                        RoutePlaceholderView(route: route)
                    }
            }
            .tabItem { Label(AppTab.perfil.title, systemImage: AppTab.perfil.systemImage) }
            .tag(AppTab.perfil)
        }
    }
}
