import SwiftUI
import Observation

struct PlanificacionesHubView: View {
    @State private var viewModel: PlanificacionesViewModel
    @State private var selectedVista = "timeline"
    @State private var searchQuery = ""
    @State private var filtroCurso: Set<String> = []
    @State private var filtroEstado: Set<UnitPlanningState> = []
    @State private var mesActual = Calendar.current.startOfDay(for: Date())
    @State private var courseForSubjectPicker: CoursePlanningGroup?
    @State private var planningDestination: PlanningDestination?

    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    private let tabs = [
        EPWebTab(id: "timeline", title: "Timeline anual", icon: "chart.bar.doc.horizontal"),
        EPWebTab(id: "cursos", title: "Cursos", icon: "graduationcap.fill"),
        EPWebTab(id: "calendario", title: "Calendario", icon: "calendar"),
        EPWebTab(id: "insights", title: "Insights", icon: "chart.bar.xaxis")
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
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    loadingState
                } else if viewModel.snapshot != nil {
                    hubContent
                } else {
                    emptyCoursesState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .reportsTabBarScroll()
        .background(EPTheme.background)
        .navigationTitle("Mis Planificaciones")
        .navigationDestination(item: $planningDestination) { destination in
            PlanificacionesDetailView(
                curso: destination.course,
                asignatura: destination.subject,
                dashboardRepository: dashboardRepository,
                planificacionRepository: planificacionRepository
            )
        }
        .confirmationDialog(
            courseForSubjectPicker?.course ?? "Asignaturas",
            isPresented: Binding(
                get: { courseForSubjectPicker != nil },
                set: { isPresented in
                    if !isPresented { courseForSubjectPicker = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let group = courseForSubjectPicker {
                ForEach(group.plans) { plan in
                    Button(plan.asignatura) {
                        open(plan)
                    }
                }
            }

            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Elige una asignatura")
        }
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
            Text("Cargando planificaciones…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyCoursesState: some View {
        EPWebCard {
            EPEmptyState(
                icon: "graduationcap.fill",
                title: "Sin cursos aún",
                message: "Configura tu horario en Mi Perfil con bloques tipo \"clase\" para que aparezcan aquí."
            )
        }
    }

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = viewModel.errorMessage {
                errorBanner(message: errorMessage)
            }

            heroCard

            if cursosInfo.isEmpty {
                emptyCoursesState
            } else {
                CoursePlanningGrid(groups: courseGroups, onOpen: openCourse)
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            EPPageHeader(
                eyebrow: "Planificación",
                title: "Tus cursos",
                subtitle: "Un toque para continuar planificando.",
                icon: "books.vertical.fill"
            )

            Label("\(courseGroups.count) cursos", systemImage: "rectangle.grid.2x2.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
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

    // MARK: - KPIs

    private var kpiGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                EPKPIBox(title: "Total unidades", value: "\(stats.total)", subtitle: "\(stats.totalHoras)h totales", icon: "square.stack.3d.up.fill", tint: EPTheme.primary)
                    .frame(width: 145)
                EPKPIBox(title: "En curso", value: "\(stats.enCurso)", subtitle: "ahora", icon: "play.circle.fill", tint: stats.enCurso > 0 ? .green : .gray)
                    .frame(width: 145)
                EPKPIBox(title: "Cobertura", value: "\(stats.cobertura)%", subtitle: "con fechas", icon: "checkmark.seal.fill", tint: coberturaTint(stats.cobertura))
                    .frame(width: 145)
                EPKPIBox(title: "Próximas", value: "\(stats.proximas)", subtitle: "planificadas", icon: "calendar.badge.clock", tint: .blue)
                    .frame(width: 145)
                EPKPIBox(title: "Sin fechas", value: "\(stats.incompletas)", subtitle: "por completar", icon: "exclamationmark.triangle.fill", tint: stats.incompletas == 0 ? .green : .orange)
                    .frame(width: 145)
                EPKPIBox(title: "Cursos", value: "\(cursosInfo.count)", subtitle: "activos", icon: "person.3.fill", tint: EPTheme.primary)
                    .frame(width: 145)
            }
        }
    }

    private func coberturaTint(_ pct: Int) -> Color {
        pct >= 80 ? .green : pct >= 50 ? .orange : .red
    }

    // MARK: - Filtros

    private var filtrosCard: some View {
        EPWebCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURSO")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                    ReplicaFlowLayout(spacing: 8) {
                        ForEach(cursosInfo) { curso in
                            cursoChip(curso)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("ESTADO")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                    ReplicaFlowLayout(spacing: 8) {
                        ForEach(UnitPlanningState.allCases) { estado in
                            estadoChip(estado)
                        }
                    }
                }

                HStack {
                    if hasActiveFilters {
                        Button {
                            withAnimation(EPTheme.spring) {
                                searchQuery = ""
                                filtroCurso.removeAll()
                                filtroEstado.removeAll()
                            }
                        } label: {
                            Label("Limpiar filtros", systemImage: "wand.and.stars")
                                .font(.caption.weight(.black))
                                .foregroundStyle(EPTheme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("\(unidadesFiltradas.count)/\(stats.total) unidades visibles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cursoChip(_ curso: CursoInfo) -> some View {
        let isSelected = filtroCurso.contains(curso.curso)
        return Button {
            withAnimation(EPTheme.spring) {
                if isSelected {
                    filtroCurso.remove(curso.curso)
                } else {
                    filtroCurso.insert(curso.curso)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.black))
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.white : EPTheme.color(hex: curso.color))
                    .frame(width: 8, height: 8)
                Text(curso.curso)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : EPTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? EPTheme.primary : EPTheme.primary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func estadoChip(_ estado: UnitPlanningState) -> some View {
        let isSelected = filtroEstado.contains(estado)
        return Button {
            withAnimation(EPTheme.spring) {
                if isSelected {
                    filtroEstado.remove(estado)
                } else {
                    filtroEstado.insert(estado)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.black))
                }
                Text(estado.label)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : estado.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? estado.tint : estado.tint.opacity(0.12), in: Capsule())
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

    // MARK: - Datos derivados

    private var hasActiveFilters: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !filtroCurso.isEmpty ||
        !filtroEstado.isEmpty
    }

    private var cursosInfo: [CursoInfo] {
        mergedPlanes.enumerated().map { index, plan in
            let completas = plan.units.filter(\.hasDates).count
            return CursoInfo(
                curso: plan.curso,
                asignatura: plan.asignatura,
                color: CursoPalette.color(at: index),
                unidades: plan.units,
                totalHoras: plan.units.reduce(0) { $0 + $1.hours },
                cobertura: plan.units.isEmpty ? 0 : Int(round(Double(completas) / Double(plan.units.count) * 100))
            )
        }
    }

    private var filteredCursos: [CursoInfo] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cursosInfo }
        return cursosInfo.filter {
            $0.curso.localizedCaseInsensitiveContains(query) ||
            $0.asignatura.localizedCaseInsensitiveContains(query)
        }
    }

    private var courseGroups: [CoursePlanningGroup] {
        var groups: [CoursePlanningGroup] = []

        for plan in cursosInfo {
            let id = normalizeCourseName(plan.curso)
            if let index = groups.firstIndex(where: { $0.id == id }) {
                groups[index].plans.append(plan)
            } else {
                groups.append(CoursePlanningGroup(id: id, course: plan.curso, color: plan.color, plans: [plan]))
            }
        }

        return groups
    }

    private func openCourse(_ group: CoursePlanningGroup) {
        guard group.plans.count == 1, let plan = group.plans.first else {
            courseForSubjectPicker = group
            return
        }
        open(plan)
    }

    private func open(_ plan: CursoInfo) {
        courseForSubjectPicker = nil
        planningDestination = PlanningDestination(course: plan.curso, subject: plan.asignatura)
    }

    private var todasUnidades: [UnidadConCurso] {
        cursosInfo.flatMap { curso in
            curso.unidades.map { unit in
                UnidadConCurso(unit: unit, curso: curso.curso, asignatura: curso.asignatura, cursoColor: curso.color)
            }
        }
    }

    private var unidadesFiltradas: [UnidadConCurso] {
        todasUnidades.filter { item in
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty,
               !item.unit.name.localizedCaseInsensitiveContains(query),
               !item.curso.localizedCaseInsensitiveContains(query) {
                return false
            }
            if !filtroCurso.isEmpty, !filtroCurso.contains(item.curso) {
                return false
            }
            if !filtroEstado.isEmpty, !filtroEstado.contains(UnitPlanningState.state(for: item.unit)) {
                return false
            }
            return true
        }
    }

    private var stats: HubStats {
        let unidades = todasUnidades.map(\.unit)
        let conFechas = unidades.filter(\.hasDates).count
        var enCurso = 0
        var proximas = 0
        var incompletas = 0
        for unit in unidades {
            switch UnitPlanningState.state(for: unit) {
            case .actual: enCurso += 1
            case .futura: proximas += 1
            case .incompleta: incompletas += 1
            case .pasada: break
            }
        }
        return HubStats(
            total: unidades.count,
            conFechas: conFechas,
            enCurso: enCurso,
            proximas: proximas,
            incompletas: incompletas,
            cobertura: unidades.isEmpty ? 0 : Int(round(Double(conFechas) / Double(unidades.count) * 100)),
            totalHoras: unidades.reduce(0) { $0 + $1.hours }
        )
    }

    private var mergedPlanes: [PlanificacionCurso] {
        var merged: [PlanificacionCurso] = []
        var seenRoutes = Set<String>()

        for plan in viewModel.planes {
            let key = "\(normalizeCourseName(plan.curso))::\(normalizeCourseName(plan.asignatura))"
            guard seenRoutes.insert(key).inserted else { continue }
            merged.append(plan)
        }

        let fallbackSubject = viewModel.availableSubjects.first ?? "Música"
        for course in uniqueNormalizedCourses(viewModel.snapshot?.courses ?? []) {
            let normalizedCourse = normalizeCourseName(course)
            guard !merged.contains(where: { normalizeCourseName($0.curso) == normalizedCourse }) else { continue }
            merged.append(PlanificacionCurso(curso: course, asignatura: fallbackSubject, units: []))
        }

        return merged.sorted {
            let courseOrder = $0.curso.localizedStandardCompare($1.curso)
            if courseOrder == .orderedSame {
                return $0.asignatura.localizedStandardCompare($1.asignatura) == .orderedAscending
            }
            return courseOrder == .orderedAscending
        }
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
}

// MARK: - Modelos derivados del hub

struct CursoInfo: Identifiable {
    let curso: String
    let asignatura: String
    let color: String
    let unidades: [UnidadPlan]
    let totalHoras: Int
    let cobertura: Int

    var id: String { "\(asignatura)::\(curso)" }
}

struct UnidadConCurso: Identifiable {
    let unit: UnidadPlan
    let curso: String
    let asignatura: String
    let cursoColor: String

    var id: String { "\(asignatura)::\(curso)::\(unit.id)" }

    var displayColor: String {
        unit.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cursoColor : unit.color
    }
}

struct HubStats {
    let total: Int
    let conFechas: Int
    let enCurso: Int
    let proximas: Int
    let incompletas: Int
    let cobertura: Int
    let totalHoras: Int
}

enum CursoPalette {
    static let colors = ["#F59E0B", "#3B82F6", "#EF4444", "#22C55E", "#8B5CF6", "#F03E6E", "#06B6D4", "#D97706"]

    static func color(at index: Int) -> String {
        colors[index % colors.count]
    }
}

// MARK: - Helpers compartidos

enum UnitPlanningState: String, CaseIterable, Identifiable, Hashable {
    case futura
    case actual
    case pasada
    case incompleta

    var id: String { rawValue }

    var label: String {
        switch self {
        case .futura: return "Próxima"
        case .actual: return "En curso"
        case .pasada: return "Cerrada"
        case .incompleta: return "Sin fechas"
        }
    }

    var tint: Color {
        switch self {
        case .futura: return .blue
        case .actual: return .green
        case .pasada: return .gray
        case .incompleta: return .orange
        }
    }

    var icon: String {
        switch self {
        case .futura: return "clock.fill"
        case .actual: return "waveform.path.ecg"
        case .pasada: return "checkmark"
        case .incompleta: return "exclamationmark.triangle.fill"
        }
    }

    static func state(for unit: UnidadPlan) -> UnitPlanningState {
        guard let start = PlanDateParser.date(from: unit.start),
              let end = PlanDateParser.date(from: unit.end) else {
            return .incompleta
        }

        let hoy = Calendar.current.startOfDay(for: Date())
        if hoy < start { return .futura }
        if hoy > end { return .pasada }
        return .actual
    }
}

enum TipoUnidad {
    static let all = ["tradicional", "invertida", "proyecto", "unidad0"]

    static func label(_ type: String) -> String {
        switch type {
        case "unidad0": return "Unidad 0"
        case "invertida": return "Invertida"
        case "proyecto": return "Proyecto"
        case "tradicional": return "Tradicional"
        default: return type.capitalized
        }
    }

    static func emoji(_ type: String) -> String {
        switch type {
        case "unidad0": return "0️⃣"
        case "invertida": return "🔄"
        case "proyecto": return "🎯"
        default: return "📘"
        }
    }

    static func tint(_ type: String) -> Color {
        switch type {
        case "unidad0": return .orange
        case "invertida": return .purple
        case "proyecto": return .green
        default: return .gray
        }
    }

    static func icon(_ type: String) -> String {
        switch type {
        case "unidad0": return "0.circle.fill"
        case "invertida": return "arrow.triangle.2.circlepath"
        case "proyecto": return "target"
        default: return "book.closed.fill"
        }
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

    static func diasDesdeHoy(hasta value: String) -> Int? {
        guard let date = date(from: value) else { return nil }
        let hoy = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: hoy, to: date).day
    }
}

enum UnitCoverage {
    static func coverage(for unit: UnidadPlan, asignatura: String?, course: String, cronogramasByUnit: [String: CronogramaUnidadData]) -> (assigned: Int, total: Int, percent: Int) {
        let oldKey = PlanificacionRepository.cronogramaKey(curso: course, unidadId: String(unit.id))
        let subjectKey = asignatura.map { PlanificacionRepository.cronogramaKey(asignatura: $0, curso: course, unidadId: String(unit.id)) }
        guard let crono = subjectKey.flatMap({ cronogramasByUnit[$0] }) ?? cronogramasByUnit[oldKey] else {
            return (0, 0, 0)
        }

        let total = max(crono.totalClases, crono.clases.count)
        guard total > 0 else { return (0, 0, 0) }
        let assigned = crono.clases.filter { !$0.fecha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return (assigned, total, Int(round(Double(assigned) / Double(total) * 100)))
    }
}

enum UnitRouteID {
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

// MARK: - Timeline anual

private struct TimelineAnualView: View {
    let cursos: [CursoInfo]
    let unidades: [UnidadConCurso]
    let cronogramasByUnit: [String: CronogramaUnidadData]

    private let labelWidth: CGFloat = 96
    private let trackWidth: CGFloat = 580
    private let mesesCorto = ["Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    EPSectionHeader(
                        title: "Timeline \(anioActual)",
                        subtitle: "Filas por curso y barras por unidad.",
                        icon: "chart.bar.doc.horizontal.fill"
                    )
                    EPStatusPill(text: "Año académico Mar–Dic", tint: .gray)
                }

                if filas.isEmpty {
                    Text("Sin unidades en estos filtros.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 22)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            headerRow
                            ForEach(filas) { fila in
                                cursoRow(fila.curso, unidades: fila.unidades)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(EPTheme.primary)
                                .frame(width: 12, height: 8)
                            Text("Hoy")
                        }
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                .frame(width: 12, height: 8)
                            Text("Sin fechas")
                        }
                        Text("Toca una unidad para abrirla.")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Curso")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(mesesCorto, id: \.self) { mes in
                        Text(mes)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                            .frame(width: trackWidth / 10)
                    }
                }
                if let x = hoyX {
                    Text("HOY")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(EPTheme.primary, in: Capsule())
                        .offset(x: max(0, min(trackWidth - 30, x - 15)), y: 14)
                }
            }
            .frame(width: trackWidth, alignment: .leading)
        }
        .padding(.bottom, hoyX == nil ? 0 : 14)
    }

    private func cursoRow(_ curso: CursoInfo, unidades: [UnidadConCurso]) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: AppRoute.coursePlanificaciones(curso: curso.curso, asignatura: curso.asignatura)) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(EPTheme.color(hex: curso.color))
                        .frame(width: 9, height: 9)
                    Text(curso.curso)
                        .font(.caption.weight(.black))
                        .foregroundStyle(EPTheme.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(unidades.count)u")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.secondary)
                }
                .frame(width: labelWidth, alignment: .leading)
            }
            .buttonStyle(.plain)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemGray6))
                    .frame(width: trackWidth, height: 34)
                if let x = hoyX {
                    Rectangle()
                        .fill(EPTheme.primary.opacity(0.45))
                        .frame(width: 2, height: 34)
                        .offset(x: x)
                }
                ForEach(Array(unidades.enumerated()), id: \.element.id) { idx, item in
                    barraUnidad(item, idx: idx, totalEnFila: unidades.count)
                }
            }
            .frame(width: trackWidth, height: 34)
        }
    }

    @ViewBuilder
    private func barraUnidad(_ item: UnidadConCurso, idx: Int, totalEnFila: Int) -> some View {
        let routeId = UnitRouteID.routeId(for: item.unit, asignatura: item.asignatura, course: item.curso, cronogramasByUnit: cronogramasByUnit)

        if let ini = PlanDateParser.date(from: item.unit.start),
           let fin = PlanDateParser.date(from: item.unit.end) {
            let startPct = fraccionAnual(ini)
            let endPct = max(startPct + 0.02, fraccionAnual(fin))
            let ancho = max(46, trackWidth * (endPct - startPct))
            let x = min(trackWidth * startPct, trackWidth - ancho)

            NavigationLink(value: AppRoute.verUnidad(curso: item.curso, asignatura: item.asignatura, unidadId: routeId, unidadNombre: item.unit.name, initialTab: "unidad")) {
                Text(item.unit.name)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(width: ancho, height: 26, alignment: .leading)
                    .background(EPTheme.color(hex: item.displayColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .offset(x: x)
        } else {
            NavigationLink(value: AppRoute.verUnidad(curso: item.curso, asignatura: item.asignatura, unidadId: routeId, unidadNombre: item.unit.name, initialTab: "cronograma")) {
                Text("?")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.orange)
                    .frame(width: 40, height: 26)
                    .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    )
            }
            .buttonStyle(.plain)
            .offset(x: min(trackWidth - 40, trackWidth * CGFloat(idx) / CGFloat(max(1, totalEnFila))))
        }
    }

    private struct Fila: Identifiable {
        let curso: CursoInfo
        let unidades: [UnidadConCurso]

        var id: String { curso.id }
    }

    private var filas: [Fila] {
        cursos.compactMap { curso in
            let propias = unidades.filter { $0.curso == curso.curso && $0.asignatura == curso.asignatura }
            return propias.isEmpty ? nil : Fila(curso: curso, unidades: propias)
        }
    }

    private var anioActual: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var rangoAnual: (inicio: Date, fin: Date)? {
        let calendar = Calendar.current
        guard let inicio = calendar.date(from: DateComponents(year: anioActual, month: 3, day: 1)),
              let fin = calendar.date(from: DateComponents(year: anioActual, month: 12, day: 31)) else { return nil }
        return (inicio, fin)
    }

    private var hoyX: CGFloat? {
        guard let rango = rangoAnual else { return nil }
        let hoy = Calendar.current.startOfDay(for: Date())
        guard hoy >= rango.inicio, hoy <= rango.fin else { return nil }
        return trackWidth * fraccionAnual(hoy)
    }

    private func fraccionAnual(_ date: Date) -> CGFloat {
        guard let rango = rangoAnual else { return 0 }
        let total = rango.fin.timeIntervalSince(rango.inicio)
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(1, date.timeIntervalSince(rango.inicio) / total)))
    }
}

