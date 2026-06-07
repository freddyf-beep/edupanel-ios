import SwiftUI
import Observation

struct PlanificacionesHubView: View {
    @State private var viewModel: PlanificacionesViewModel
    @State private var selectedVista = "timeline"
    @State private var searchQuery = ""
    @State private var selectedCourseFilter: Set<String> = []
    @State private var selectedStateFilter: Set<UnitPlanningState> = []
    @State private var isStatsExpanded = false
    @State private var isFiltersExpanded = false

    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    private let tabs = [
        EPWebTab(id: "timeline", title: "Timeline", icon: "chart.bar.doc.horizontal"),
        EPWebTab(id: "calendario", title: "Calendario", icon: "calendar"),
        EPWebTab(id: "insights", title: "Insights", icon: "sparkles")
    ]

    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        self._viewModel = State(initialValue: PlanificacionesViewModel(
            dashboardRepository: dashboardRepository,
            planificacionRepository: planificacionRepository
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    loadingState
                } else if viewModel.snapshot != nil {
                    hubContent
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mis Planificaciones")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando planificaciones...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyState: some View {
        EPWebCard {
            VStack(spacing: 14) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(EPTheme.primary)
                Text("Sin cursos configurados")
                    .font(.headline.weight(.black))
                Text("Configura tu horario en Mi Perfil para habilitar la planificación por curso.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage = viewModel.errorMessage {
                errorBanner(message: errorMessage)
            }

            heroCard
            if viewModel.availableSubjects.count > 1 {
                subjectSelector
            }
            kpiSection
            filtersSection

            EPWebTabBar(tabs: tabs, selected: $selectedVista)

            switch selectedVista {
            case "timeline":
                PlanTimelineReplicaView(
                    planes: filteredPlanes,
                    cronogramasByUnit: viewModel.cronogramasByUnit
                )
            case "calendario":
                CalendarioReplicaView(planes: filteredPlanes)
            case "insights":
                InsightsReplicaView(
                    planes: filteredPlanes,
                    cronogramasByUnit: viewModel.cronogramasByUnit
                )
            default:
                EmptyView()
            }
        }
    }

    private var subjectSelector: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(
                    title: "Asignatura seleccionada",
                    subtitle: "Cambia para ver la planificación de otras materias que dictas.",
                    icon: "book.fill"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.availableSubjects, id: \.self) { subject in
                            let isSelected = viewModel.activeSubject == subject
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.selectedSubject = subject
                                }
                            } label: {
                                Text(subject)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(isSelected ? .white : EPTheme.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? EPTheme.primary : EPTheme.primary.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MIS PLANIFICACIONES")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.8))

                Text("\(viewModel.activeSubject) · \(courseOptions.count) Cursos")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                TextField("Buscar unidad o curso...", text: $searchQuery)
                    .font(.footnote.weight(.semibold))
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                EPPlaceholderActionButton(title: "Drive", icon: "externaldrive.fill", message: "La conexión Drive queda visible como en la web y se conectará cuando habilitemos el flujo nativo.", variant: .white)
                EPPlaceholderActionButton(title: "IA", icon: "sparkles", message: "La generación IA queda preparada para una siguiente entrega.", variant: .white)
                Spacer()
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [EPTheme.primary, EPTheme.rose, EPTheme.fuchsia],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var kpiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isStatsExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(
                        isStatsExpanded ? "Ocultar estadísticas" : "Ver estadísticas de avance",
                        systemImage: isStatsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
                    )
                    .font(.footnote.weight(.black))
                    .foregroundStyle(EPTheme.primary)
                    
                    Spacer()
                    
                    if !isStatsExpanded {
                        let stats = calculateStats()
                        HStack(spacing: 12) {
                            Text("\(stats.totalUnidades) Uni.")
                            Text("\(stats.cobertura)% Cob.")
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5), in: Capsule())
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if isStatsExpanded {
                kpiGrid
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var kpiGrid: some View {
        let stats = calculateStats()
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            EPKPIBox(title: "Total unidades", value: "\(stats.totalUnidades)", subtitle: "\(stats.totalHoras) horas registradas", icon: "square.stack.3d.up.fill", tint: .blue)
            EPKPIBox(title: "En curso", value: "\(stats.enCurso)", subtitle: "unidades activas hoy", icon: "play.circle.fill", tint: .green)
            EPKPIBox(title: "Próximas", value: "\(stats.proximas)", subtitle: "inician más adelante", icon: "calendar.badge.clock", tint: .purple)
            EPKPIBox(title: "Cobertura", value: "\(stats.cobertura)%", subtitle: "clases con OA asignados", icon: "checkmark.seal.fill", tint: .pink)
            EPKPIBox(title: "Sin fechas", value: "\(stats.sinFechas)", subtitle: "pendientes de programar", icon: "exclamationmark.triangle.fill", tint: .orange)
            EPKPIBox(title: "Cursos", value: "\(stats.totalCursos)", subtitle: "en horario activo", icon: "person.3.fill", tint: .cyan)
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isFiltersExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(
                        isFiltersExpanded ? "Ocultar filtros" : "Filtrar unidades",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.footnote.weight(.black))
                    .foregroundStyle(EPTheme.primary)
                    
                    Spacer()
                    
                    if hasActiveFilters {
                        let activeCount = (selectedCourseFilter.count) + (selectedStateFilter.count) + (searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
                        Text("\(activeCount) activos")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(EPTheme.primary, in: Capsule())
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if isFiltersExpanded {
                EPWebCard {
                    VStack(alignment: .leading, spacing: 14) {
                        filterSection(title: "Curso", values: courseOptions)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Estado")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.secondary)
                            ReplicaFlowLayout(spacing: 8) {
                                ForEach(UnitPlanningState.allCases) { state in
                                    filterChip(
                                        title: state.label,
                                        isSelected: selectedStateFilter.contains(state),
                                        tint: state.tint
                                    ) {
                                        if selectedStateFilter.contains(state) {
                                            selectedStateFilter.remove(state)
                                        } else {
                                            selectedStateFilter.insert(state)
                                        }
                                    }
                                }
                            }
                        }

                        if hasActiveFilters {
                            Button {
                                searchQuery = ""
                                selectedCourseFilter.removeAll()
                                selectedStateFilter.removeAll()
                            } label: {
                                Label("Limpiar filtros", systemImage: "xmark.circle.fill")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(EPTheme.primary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func filterSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            if values.isEmpty {
                Text("Sin cursos disponibles.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ReplicaFlowLayout(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        filterChip(
                            title: value,
                            isSelected: selectedCourseFilter.contains(value),
                            tint: EPTheme.primary
                        ) {
                            if selectedCourseFilter.contains(value) {
                                selectedCourseFilter.remove(value)
                            } else {
                                selectedCourseFilter.insert(value)
                            }
                        }
                    }
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.black))
                }
                Text(title)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? tint : tint.opacity(0.11), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Planificaciones sin sincronizar")
                    .font(.subheadline.weight(.black))
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.callout.weight(.bold))
                    .padding(8)
                    .background(Color(.systemGray6), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reintentar carga")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var hasActiveFilters: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !selectedCourseFilter.isEmpty ||
        !selectedStateFilter.isEmpty
    }

    private var courseOptions: [String] {
        Array(Set(mergedPlanes.map(\.curso))).sorted()
    }

    private var filteredPlanes: [PlanificacionCurso] {
        var result = mergedPlanes

        if !selectedCourseFilter.isEmpty {
            result = result.filter { selectedCourseFilter.contains($0.curso) }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.compactMap { plan in
                if plan.curso.localizedCaseInsensitiveContains(query) {
                    return plan
                }
                let units = plan.units.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.type.localizedCaseInsensitiveContains(query) }
                return units.isEmpty ? nil : PlanificacionCurso(curso: plan.curso, asignatura: plan.asignatura, units: units)
            }
        }

        if !selectedStateFilter.isEmpty {
            result = result.compactMap { plan in
                let units = plan.units.filter { selectedStateFilter.contains(UnitPlanningState.state(for: $0)) }
                if units.isEmpty, !plan.units.isEmpty {
                    return nil
                }
                return PlanificacionCurso(curso: plan.curso, asignatura: plan.asignatura, units: units)
            }
        }

        return result
    }

    private var mergedPlanes: [PlanificacionCurso] {
        let subject = viewModel.activeSubject
        guard let snapshot = viewModel.snapshot else {
            return uniquePlanes(viewModel.planes.filter { $0.asignatura == subject })
        }
        
        let uniqueSnapshotCourses = uniqueNormalizedCourses(snapshot.courses)
        var merged: [PlanificacionCurso] = []
        var seenCourses = Set<String>()

        for curso in uniqueSnapshotCourses {
            let normalizedCurso = normalizeCourseName(curso)
            guard !seenCourses.contains(normalizedCurso) else { continue }
            seenCourses.insert(normalizedCurso)
            
            if let existing = viewModel.planes.first(where: { 
                normalizeCourseName($0.curso) == normalizedCurso && $0.asignatura == subject 
            }) {
                var planCopy = existing
                planCopy.curso = curso
                merged.append(planCopy)
            } else {
                merged.append(PlanificacionCurso(curso: curso, asignatura: subject, units: []))
            }
        }

        return merged
    }

    private func normalizeCourseName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func uniqueNormalizedCourses(_ courses: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for course in courses {
            let normalized = normalizeCourseName(course)
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(course)
            }
        }
        return result
    }

    private func uniquePlanes(_ planes: [PlanificacionCurso]) -> [PlanificacionCurso] {
        var seen = Set<String>()
        var result: [PlanificacionCurso] = []
        for plan in planes {
            let normalized = normalizeCourseName(plan.curso)
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(plan)
            }
        }
        return result
    }

    private struct Stats {
        var totalUnidades = 0
        var totalHoras = 0
        var enCurso = 0
        var proximas = 0
        var cobertura = 0
        var sinFechas = 0
        var totalCursos = 0
    }

    private func calculateStats() -> Stats {
        let list = filteredPlanes
        var stats = Stats()
        stats.totalCursos = list.count
        var assignedClasses = 0
        var totalClasses = 0

        for plan in list {
            stats.totalUnidades += plan.units.count
            for unit in plan.units {
                stats.totalHoras += unit.hours
                switch UnitPlanningState.state(for: unit) {
                case .enCurso: stats.enCurso += 1
                case .proxima: stats.proximas += 1
                case .sinFechas: stats.sinFechas += 1
                case .completada: break
                }

                let coverage = UnitCoverage.coverage(for: unit, plan: plan, cronogramasByUnit: viewModel.cronogramasByUnit)
                assignedClasses += coverage.assigned
                totalClasses += coverage.total
            }
        }

        stats.cobertura = totalClasses > 0 ? Int((Double(assignedClasses) / Double(totalClasses)) * 100) : 0
        return stats
    }
}

enum UnitPlanningState: String, CaseIterable, Identifiable, Hashable {
    case enCurso
    case proxima
    case completada
    case sinFechas

    var id: String { rawValue }

    var label: String {
        switch self {
        case .enCurso: return "En curso"
        case .proxima: return "Próxima"
        case .completada: return "Completada"
        case .sinFechas: return "Sin fechas"
        }
    }

    var tint: Color {
        switch self {
        case .enCurso: return .green
        case .proxima: return .purple
        case .completada: return .blue
        case .sinFechas: return .orange
        }
    }

    static func state(for unit: UnidadPlan) -> UnitPlanningState {
        guard unit.hasDates,
              let start = PlanDateParser.date(from: unit.start),
              let end = PlanDateParser.date(from: unit.end) else {
            return .sinFechas
        }

        let today = Calendar.current.startOfDay(for: Date())
        if end < today { return .completada }
        if start > today { return .proxima }
        return .enCurso
    }
}

enum PlanDateParser {
    static func date(from value: String) -> Date? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        for format in ["yyyy-MM-dd", "dd/MM/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_CL")
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return Calendar.current.startOfDay(for: date)
            }
        }

        return nil
    }

    static func short(_ value: String) -> String {
        guard let date = date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

enum UnitCoverage {
    static func coverage(for unit: UnidadPlan, plan: PlanificacionCurso, cronogramasByUnit: [String: CronogramaUnidadData]) -> (assigned: Int, total: Int, percent: Int) {
        coverage(for: unit, asignatura: plan.asignatura, course: plan.curso, cronogramasByUnit: cronogramasByUnit)
    }

    static func coverage(for unit: UnidadPlan, course: String, cronogramasByUnit: [String: CronogramaUnidadData]) -> (assigned: Int, total: Int, percent: Int) {
        coverage(for: unit, asignatura: nil, course: course, cronogramasByUnit: cronogramasByUnit)
    }

    static func coverage(for unit: UnidadPlan, asignatura: String?, course: String, cronogramasByUnit: [String: CronogramaUnidadData]) -> (assigned: Int, total: Int, percent: Int) {
        let oldKey = PlanificacionRepository.cronogramaKey(curso: course, unidadId: String(unit.id))
        let subjectKey = asignatura.map { PlanificacionRepository.cronogramaKey(asignatura: $0, curso: course, unidadId: String(unit.id)) }
        guard let crono = subjectKey.flatMap({ cronogramasByUnit[$0] }) ?? cronogramasByUnit[oldKey] else {
            return (unit.hasDates ? 1 : 0, unit.hasDates ? 1 : 0, unit.hasDates ? 100 : 0)
        }

        let total = max(crono.totalClases, crono.clases.count)
        guard total > 0 else { return (0, 0, 0) }
        let assigned = crono.clases.filter { !$0.oaIds.isEmpty }.count
        return (assigned, total, Int((Double(assigned) / Double(total)) * 100))
    }
}

enum UnitRouteID {
    static func routeId(for unit: UnidadPlan, plan: PlanificacionCurso, cronogramasByUnit: [String: CronogramaUnidadData]) -> String {
        routeId(for: unit, asignatura: plan.asignatura, course: plan.curso, cronogramasByUnit: cronogramasByUnit)
    }

    static func routeId(for unit: UnidadPlan, course: String, cronogramasByUnit: [String: CronogramaUnidadData]) -> String {
        routeId(for: unit, asignatura: nil, course: course, cronogramasByUnit: cronogramasByUnit)
    }

    static func routeId(for unit: UnidadPlan, asignatura: String?, course: String, cronogramasByUnit: [String: CronogramaUnidadData]) -> String {
        let oldKey = PlanificacionRepository.cronogramaKey(curso: course, unidadId: String(unit.id))
        let subjectKey = asignatura.map { PlanificacionRepository.cronogramaKey(asignatura: $0, curso: course, unidadId: String(unit.id)) }
        if let savedId = (subjectKey.flatMap { cronogramasByUnit[$0] } ?? cronogramasByUnit[oldKey])?.unidadId.trimmingCharacters(in: .whitespacesAndNewlines),
           !savedId.isEmpty {
            return savedId
        }

        if let curricularId = unit.unidadCurricularId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !curricularId.isEmpty {
            return curricularId
        }

        return String(unit.id)
    }
}

private struct PlanTimelineReplicaView: View {
    let planes: [PlanificacionCurso]
    let cronogramasByUnit: [String: CronogramaUnidadData]

    private let months = ["Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Gantt de planificación anual", subtitle: "Filas por curso y bloques por unidad.", icon: "chart.bar.doc.horizontal.fill")

                if planes.allSatisfy(\.units.isEmpty) {
                    emptyMessage("No hay unidades planificadas para mostrar en timeline.")
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 0) {
                                Text("Curso")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 86, alignment: .leading)
                                ForEach(months, id: \.self) { month in
                                    Text(month)
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 58)
                                }
                                Text("Sin fecha")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .center)
                                    .padding(.leading, 8)
                            }

