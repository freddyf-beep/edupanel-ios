import SwiftUI

enum AppRoute: Hashable {
    case calificaciones
    case cronograma
    case actividades
    case perfil360
    case planificacionNueva
    case evaluacionNueva
    case classDetail(id: String, title: String)
    case newScheduleBlock
    case courseStudents(String)
    case editCourse(String)
    case schoolLogo
    case calendarConnect
    case calendarSync
    case driveConnect
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
        case .classDetail(id: _, title: let title): return title.isEmpty ? "Detalle de clase" : title
        case .newScheduleBlock: return "Nuevo bloque"
        case .courseStudents(let course): return "Estudiantes - \(course)"
        case .editCourse(let course): return "Editar curso - \(course)"
        case .schoolLogo: return "Logo del colegio"
        case .calendarConnect: return "Conectar Google Calendar"
        case .calendarSync: return "Sincronizar Calendar"
        case .driveConnect: return "Conectar Google Drive"
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
        case .classDetail: return "calendar"
        case .newScheduleBlock: return "plus.rectangle.on.rectangle"
        case .courseStudents: return "person.2.fill"
        case .editCourse: return "pencil"
        case .schoolLogo: return "photo.badge.plus"
        case .calendarConnect: return "calendar.badge.plus"
        case .calendarSync: return "arrow.triangle.2.circlepath"
        case .driveConnect: return "externaldrive.badge.plus"
        case .perfilAction: return "arrow.right.circle.fill"
        case .module(let tab): return tab.systemImage
        }
    }

    var placeholderText: String {
        switch self {
        case .classDetail:
            return "Pantalla preparada para revisar y editar este bloque."
        case .newScheduleBlock:
            return "Aqui construiremos el formulario nativo para crear bloques de clase o libres."
        case .courseStudents(let course):
            return "Lista de estudiantes preparada para \(course)."
        case .editCourse(let course):
            return "Configuracion del curso preparada para \(course)."
        case .schoolLogo:
            return "Subida del logo del colegio reservada para el siguiente paso."
        case .calendarConnect:
            return "Conexion OAuth de Google Calendar pendiente de implementar."
        case .calendarSync:
            return "Sincronizacion de Calendar pendiente de conectar."
        case .driveConnect:
            return "Conexion a Google Drive pendiente de implementar."
        default:
            return "Sin contenido por ahora."
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
