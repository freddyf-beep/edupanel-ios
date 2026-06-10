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
    case coursePlanificaciones(curso: String, asignatura: String?)
    case verUnidad(curso: String, asignatura: String?, unidadId: String, unidadNombre: String, initialTab: String)

    var title: String {
        switch self {
        case .calificaciones: return "Calificaciones"
        case .cronograma: return "Cronograma"
        case .actividades: return "Actividades de clase"
        case .perfil360: return "Perfil 360"
        case .planificacionNueva: return "Nueva planificación"
        case .evaluacionNueva: return "Nueva evaluación"
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
        case .coursePlanificaciones(let course, _): return "Planificaciones - \(course)"
        case .verUnidad(_, _, _, let unidadNombre, _): return unidadNombre
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
        case .verUnidad: return "book.closed.fill"
        }
    }

    var placeholderText: String {
        switch self {
        case .classDetail:
            return "Pantalla preparada para revisar y editar este bloque."
        case .newScheduleBlock:
            return "Aquí construiremos el formulario nativo para crear bloques de clase o libres."
        case .courseStudents(let course):
            return "Lista de estudiantes preparada para \(course)."
        case .editCourse(let course):
            return "Configuración del curso preparada para \(course)."
        case .schoolLogo:
            return "Subida del logo del colegio reservada para el siguiente paso."
        case .calendarConnect:
            return "Conexión OAuth de Google Calendar pendiente de implementar."
        case .calendarSync:
            return "Sincronización de Calendar pendiente de conectar."
        case .driveConnect:
            return "Conexión a Google Drive pendiente de implementar."
        case .coursePlanificaciones(let course, _):
            return "Planificaciones filtradas para el curso \(course)."
        case .verUnidad:
            return "Detalle de Unidad"
        default:
            return "Sin contenido por ahora."
        }
    }
}

struct AppShell: View {
    @Environment(AuthSession.self) private var authSession

    let user: AuthenticatedUser
    let dashboardRepository: DashboardRepository
    private let planificacionRepository = PlanificacionRepository()

    @State private var selectedTab: AppTab = .planificaciones
    @State private var selectedRoute: AppRoute = .module(.planificaciones)
    @State private var isSidebarOpen = false

    @State private var inicioPath = NavigationPath()
    @State private var planificacionesPath = NavigationPath()
    @State private var evaluacionesPath = NavigationPath()
    @State private var clasesPath = NavigationPath()
    @State private var perfilPath = NavigationPath()

    private var activePath: Binding<NavigationPath> {
        switch selectedTab {
        case .inicio: return $inicioPath
        case .planificaciones: return $planificacionesPath
        case .evaluaciones: return $evaluacionesPath
        case .clases: return $clasesPath
        case .perfil: return $perfilPath
        }
    }

    var body: some View {
        SidebarContainer(
            isOpen: $isSidebarOpen,
            navigationPath: activePath,
            sidebar: {
                SidebarView(
                    repository: dashboardRepository,
                    user: user,
                    selectedRoute: $selectedRoute,
                    selectedTab: $selectedTab,
                    isSidebarOpen: $isSidebarOpen,
                    navigationPath: activePath
                )
            },
            content: {
                TabView(selection: $selectedTab) {
                    // Inicio Tab
                    NavigationStack(path: $inicioPath) {
                        DashboardView(
                            repository: dashboardRepository,
                            user: user,
                            onOpenProfile: {
                                withAnimation {
                                    selectedTab = .perfil
                                }
                            }
                        )
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    withAnimation(EPTheme.spring) {
                                        isSidebarOpen.toggle()
                                    }
                                } label: {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(EPTheme.primary)
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    Task { await authSession.signOut() }
                                } label: {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                }
                                .accessibilityLabel("Cerrar sesión")
                            }
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                    }
                    .tabItem { Label(AppTab.inicio.title, systemImage: AppTab.inicio.systemImage) }
                    .tag(AppTab.inicio)

                    // Planificaciones Tab
                    NavigationStack(path: $planificacionesPath) {
                        PlanificacionesHubView(
                            dashboardRepository: dashboardRepository,
                            planificacionRepository: planificacionRepository
                        )
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    withAnimation(EPTheme.spring) {
                                        isSidebarOpen.toggle()
                                    }
                                } label: {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(EPTheme.primary)
                                        .frame(width: 34, height: 34)
                                        .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                }
                            }
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                    }
                    .tabItem { Label(AppTab.planificaciones.title, systemImage: AppTab.planificaciones.systemImage) }
                    .tag(AppTab.planificaciones)

