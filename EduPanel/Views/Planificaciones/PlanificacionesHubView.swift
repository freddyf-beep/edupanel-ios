import SwiftUI
import Observation

struct PlanificacionesHubView: View {
    @State private var viewModel: PlanificacionesViewModel
    @State private var selectedVista: String = "timeline" // "timeline", "cursos", "calendario"
    @State private var searchQuery: String = ""
    @State private var selectedFiltroCurso: String? = nil
    
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

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
            .padding(.horizontal, 18)
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
        VStack {
            Spacer()
            ProgressView("Cargando planificaciones...")
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 48))
                .foregroundStyle(.pink)
            Text("Sin cursos configurados")
                .font(.headline)
            Text("Configura tu horario en Mi Perfil para habilitar la planificación por curso.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Hero Card
            heroCard
            
            // KPIs
            kpiGrid
            
            // Filters & Tabs
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Color(hex: "#F03E6E"))
                    Text("Vista e Informes")
                        .font(.subheadline.bold())
                    Spacer()
                }
                
                // Segments
                Picker("Vista", selection: $selectedVista) {
                    Text("Timeline").tag("timeline")
                    Text("Cursos").tag("cursos")
                    Text("Calendario").tag("calendario")
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            // Main selected view
            if selectedVista == "timeline" {
                TimelineView(planes: filteredPlanes, snapshot: viewModel.snapshot, activeSubject: viewModel.activeSubject)
            } else if selectedVista == "cursos" {
                CursosView(planes: filteredPlanes, snapshot: viewModel.snapshot, activeSubject: viewModel.activeSubject)
            } else {
                CalendarioView(planes: filteredPlanes, activeSubject: viewModel.activeSubject)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.activeSubject.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(1.2)
                    
                    Text("Unidades de Aprendizaje")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Text("Planifica, gestiona y exporta la cobertura curricular de tus cursos activos en tiempo real.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
            
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar unidad o curso...", text: $searchQuery)
                    .font(.footnote)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: "#F03E6E"), .pink, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var kpiGrid: some View {
        let stats = calculateStats()
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        
        return LazyVGrid(columns: columns, spacing: 10) {
            kpiCard(title: "Unidades totales", value: "\(stats.totalUnidades)", subtitle: "\(stats.totalHoras) hrs registradas", color: .blue)
            kpiCard(title: "Cobertura fechas", value: "\(stats.cobertura)%", subtitle: "de unidades con rango", color: .green)
            kpiCard(title: "Cursos activos", value: "\(stats.totalCursos)", subtitle: "en tu horario", color: .purple)
            kpiCard(title: "Unidades sin fecha", value: "\(stats.sinFechas)", subtitle: "pendientes de programar", color: .orange)
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Color(.label))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Calculations & Filtering

    private var filteredPlanes: [PlanificacionCurso] {
        guard let snapshot = viewModel.snapshot else { return [] }
        let subject = viewModel.activeSubject
        
        // Ensure every active course from timetable is represented
        let activeCursos = snapshot.courses
        var merged: [PlanificacionCurso] = []
        
        for curso in activeCursos {
            if let existing = viewModel.planes.first(where: { $0.curso == curso }) {
                merged.append(existing)
            } else {
                // Return empty placeholder plan
                merged.append(PlanificacionCurso(curso: curso, asignatura: subject, units: []))
            }
        }
        
        // Filter by search query
        if !searchQuery.isEmpty {
            merged = merged.filter { plan in
                plan.curso.localizedCaseInsensitiveContains(searchQuery) ||
                plan.units.contains { $0.name.localizedCaseInsensitiveContains(searchQuery) }
            }
        }
        
        return merged
    }

    private struct Stats {
        var totalUnidades = 0
        var totalHoras = 0
        var cobertura = 0
        var sinFechas = 0
        var totalCursos = 0
    }

    private func calculateStats() -> Stats {
        let list = filteredPlanes
        var stats = Stats()
        stats.totalCursos = list.count
        
        var unitsCount = 0
        var unitsWithDates = 0
        
        for plan in list {
            unitsCount += plan.units.count
            for unit in plan.units {
                stats.totalHoras += unit.hours
                if unit.hasDates {
                    unitsWithDates += 1
                } else {
                    stats.sinFechas += 1
                }
            }
        }
        
        stats.totalUnidades = unitsCount
        stats.cobertura = unitsCount > 0 ? Int(Double(unitsWithDates) / Double(unitsCount) * 100) : 0
        return stats
    }
}

// MARK: - Subviews: Timeline
private struct TimelineView: View {
    let planes: [PlanificacionCurso]
    let snapshot: DashboardSnapshot?
    let activeSubject: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundStyle(.blue)
                Text("Gantt de Planificación Anual")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(.bottom, 4)
            
            if planes.isEmpty {
                Text("No hay cursos con unidades planificadas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 16) {
                    // Month scale headers (Mar to Dec - 10 columns)
                    HStack(spacing: 0) {
                        Spacer().frame(width: 84)
                        let months = ["Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
                        ForEach(months, id: \.self) { month in
                            Text(month)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Row per course
                    ForEach(planes, id: \.curso) { plan in
                        HStack(spacing: 8) {
                            // Course tag
                            NavigationLink(value: AppRoute.coursePlanificaciones(plan.curso)) {
                                Text(plan.curso)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundStyle(Color(hex: "#F03E6E"))
                            }
                            .buttonStyle(.plain)
                            
                            // Visual timeline area
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Base strip
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(.systemGray6))
                                    
                                    // Highlighted unit blocks
                                    ForEach(plan.units) { unit in
                                        if unit.hasDates {
                                            let startRatio = offsetPercentage(for: unit.start)
                                            let endRatio = offsetPercentage(for: unit.end)
                                            let width = max(geometry.size.width * 0.08, geometry.size.width * (endRatio - startRatio))
                                            let offset = geometry.size.width * startRatio
                                            
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(Color(hex: unit.color))
                                                .frame(width: width, height: 18)
                                                .offset(x: offset)
                                                .overlay(
                                                    Text(unit.name)
                                                        .font(.system(size: 8, weight: .black))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                        .padding(.horizontal, 3),
                                                    alignment: .center
                                                )
                                        }
                                    }
                                }
                                .frame(height: 22)
                                .offset(y: 2)
                            }
                            .frame(height: 26)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // Calculates fraction of time between March 1 and Dec 31
    private func offsetPercentage(for dateString: String) -> CGFloat {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let cleaned = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = formatter.date(from: cleaned) else { return 0 }
        
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        
        var componentsStart = DateComponents()
        componentsStart.year = year
        componentsStart.month = 3 // March
        componentsStart.day = 1
        guard let startYear = calendar.date(from: componentsStart) else { return 0 }
        
        var componentsEnd = DateComponents()
        componentsEnd.year = year
        componentsEnd.month = 12 // December
        componentsEnd.day = 31
        guard let endYear = calendar.date(from: componentsEnd) else { return 0 }
        
        let totalSeconds = endYear.timeIntervalSince(startYear)
        let elapsedSeconds = date.timeIntervalSince(startYear)
        
        guard totalSeconds > 0 else { return 0 }
        return CGFloat(max(0.0, min(1.0, elapsedSeconds / totalSeconds)))
    }
}

// MARK: - Subviews: Cursos
private struct CursosView: View {
    let planes: [PlanificacionCurso]
    let snapshot: DashboardSnapshot?
    let activeSubject: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(.purple)
                Text("Avance por Curso")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(.bottom, 4)
            
            let columns = [
                GridItem(.flexible(), spacing: 12)
            ]
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(planes, id: \.curso) { plan in
                    let coverage = calculateCoverage(for: plan)
                    let courseColorHex = snapshot?.horario.first(where: { $0.resumen == plan.curso })?.colorHex ?? "#F03E6E"
                    
                    NavigationLink(value: AppRoute.coursePlanificaciones(plan.curso)) {
                        HStack(spacing: 12) {
                            // Course dot
                            Circle()
                                .fill(Color(hex: courseColorHex))
                                .frame(width: 12, height: 12)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.curso)
                                    .font(.headline)
                                    .foregroundStyle(Color(.label))
                                
                                Text("\(plan.units.count) unidades · \(plan.units.reduce(0) { $0 + $1.hours }) hrs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Coverage progress
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(coverage)%")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(coverage >= 80 ? .green : coverage >= 50 ? .orange : .red)
                                
                                ProgressView(value: Double(coverage) / 100.0)
                                    .frame(width: 60)
                                    .tint(coverage >= 80 ? .green : coverage >= 50 ? .orange : .red)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func calculateCoverage(for plan: PlanificacionCurso) -> Int {
        guard !plan.units.isEmpty else { return 0 }
        let withDates = plan.units.filter(\.hasDates).count
        return Int(Double(withDates) / Double(plan.units.count) * 100)
    }
}

// MARK: - Subviews: Calendario (Milestones)
private struct CalendarioView: View {
    let planes: [PlanificacionCurso]
    let activeSubject: String
    @State private var selectedMonthOffset = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Month switcher
            let activeMonthDate = getMonthDate()
            HStack {
                Button {
                    selectedMonthOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .padding(8)
                        .background(Color(.systemGray6), in: Circle())
                }
                
                Spacer()
                
                Text(monthYearString(for: activeMonthDate))
                    .font(.headline)
                
                Spacer()
                
                Button {
                    selectedMonthOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                        .padding(8)
                        .background(Color(.systemGray6), in: Circle())
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            
            // Milestones list for the selected month
            let milestones = getMilestones(for: activeMonthDate)
            if milestones.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No hay hitos este mes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(milestones, id: \.id) { milestone in
                        HStack(spacing: 12) {
                            VStack {
                                Text("\(milestone.day)")
                                    .font(.title3.bold())
                                Text(milestone.weekday)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 36)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: milestone.isStart ? "arrow.right.circle.fill" : "stop.circle.fill")
                                        .foregroundStyle(Color(hex: milestone.unitColor))
                                        .font(.caption)
                                    
                                    Text(milestone.isStart ? "Inicio de Unidad" : "Cierre de Unidad")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text(milestone.unitName)
                                    .font(.subheadline.bold())
                                Text(milestone.curso)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func getMonthDate() -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: selectedMonthOffset, to: Date()) ?? Date()
    }
    
    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
    
    private struct Milestone {
        let id: String
        let day: Int
        let weekday: String
        let isStart: Bool
        let unitName: String
        let unitColor: String
        let curso: String
    }
    
    private func getMilestones(for monthDate: Date) -> [Milestone] {
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: monthDate)
        let targetYear = calendar.component(.year, from: monthDate)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var list: [Milestone] = []
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "es_CL")
        weekdayFormatter.dateFormat = "EEE"
        
        for plan in planes {
            for unit in plan.units {
                // Check start date
                if unit.hasDates {
                    if let startD = formatter.date(from: unit.start) {
                        let m = calendar.component(.month, from: startD)
                        let y = calendar.component(.year, from: startD)
                        if m == targetMonth && y == targetYear {
                            let day = calendar.component(.day, from: startD)
                            let w = weekdayFormatter.string(from: startD).uppercased().replacingOccurrences(of: ".", with: "")
                            list.append(Milestone(
                                id: "\(plan.curso)-\(unit.id)-start",
                                day: day,
                                weekday: w,
                                isStart: true,
                                unitName: unit.name,
                                unitColor: unit.color,
                                curso: plan.curso
                            ))
                        }
                    }
                    
                    // Check end date
                    if let endD = formatter.date(from: unit.end) {
                        let m = calendar.component(.month, from: endD)
                        let y = calendar.component(.year, from: endD)
                        if m == targetMonth && y == targetYear {
                            let day = calendar.component(.day, from: endD)
                            let w = weekdayFormatter.string(from: endD).uppercased().replacingOccurrences(of: ".", with: "")
                            list.append(Milestone(
                                id: "\(plan.curso)-\(unit.id)-end",
                                day: day,
                                weekday: w,
                                isStart: false,
                                unitName: unit.name,
                                unitColor: unit.color,
                                curso: plan.curso
                            ))
                        }
                    }
                }
            }
        }
        
        return list.sorted { $0.day < $1.day }
    }
}

// MARK: - Color Hex Helpers
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
