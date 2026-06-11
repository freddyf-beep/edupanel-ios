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
    case settings
    case ayuda
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
        case .settings: return "Configuración"
        case .ayuda: return "Ayuda"
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
        case .settings: return "gearshape.fill"
        case .ayuda: return "questionmark.circle.fill"
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

    @State private var selectedTab: AppTab = .inicio
    @State private var selectedRoute: AppRoute = .module(.inicio)
    @State private var isSidebarOpen = false
    @State private var tabBadges: [AppTab: Int] = [:]

    @State private var inicioPath = NavigationPath()
    @State private var planificacionesPath = NavigationPath()
    @State private var cronogramaPath = NavigationPath()
    @State private var evaluacionesPath = NavigationPath()
    @State private var clasesPath = NavigationPath()
    @State private var perfilPath = NavigationPath()

    private var activePath: Binding<NavigationPath> {
        switch selectedTab {
        case .inicio: return $inicioPath
        case .planificaciones: return $planificacionesPath
        case .cronograma: return $cronogramaPath
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
                ZStack(alignment: .bottom) {
                    tabContent
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear.frame(height: 70)
                        }

                    FloatingTabBar(selected: $selectedTab, badges: tabBadges) {
                        withAnimation(EPTheme.spring) {
                            isSidebarOpen = true
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
                }
                .onChange(of: selectedTab) { _, newTab in
                    if case .coursePlanificaciones = selectedRoute, newTab == .planificaciones {
                        return
                    }
                    selectedRoute = .module(newTab)
                }
                .onChange(of: selectedRoute) { _, newRoute in
                    switch newRoute {
                    case .coursePlanificaciones(let course, let asignatura):
                        selectedTab = .planificaciones
                        planificacionesPath = NavigationPath([AppRoute.coursePlanificaciones(curso: course, asignatura: asignatura)])
                    case .module(let tab):
                        selectedTab = tab
                    default:
                        break
                    }
                }
                .task {
                    await loadBadges()
                }
            }
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .inicio:
            tabStack(path: $inicioPath) {
                DashboardView(
                    repository: dashboardRepository,
                    user: user,
                    onOpenProfile: {
                        withAnimation(EPTheme.spring) {
                            selectedTab = .perfil
                        }
                    }
                )
            }
        case .planificaciones:
            tabStack(path: $planificacionesPath) {
                PlanificacionesHubView(
                    dashboardRepository: dashboardRepository,
                    planificacionRepository: planificacionRepository
                )
            }
        case .cronograma:
            tabStack(path: $cronogramaPath) {
                CronogramaView(
                    dashboardRepository: dashboardRepository,
                    planificacionRepository: planificacionRepository
                )
            }
        case .evaluaciones:
            tabStack(path: $evaluacionesPath) {
                PlaceholderModuleView(tab: .evaluaciones)
            }
        case .clases:
            tabStack(path: $clasesPath) {
                PlaceholderModuleView(tab: .clases)
            }
        case .perfil:
            tabStack(path: $perfilPath) {
                ProfileView(repository: dashboardRepository, user: user)
            }
        }
    }

    private func tabStack<Root: View>(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { shellToolbar }
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    @ToolbarContentBuilder
    private var shellToolbar: some ToolbarContent {
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
        ToolbarItem(placement: .topBarTrailing) {
            DisplayModeToggleButton()
        }
    }

    private func loadBadges() async {
        guard let snapshot = try? await dashboardRepository.fetchDashboard() else { return }
        let pendientes = snapshot.pendingClasses.count
        tabBadges[.inicio] = pendientes > 0 ? pendientes : nil
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsView(user: user, repository: dashboardRepository)
        case .ayuda:
            HelpView()
        case .cronograma:
            CronogramaView(
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
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