                    // Evaluaciones Tab
                    NavigationStack(path: $evaluacionesPath) {
                        PlaceholderModuleView(tab: .evaluaciones)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button {
                                        withAnimation(EPTheme.spring) {
                                            isSidebarOpen.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(EPTheme.primary)
                                    }
                                }
                            }
                            .navigationDestination(for: AppRoute.self) { route in
                                destination(for: route)
                            }
                    }
                    .tabItem { Label(AppTab.evaluaciones.title, systemImage: AppTab.evaluaciones.systemImage) }
                    .tag(AppTab.evaluaciones)

                    // Clases Tab
                    NavigationStack(path: $clasesPath) {
                        PlaceholderModuleView(tab: .clases)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button {
                                        withAnimation(EPTheme.spring) {
                                            isSidebarOpen.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(EPTheme.primary)
                                    }
                                }
                            }
                            .navigationDestination(for: AppRoute.self) { route in
                                destination(for: route)
                            }
                    }
                    .tabItem { Label(AppTab.clases.title, systemImage: AppTab.clases.systemImage) }
                    .tag(AppTab.clases)

                    // Perfil Tab
                    NavigationStack(path: $perfilPath) {
                        ProfileView(repository: dashboardRepository, user: user)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button {
                                        withAnimation(EPTheme.spring) {
                                            isSidebarOpen.toggle()
                                        }
                                    } label: {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(EPTheme.primary)
                                    }
                                }
                            }
                            .navigationDestination(for: AppRoute.self) { route in
                                destination(for: route)
                            }
                    }
                    .tabItem { Label(AppTab.perfil.title, systemImage: AppTab.perfil.systemImage) }
                    .tag(AppTab.perfil)
                }
                .onChange(of: selectedTab) { oldTab, newTab in
                    // If they switch tabs manually (away from planificaciones), reset course selection route
                    if newTab != .planificaciones {
                        if case .coursePlanificaciones = selectedRoute {
                            selectedRoute = .module(.inicio)
                        }
                    }
                }
                .onChange(of: selectedRoute) { oldRoute, newRoute in
                    switch newRoute {
                    case .coursePlanificaciones(let course, let asignatura):
                        selectedTab = .planificaciones
                        planificacionesPath = NavigationPath([AppRoute.coursePlanificaciones(curso: course, asignatura: asignatura)])
                    case .module(let tab):
                        selectedTab = tab
                        if tab == .planificaciones {
                            planificacionesPath = NavigationPath()
                        }
                    default:
                        break
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .coursePlanificaciones(let course, let asignatura):
            PlanificacionesDetailView(
                curso: course,
                asignatura: asignatura,
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        case .verUnidad(let curso, let asignatura, let unidadId, let unidadNombre, let initialTab):
            VerUnidadDashboardView(
                curso: curso,
                asignatura: asignatura,
                unidadId: unidadId,
                unidadNombre: unidadNombre,
                initialTab: initialTab,
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        case .courseStudents(let course):
            CourseStudentsView(courseName: course, repository: dashboardRepository)
        case .editCourse(let course):
            EditCourseView(courseName: course, repository: dashboardRepository)
        case .schoolLogo:
            SchoolLogoEditView(repository: dashboardRepository)
        case .calendarConnect, .calendarSync:
            GoogleConnectionView(connectionType: "calendar", repository: dashboardRepository)
        case .driveConnect:
            GoogleConnectionView(connectionType: "drive", repository: dashboardRepository)
        default:
            RoutePlaceholderView(route: route)
        }
    }
}