                            ForEach(planes, id: \.routeKey) { plan in
                                HStack(alignment: .center, spacing: 8) {
                                    NavigationLink(value: AppRoute.coursePlanificaciones(curso: plan.curso, asignatura: plan.asignatura)) {
                                        Text(plan.curso)
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(EPTheme.primary)
                                            .frame(width: 78, alignment: .leading)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)

                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.systemGray6))
                                            .frame(width: 580, height: 30)

                                        ForEach(plan.units.filter(\.hasDates)) { unit in
                                            unitBlock(plan: plan, unit: unit)
                                        }
                                    }
                                    .frame(width: 580, height: 34)

                                    let unscheduled = plan.units.filter { !$0.hasDates }
                                    if !unscheduled.isEmpty {
                                        Menu {
                                            ForEach(unscheduled) { unit in
                                                let routeId = UnitRouteID.routeId(for: unit, plan: plan, cronogramasByUnit: cronogramasByUnit)
                                                NavigationLink(value: AppRoute.verUnidad(curso: plan.curso, asignatura: plan.asignatura, unidadId: routeId, unidadNombre: unit.name, initialTab: "cronograma")) {
                                                    Label(unit.name, systemImage: "calendar")
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "calendar.badge.exclamationmark")
                                                Text("\(unscheduled.count)")
                                            }
                                            .font(.system(size: 9, weight: .black))
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 5)
                                            .frame(width: 46)
                                            .background(.orange.opacity(0.12), in: Capsule())
                                        }
                                        .menuStyle(.borderlessButton)
                                        .frame(width: 54)
                                    } else {
                                        Spacer().frame(width: 54)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
            }
        }
    }

    private func unitBlock(plan: PlanificacionCurso, unit: UnidadPlan) -> some View {
        let start = offset(for: unit.start)
        let end = max(start + 0.08, offset(for: unit.end))
        let width = max(54, 580 * (end - start))
        let coverage = UnitCoverage.coverage(for: unit, plan: plan, cronogramasByUnit: cronogramasByUnit).percent
        let routeId = UnitRouteID.routeId(for: unit, plan: plan, cronogramasByUnit: cronogramasByUnit)

        return NavigationLink(value: AppRoute.verUnidad(curso: plan.curso, asignatura: plan.asignatura, unidadId: routeId, unidadNombre: unit.name, initialTab: "unidad")) {
            HStack(spacing: 5) {
                Text(unit.name)
                    .font(.system(size: 9, weight: .black))
                    .lineLimit(1)
                if coverage > 0 {
                    Text("\(coverage)%")
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .frame(width: width, height: 24)
            .background(EPTheme.color(hex: unit.color), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if !unit.hasDates {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .offset(x: unit.hasDates ? 580 * start : 0)
        }
        .buttonStyle(.plain)
    }

    private func offset(for dateString: String) -> CGFloat {
        guard let date = PlanDateParser.date(from: dateString) else { return 0 }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        guard let start = calendar.date(from: DateComponents(year: year, month: 3, day: 1)),
              let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(1, date.timeIntervalSince(start) / total)))
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 22)
    }
}