// MARK: - Navegación rápida por curso

private struct CoursePlanningGroup: Identifiable {
    let id: String
    let course: String
    let color: String
    var plans: [CursoInfo]
}

private struct PlanningDestination: Identifiable, Hashable {
    let course: String
    let subject: String

    var id: String { "\(course)::\(subject)" }
}

private struct CoursePlanningGrid: View {
    let groups: [CoursePlanningGroup]
    let onOpen: (CoursePlanningGroup) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
            ForEach(groups) { group in
                Button {
                    onOpen(group)
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(initials(group.course))
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(EPTheme.color(hex: group.color))
                                .frame(width: 44, height: 44)
                                .background(EPTheme.color(hex: group.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Spacer()

                            Image(systemName: group.plans.count > 1 ? "ellipsis" : "arrow.up.right")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.course)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(group.plans.count == 1 ? "Abrir planificación" : "\(group.plans.count) asignaturas")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
                    .padding(14)
                    .background(EPTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(EPTheme.border, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .accessibilityHint(group.plans.count == 1 ? "Abre directamente la planificación" : "Muestra las asignaturas del curso")
            }
        }
    }

    private func initials(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: " ", with: "")
        return String(compact.prefix(3)).uppercased()
    }
}

// MARK: - Calendario mensual

private struct CalendarioMensualView: View {
    @Binding var mes: Date
    let unidades: [UnidadConCurso]

