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
    case listaCotejoEditor(listaId: String?, curso: String, asignatura: String)
    case listaEvaluacion(listaId: String)
    case listaResultados(listaId: String)
    case rubricaEditor(rubricaId: String?, curso: String, asignatura: String)
    case rubricaEvaluacion(rubricaId: String)
    case rubricaResultados(rubricaId: String)
    case pruebaDetalle(pruebaId: String, scope: EvaluacionScope)
    case pruebaEditor(pruebaId: String?, curso: String, asignatura: String, scope: EvaluacionScope)
    case pruebaResultados(pruebaId: String, scope: EvaluacionScope)
    case guiaDetalle(guiaId: String, scope: EvaluacionScope)
    case guiaEditor(guiaId: String?, curso: String, asignatura: String, scope: EvaluacionScope)

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
        case .listaCotejoEditor(let listaId, _, _): return listaId == nil ? "Nueva lista" : "Editar lista"
        case .listaEvaluacion: return "Evaluar lista"
        case .listaResultados: return "Resultados de lista"
        case .rubricaEditor(let rubricaId, _, _): return rubricaId == nil ? "Nueva rúbrica" : "Editar rúbrica"
        case .rubricaEvaluacion: return "Evaluar rúbrica"
        case .rubricaResultados: return "Resultados de rúbrica"
        case .pruebaDetalle: return "Detalle de prueba"
        case .pruebaEditor(let pruebaId, _, _, _): return pruebaId == nil ? "Nueva prueba" : "Editar prueba"
        case .pruebaResultados: return "Aplicar y corregir"
        case .guiaDetalle: return "Detalle de guía"
        case .guiaEditor(let guiaId, _, _, _): return guiaId == nil ? "Nueva guía" : "Editar guía"
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
        case .listaCotejoEditor: return "checklist"
        case .listaEvaluacion: return "checkmark.circle.fill"
        case .listaResultados: return "chart.bar.fill"
        case .rubricaEditor: return "square.grid.2x2"
        case .rubricaEvaluacion: return "checkmark.circle.fill"
        case .rubricaResultados: return "chart.bar.fill"
        case .pruebaDetalle: return "doc.text.fill"
        case .pruebaEditor: return "square.and.pencil"
        case .pruebaResultados: return "checkmark.rectangle.stack.fill"
        case .guiaDetalle: return "book.pages.fill"
        case .guiaEditor: return "square.and.pencil"
        }
    }

}

struct AppShell: View {
    @Environment(AuthSession.self) private var authSession

    let user: AuthenticatedUser
    let dashboardRepository: DashboardRepository
    private let planificacionRepository = PlanificacionRepository()
    private let evaluacionesRepository = EvaluacionesRepository()

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
                    },
                    onOpenPlanificaciones: {
                        withAnimation(EPTheme.spring) {
                            selectedTab = .planificaciones
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
                EvaluacionesShell(
                    dashboardRepository: dashboardRepository,
                    evaluacionesRepository: evaluacionesRepository
                )
            }
        case .clases:
            tabStack(path: $clasesPath) {
                ClasesView(
                    dashboardRepository: dashboardRepository,
                    planificacionRepository: planificacionRepository
                )
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
        case .module(.inicio):
            DashboardView(
                repository: dashboardRepository,
                user: user,
                onOpenProfile: {
                    withAnimation(EPTheme.spring) {
                        selectedTab = .perfil
                    }
                },
                onOpenPlanificaciones: {
                    withAnimation(EPTheme.spring) {
                        selectedTab = .planificaciones
                    }
                }
            )
        case .module(.planificaciones), .planificacionNueva:
            PlanificacionesHubView(
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        case .module(.cronograma), .cronograma:
            CronogramaView(
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        case .actividades:
            ActividadesHubView(
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        case .module(.evaluaciones), .evaluacionNueva:
            EvaluacionesShell(
                dashboardRepository: dashboardRepository,
                evaluacionesRepository: evaluacionesRepository
            )
        case .module(.clases):
            ClasesView(
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        case .module(.perfil), .newScheduleBlock, .perfilAction(_):
            ProfileView(repository: dashboardRepository, user: user)
        case .settings:
            SettingsView(user: user, repository: dashboardRepository)
        case .ayuda:
            HelpView()
        case .perfil360:
            Perfil360View(user: user, repository: dashboardRepository)
        case .calificaciones:
            CalificacionesView(dashboardRepository: dashboardRepository)
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
        case .classDetail(let id, let title):
            ClassDetailView(
                classId: id,
                title: title,
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        case .listaCotejoEditor(let listaId, let curso, let asignatura):
            ListaCotejoEditorView(
                listaId: listaId,
                curso: curso,
                asignatura: asignatura,
                dashboardRepository: dashboardRepository
            )
        case .listaEvaluacion(let listaId):
            ListaEvaluacionView(listaId: listaId, dashboardRepository: dashboardRepository)
        case .listaResultados(let listaId):
            ListaResultadosView(listaId: listaId, dashboardRepository: dashboardRepository)
        case .rubricaEditor(let rubricaId, let curso, let asignatura):
            RubricaEditorView(
                rubricaId: rubricaId,
                curso: curso,
                asignatura: asignatura,
                dashboardRepository: dashboardRepository
            )
        case .rubricaEvaluacion(let rubricaId):
            RubricaEvaluacionView(rubricaId: rubricaId, dashboardRepository: dashboardRepository)
        case .rubricaResultados(let rubricaId):
            RubricaResultadosView(rubricaId: rubricaId, dashboardRepository: dashboardRepository)
        case .pruebaDetalle(let pruebaId, let scope):
            PruebaDetalleView(
                pruebaId: pruebaId,
                scope: scope,
                repository: evaluacionesRepository,
                dashboardRepository: dashboardRepository
            )
        case .pruebaEditor(let pruebaId, let curso, let asignatura, let scope):
            PruebaEditorView(
                pruebaId: pruebaId,
                curso: curso,
                asignatura: asignatura,
                scope: scope,
                repository: evaluacionesRepository,
                dashboardRepository: dashboardRepository
            )
        case .pruebaResultados(let pruebaId, let scope):
            PruebaResultadosView(
                pruebaId: pruebaId,
                scope: scope,
                repository: evaluacionesRepository
            )
        case .guiaDetalle(let guiaId, let scope):
            GuiaDetalleView(
                guiaId: guiaId,
                scope: scope,
                repository: evaluacionesRepository,
                dashboardRepository: dashboardRepository
            )
        case .guiaEditor(let guiaId, let curso, let asignatura, let scope):
            GuiaEditorView(
                guiaId: guiaId,
                curso: curso,
                asignatura: asignatura,
                scope: scope,
                repository: evaluacionesRepository,
                dashboardRepository: dashboardRepository
            )
        }
    }
}