private struct CalendarioReplicaView: View {
    let planes: [PlanificacionCurso]
    @State private var selectedMonthOffset = 0
    @State private var selectedDate: Date? = Calendar.current.startOfDay(for: Date())

    private let monthGrid = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)

    var body: some View {
        VStack(spacing: 16) {
            EPWebCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button {
                            selectedMonthOffset -= 1
                            selectedDate = nil
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.black))
                                .padding(8)
                                .background(Color(.systemGray6), in: Circle())
                        }
                        Spacer()
                        Text(monthYearString(for: activeMonthDate))
                            .font(.headline.weight(.black))
                        Spacer()
                        Button {
                            selectedMonthOffset += 1
                            selectedDate = nil
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.black))
                                .padding(8)
                                .background(Color(.systemGray6), in: Circle())
                        }
                    }
                    .buttonStyle(.plain)

                    HStack {
                        ForEach(["Dom", "Lun", "Mar", "Mie", "Jue", "Vie", "Sab"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    let milestones = getMilestones(for: activeMonthDate)

                    LazyVGrid(columns: monthGrid, spacing: 7) {
                        ForEach(Array(currentMonthGrid(for: activeMonthDate).enumerated()), id: \.offset) { item in
                            let date = item.element
                            dayCell(date: date, milestones: milestones)
                        }
                    }
                }
            }

            EPWebCard {
                VStack(alignment: .leading, spacing: 12) {
                    if let selectedDate {
                        EPSectionHeader(
                            title: "Hitos del \(formattedDate(selectedDate))",
                            subtitle: "Eventos planificados para esta fecha.",
                            icon: "calendar.badge.clock"
                        )

                        let dayMilestones = getMilestonesForDate(selectedDate)
                        if dayMilestones.isEmpty {
                            Text("No hay hitos programados para este día.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                        } else {
                            milestonesList(dayMilestones)
                        }
                    } else {
                        EPSectionHeader(
                            title: "Hitos de \(monthYearString(for: activeMonthDate))",
                            subtitle: "Eventos planificados para este mes. Toca un día para filtrar.",
                            icon: "calendar.badge.clock"
                        )

                        let monthMilestones = getMilestones(for: activeMonthDate)
                        if monthMilestones.isEmpty {
                            Text("No hay hitos este mes.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                        } else {
                            milestonesList(monthMilestones)
                        }
                    }
                }
            }
        }
    }

    private func milestonesList(_ milestones: [Milestone]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(milestones) { milestone in
                let routeId = UnitRouteID.routeId(for: milestone.unit, plan: milestone.plan, cronogramasByUnit: [:])
                NavigationLink(value: AppRoute.verUnidad(curso: milestone.curso, asignatura: milestone.plan.asignatura, unidadId: routeId, unidadNombre: milestone.unitName, initialTab: "unidad")) {
                    HStack(spacing: 12) {
                        VStack(spacing: 1) {
                            Text("\(milestone.day)")
                                .font(.title3.weight(.black))
                            Text(milestone.weekday)
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 38)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: milestone.isStart ? "arrow.right.circle.fill" : "stop.circle.fill")
                                    .foregroundStyle(EPTheme.color(hex: milestone.unitColor))
                                Text(milestone.isStart ? "Inicio de unidad" : "Cierre de unidad")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.secondary)
                            }
                            Text(milestone.unitName)
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(.primary)
                            Text(milestone.curso)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(11)
                    .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayCell(date: Date?, milestones: [Milestone]) -> some View {
        guard let date else {
            return AnyView(Spacer().frame(height: 38))
        }

        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let dayNum = calendar.component(.day, from: date)

        let dayMilestones = milestones.filter { calendar.isDate($0.date, inSameDayAs: date) }

        return AnyView(
            Button {
                selectedDate = date
            } label: {
                VStack(spacing: 4) {
                    Text("\(dayNum)")
                        .font(.system(size: 11, weight: isToday || isSelected ? .black : .bold))
                        .foregroundStyle(isSelected ? .white : isToday ? EPTheme.primary : .primary)
                        .frame(width: 26, height: 26)
                        .background(isSelected ? EPTheme.primary : isToday ? EPTheme.primary.opacity(0.12) : Color.clear, in: Circle())

                    HStack(spacing: 3) {
                        ForEach(dayMilestones.prefix(3)) { ms in
                            Circle()
                                .fill(EPTheme.color(hex: ms.unitColor))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.plain)
        )
    }

    private var activeMonthDate: Date {
        Calendar.current.date(byAdding: .month, value: selectedMonthOffset, to: Date()) ?? Date()
    }

    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(for: date)
    }

    private func currentMonthGrid(for monthDate: Date) -> [Date?] {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = 1
        guard let firstDay = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }

        let leadingSpaces = calendar.component(.weekday, from: firstDay) - 1
        var result: [Date?] = Array(repeating: nil, count: leadingSpaces)
        for day in dayRange {
            components.day = day
            result.append(calendar.date(from: components))
        }
        while result.count % 7 != 0 {
            result.append(nil)
        }
        return result
    }

    private struct Milestone: Identifiable {
        let id: String
        let day: Int
        let weekday: String
        let isStart: Bool
        let unitName: String
        let unitColor: String
        let curso: String
        let date: Date
        let plan: PlanificacionCurso
        let unit: UnidadPlan
    }

    private func getMilestones(for monthDate: Date) -> [Milestone] {
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: monthDate)
        let targetYear = calendar.component(.year, from: monthDate)
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "es_CL")
        weekdayFormatter.dateFormat = "EEE"

        var list: [Milestone] = []
        for plan in planes {
            for unit in plan.units where unit.hasDates {
                addMilestone(unit.start, unit: unit, plan: plan, isStart: true, targetMonth: targetMonth, targetYear: targetYear, calendar: calendar, weekdayFormatter: weekdayFormatter, to: &list)
                addMilestone(unit.end, unit: unit, plan: plan, isStart: false, targetMonth: targetMonth, targetYear: targetYear, calendar: calendar, weekdayFormatter: weekdayFormatter, to: &list)
            }
        }
        return list.sorted { $0.day < $1.day }
    }

    private func getMilestonesForDate(_ date: Date) -> [Milestone] {
        let milestones = getMilestones(for: date)
        let calendar = Calendar.current
        return milestones.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func addMilestone(
        _ dateString: String,
        unit: UnidadPlan,
        plan: PlanificacionCurso,
        isStart: Bool,
        targetMonth: Int,
        targetYear: Int,
        calendar: Calendar,
        weekdayFormatter: DateFormatter,
        to list: inout [Milestone]
    ) {
        guard let date = PlanDateParser.date(from: dateString),
              calendar.component(.month, from: date) == targetMonth,
              calendar.component(.year, from: date) == targetYear else { return }

        list.append(Milestone(
            id: "\(plan.curso)-\(unit.id)-\(isStart ? "start" : "end")",
            day: calendar.component(.day, from: date),
            weekday: weekdayFormatter.string(from: date).uppercased().replacingOccurrences(of: ".", with: ""),
            isStart: isStart,
            unitName: unit.name,
            unitColor: unit.color,
            curso: plan.curso,
            date: date,
            plan: plan,
            unit: unit
        ))
    }
}

private struct InsightsReplicaView: View {
    let planes: [PlanificacionCurso]
    let cronogramasByUnit: [String: CronogramaUnidadData]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EPWebCard {
                VStack(alignment: .leading, spacing: 12) {
                    EPSectionHeader(title: "Sugerencias", subtitle: "Alertas operativas iguales a la mirada rápida de la web.", icon: "sparkles")
                    ForEach(suggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "lightbulb.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            EPWebCard {
                VStack(alignment: .leading, spacing: 12) {
                    EPSectionHeader(title: "Cobertura por curso", subtitle: "Clases con OA asignados sobre total de clases.", icon: "checkmark.seal.fill")
                    ForEach(planes, id: \.routeKey) { plan in
                        let coverage = planCoverage(plan)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(plan.curso)
                                    .font(.footnote.weight(.black))
                                Spacer()
                                Text("\(coverage)%")
                                    .font(.footnote.weight(.black))
                                    .foregroundStyle(coverage >= 80 ? .green : coverage >= 45 ? .orange : EPTheme.primary)
                            }
                            ProgressView(value: Double(coverage) / 100.0)
                                .tint(coverage >= 80 ? .green : coverage >= 45 ? .orange : EPTheme.primary)
                        }
                    }
                }
            }

            EPWebCard {
                VStack(alignment: .leading, spacing: 12) {
                    EPSectionHeader(title: "Distribución por tipo", subtitle: "Cantidad de unidades por metodología.", icon: "chart.pie.fill")
                    ForEach(typeDistribution) { item in
                        HStack {
                            Text(typeLabel(item.type))
                                .font(.footnote.weight(.black))
                            Spacer()
                            Text("\(item.count)")
                                .font(.headline.weight(.black))
                                .foregroundStyle(EPTheme.primary)
                        }
                        .padding(10)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var suggestions: [String] {
        var list: [String] = []
        let units = planes.flatMap(\.units)
        let withoutDates = units.filter { !$0.hasDates }.count
        if withoutDates > 0 {
            list.append("\(withoutDates) unidades todavía no tienen fechas.")
        }

        let lowCoverage = planes.filter { planCoverage($0) < 50 && !$0.units.isEmpty }.map(\.curso)
        if !lowCoverage.isEmpty {
            list.append("Revisa cobertura en \(lowCoverage.prefix(3).joined(separator: ", ")).")
        }

        if list.isEmpty {
            list.append("La planificación está ordenada para los cursos filtrados.")
        }

        return list
    }

    private struct TypeDistributionItem: Identifiable {
        let type: String
        let count: Int
        var id: String { type }
    }

    private var typeDistribution: [TypeDistributionItem] {
        let grouped = Dictionary(grouping: planes.flatMap(\.units), by: \.type)
        return grouped.map { TypeDistributionItem(type: $0.key, count: $0.value.count) }.sorted { $0.type < $1.type }
    }

    private func planCoverage(_ plan: PlanificacionCurso) -> Int {
        var assigned = 0
        var total = 0
        for unit in plan.units {
            let coverage = UnitCoverage.coverage(for: unit, plan: plan, cronogramasByUnit: cronogramasByUnit)
            assigned += coverage.assigned
            total += coverage.total
        }
        return total > 0 ? Int((Double(assigned) / Double(total)) * 100) : 0
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "unidad0": return "Unidad cero"
        case "invertida": return "Clase invertida"
        case "proyecto": return "Proyecto"
        case "tradicional": return "Tradicional"
        default: return type.capitalized
        }
    }
}