    private let columnas = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let diasSemana = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EPWebCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            cambiarMes(-1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.black))
                                .padding(8)
                                .background(Color(.systemGray6), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(tituloMes)
                            .font(.headline.weight(.black))

                        Spacer()

                        Button {
                            cambiarMes(1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.black))
                                .padding(8)
                                .background(Color(.systemGray6), in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            mes = Calendar.current.startOfDay(for: Date())
                        } label: {
                            Text("Hoy")
                                .font(.caption.weight(.black))
                                .foregroundStyle(EPTheme.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(EPTheme.primary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        ForEach(diasSemana, id: \.self) { dia in
                            Text(dia)
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    let hitos = hitosDelMes

                    LazyVGrid(columns: columnas, spacing: 6) {
                        ForEach(Array(diasDelMes.enumerated()), id: \.offset) { item in
                            celda(item.element, hitos: hitos)
                        }
                    }

                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(EPTheme.primary)
                                .frame(width: 8, height: 8)
                            Text("Inicia unidad")
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(EPTheme.primary, lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                            Text("Termina unidad")
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(EPTheme.primary.opacity(0.12))
                                .frame(width: 8, height: 8)
                            Text("Hoy")
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
            }

            EPWebCard {
                VStack(alignment: .leading, spacing: 12) {
                    EPSectionHeader(
                        title: "Unidades activas en \(nombreMes)",
                        subtitle: "Unidades cuyo rango de fechas cruza este mes.",
                        icon: "pin.fill"
                    )

                    let activas = unidadesActivasDelMes
                    if activas.isEmpty {
                        Text("Sin unidades en este mes.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(activas) { item in
                            NavigationLink(value: AppRoute.coursePlanificaciones(curso: item.curso, asignatura: item.asignatura)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(EPTheme.color(hex: item.displayColor))
                                            .frame(width: 8, height: 8)
                                        Text(item.unit.name)
                                            .font(.footnote.weight(.black))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(item.curso) · \(item.unit.hours)h")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text("\(item.unit.start) → \(item.unit.end)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private struct Hito: Identifiable {
        let id: String
        let fecha: Date
        let esInicio: Bool
        let unidad: UnidadConCurso
    }

    @ViewBuilder
    private func celda(_ date: Date?, hitos: [Hito]) -> some View {
        if let date {
            let calendar = Calendar.current
            let esHoy = calendar.isDateInToday(date)
            let delDia = hitos.filter { calendar.isDate($0.fecha, inSameDayAs: date) }

            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 11, weight: esHoy ? .black : .bold))
                    .foregroundStyle(esHoy ? EPTheme.primary : .primary)

                HStack(spacing: 3) {
                    ForEach(Array(delDia.prefix(3))) { hito in
                        if hito.esInicio {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(EPTheme.color(hex: hito.unidad.displayColor))
                                .frame(width: 7, height: 7)
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(EPTheme.color(hex: hito.unidad.displayColor), lineWidth: 1.5)
                                .frame(width: 7, height: 7)
                        }
                    }
                    if delDia.count > 3 {
                        Text("+\(delDia.count - 3)")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(esHoy ? EPTheme.primary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if esHoy {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(EPTheme.primary, lineWidth: 1.5)
                }
            }
        } else {
            Color.clear
                .frame(minHeight: 42)
        }
    }

    private var hitosDelMes: [Hito] {
        let calendar = Calendar.current
        let mesObjetivo = calendar.component(.month, from: mes)
        let anioObjetivo = calendar.component(.year, from: mes)

        var lista: [Hito] = []
        for item in unidades where item.unit.hasDates {
            if let inicio = PlanDateParser.date(from: item.unit.start),
               calendar.component(.month, from: inicio) == mesObjetivo,
               calendar.component(.year, from: inicio) == anioObjetivo {
                lista.append(Hito(id: "\(item.id)-inicio", fecha: inicio, esInicio: true, unidad: item))
            }
            if let fin = PlanDateParser.date(from: item.unit.end),
               calendar.component(.month, from: fin) == mesObjetivo,
               calendar.component(.year, from: fin) == anioObjetivo {
                lista.append(Hito(id: "\(item.id)-fin", fecha: fin, esInicio: false, unidad: item))
            }
        }
        return lista
    }

    private var unidadesActivasDelMes: [UnidadConCurso] {
        guard let rango = rangoDelMes else { return [] }
        return unidades.filter { item in
            guard let inicio = PlanDateParser.date(from: item.unit.start),
                  let fin = PlanDateParser.date(from: item.unit.end) else { return false }
            return !(fin < rango.inicio || inicio > rango.fin)
        }
    }

    private var rangoDelMes: (inicio: Date, fin: Date)? {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: mes)
        comps.day = 1
        guard let inicio = calendar.date(from: comps),
              let dias = calendar.range(of: .day, in: .month, for: inicio) else { return nil }
        comps.day = dias.count
        guard let fin = calendar.date(from: comps) else { return nil }
        return (inicio, fin)
    }

    private var diasDelMes: [Date?] {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: mes)
        comps.day = 1
        guard let primerDia = calendar.date(from: comps),
              let rango = calendar.range(of: .day, in: .month, for: primerDia) else { return [] }

        let weekday = calendar.component(.weekday, from: primerDia)
        let offset = (weekday + 5) % 7
        var resultado: [Date?] = Array(repeating: nil, count: offset)
        for dia in rango {
            comps.day = dia
            resultado.append(calendar.date(from: comps))
        }
        while resultado.count % 7 != 0 {
            resultado.append(nil)
        }
        return resultado
    }

    private var tituloMes: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: mes).capitalized
    }

    private var nombreMes: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: mes).capitalized
    }

    private func cambiarMes(_ delta: Int) {
        if let nueva = Calendar.current.date(byAdding: .month, value: delta, to: mes) {
            mes = nueva
        }
    }
}

// MARK: - Insights

private struct InsightsReplicaView: View {
    let cursos: [CursoInfo]
    let unidades: [UnidadConCurso]
    let stats: HubStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sugerenciasCard
            distribucionCard
            coberturaPorCursoCard

            if !proximas30.isEmpty {
                proximas30Card
            }

            if !incompletas.isEmpty {
                sinFechasCard
            }
        }
    }

    private struct Sugerencia: Identifiable {
        let titulo: String
        let texto: String
        let tint: Color

        var id: String { titulo }
    }

    private struct ConteoTipo: Identifiable {
        let tipo: String
        let cantidad: Int

        var id: String { tipo }
    }

    private struct ProximaUnidad: Identifiable {
        let unidad: UnidadConCurso
        let dias: Int

        var id: String { unidad.id }
    }

    private var sugerenciasCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(title: "Sugerencias de planificación", subtitle: nil, icon: "sparkles")

                if sugerencias.isEmpty {
                    Text("¡Todo en orden! No hay sugerencias urgentes.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sugerencias) { sugerencia in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sugerencia.titulo)
                                .font(.footnote.weight(.black))
                                .foregroundStyle(.primary)
                            Text(sugerencia.texto)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(sugerencia.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(sugerencia.tint.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private var distribucionCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Distribución por tipo", subtitle: "Cantidad de unidades por metodología.", icon: "target")

                let conteos = distribucionPorTipo
                let maximo = max(1, conteos.map(\.cantidad).max() ?? 1)

                ForEach(conteos) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(TipoUnidad.label(item.tipo))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(item.cantidad)")
                                .font(.caption.weight(.black))
                        }
                        barra(fraccion: Double(item.cantidad) / Double(maximo))
                    }
                }
            }
        }
    }

