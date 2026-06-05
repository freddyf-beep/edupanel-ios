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
    case coursePlanificaciones(String)

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
        case .coursePlanificaciones(let course): return "Planificaciones - \(course)"
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
        case .coursePlanificaciones: return "book.closed.fill"
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
        case .coursePlanificaciones(let course):
            return "Planificaciones filtradas para el curso \(course)."
        default:
            return "Sin contenido por ahora."
        }
    }
}

struct AppShell: View {
    @Environment(AuthSession.self) private var authSession

    let user: AuthenticatedUser
    let dashboardRepository: DashboardRepository

    @State private var selectedRoute: AppRoute = .module(.inicio)
    @State private var isSidebarOpen = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        SidebarContainer(
            isOpen: $isSidebarOpen,
            navigationPath: $navigationPath,
            sidebar: {
                SidebarView(
                    repository: dashboardRepository,
                    user: user,
                    selectedRoute: $selectedRoute,
                    isSidebarOpen: $isSidebarOpen,
                    navigationPath: $navigationPath
                )
            },
            content: {
                NavigationStack(path: $navigationPath) {
                    Group {
                        switch selectedRoute {
                        case .module(.inicio):
                            DashboardView(
                                repository: dashboardRepository,
                                user: user,
                                onOpenProfile: {
                                    withAnimation {
                                        selectedRoute = .module(.perfil)
                                    }
                                }
                            )
                        case .module(.perfil):
                            ProfileView(
                                repository: dashboardRepository,
                                user: user
                            )
                        case .module(let tab):
                            PlaceholderModuleView(tab: tab)
                        case .cronograma:
                            RoutePlaceholderView(route: .cronograma)
                        case .calificaciones:
                            RoutePlaceholderView(route: .calificaciones)
                        case .perfil360:
                            RoutePlaceholderView(route: .perfil360)
                        case .coursePlanificaciones(let course):
                            RoutePlaceholderView(route: .coursePlanificaciones(course))
                        default:
                            RoutePlaceholderView(route: selectedRoute)
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    isSidebarOpen.toggle()
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(Color(hex: "#F03E6E"))
                            }
                        }
                        
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
            }
        )
    }
}

// Private hex helper for toolbar custom color
private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else {
            self = .pink
            return
        }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else {
            self = .pink
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