    private func barra(fraccion: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                Capsule()
                    .fill(LinearGradient(colors: [EPTheme.primary, EPTheme.fuchsia], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * fraccion)
            }
        }
        .frame(height: 8)
    }

    private var coberturaPorCursoCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Cobertura por curso", subtitle: "Porcentaje de unidades con fechas asignadas.", icon: "waveform.path.ecg")

                if cursos.isEmpty {
                    Text("Sin cursos.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cursos) { curso in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(EPTheme.color(hex: curso.color))
                                    .frame(width: 9, height: 9)
                                Text(curso.curso)
                                    .font(.caption.weight(.black))
                                    .lineLimit(1)
                                Text("· \(curso.unidades.count)u · \(curso.totalHoras)h")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(curso.cobertura)%")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(coberturaColor(curso.cobertura))
                            }
                            ProgressView(value: Double(curso.cobertura) / 100.0)
                                .tint(coberturaColor(curso.cobertura))
                        }
                    }
                }
            }
        }
    }

    private var proximas30Card: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(title: "Próximas 30 días", subtitle: "Unidades que inician pronto.", icon: "clock.fill")

                ForEach(proximas30) { item in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(EPTheme.color(hex: item.unidad.displayColor))
                            .frame(width: 4, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.unidad.unit.name)
                                .font(.footnote.weight(.black))
                                .lineLimit(1)
                            Text(etiquetaInicio(item))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        EPStatusPill(text: TipoUnidad.label(item.unidad.unit.type), tint: TipoUnidad.tint(item.unidad.unit.type))
                    }
                    .padding(10)
                    .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var sinFechasCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(title: "Sin fechas asignadas (\(incompletas.count))", subtitle: "Asígnales rango de inicio y fin para verlas en timeline y calendario.", icon: "exclamationmark.triangle.fill")

                ForEach(incompletas) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(EPTheme.color(hex: item.displayColor))
                            .frame(width: 8, height: 8)
                        Text(item.unit.name)
                            .font(.caption.weight(.black))
                            .lineLimit(1)
                        Text("· \(item.curso)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var sugerencias: [Sugerencia] {
        var lista: [Sugerencia] = []
        if stats.incompletas > 0 {
            lista.append(Sugerencia(
                titulo: "Tienes \(stats.incompletas) unidad\(stats.incompletas == 1 ? "" : "es") sin fechas",
                texto: "Asígnales rangos de inicio y fin para que aparezcan en el timeline y calendario.",
                tint: .orange
            ))
        }
        if stats.cobertura < 50 && stats.total > 0 {
            lista.append(Sugerencia(
                titulo: "Cobertura baja (\(stats.cobertura)%)",
                texto: "Menos de la mitad de tus unidades tienen fechas asignadas. Considera planificarlas pronto.",
                tint: .red
            ))
        }
        if !proximas30.isEmpty {
            lista.append(Sugerencia(
                titulo: "\(proximas30.count) unidad\(proximas30.count == 1 ? "" : "es") inicia\(proximas30.count == 1 ? "" : "n") en 30 días",
                texto: "Revisa que tengas las clases planificadas y materiales listos.",
                tint: .blue
            ))
        }
        let enCurso = unidades.filter { UnitPlanningState.state(for: $0.unit) == .actual }
        if !enCurso.isEmpty {
            lista.append(Sugerencia(
                titulo: "\(enCurso.count) unidad\(enCurso.count == 1 ? "" : "es") en curso",
                texto: enCurso.map { "\($0.unit.name) (\($0.curso))" }.joined(separator: " · "),
                tint: .green
            ))
        }
        return lista
    }

    private var distribucionPorTipo: [ConteoTipo] {
        TipoUnidad.all.map { tipo in
            ConteoTipo(tipo: tipo, cantidad: unidades.filter { $0.unit.type == tipo }.count)
        }
    }

    private var proximas30: [ProximaUnidad] {
        unidades.compactMap { item -> ProximaUnidad? in
            guard let dias = PlanDateParser.diasDesdeHoy(hasta: item.unit.start),
                  dias >= 0, dias <= 30 else { return nil }
            return ProximaUnidad(unidad: item, dias: dias)
        }
        .sorted { $0.dias < $1.dias }
    }

    private func etiquetaInicio(_ item: ProximaUnidad) -> String {
        let cuando = item.dias == 0 ? "hoy" : (item.dias == 1 ? "en 1 día" : "en \(item.dias) días")
        return "\(item.unidad.curso) · empieza el \(item.unidad.unit.start) (\(cuando))"
    }

    private var incompletas: [UnidadConCurso] {
        unidades.filter { UnitPlanningState.state(for: $0.unit) == .incompleta }
    }

    private func coberturaColor(_ pct: Int) -> Color {
        pct >= 80 ? .green : pct >= 50 ? .orange : .red
    }
}
