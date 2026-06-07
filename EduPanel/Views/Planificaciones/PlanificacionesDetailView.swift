import SwiftUI

struct PlanificacionesDetailView: View {
    let curso: String
    let asignatura: String?
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    @State private var units: [UnidadPlan] = []
    @State private var cronogramasByUnit: [String: CronogramaUnidadData] = [:]
    @State private var isLoading = false
    @State private var activeSubject = "M\u{00FA}sica"
    @State private var saveStatus = ""

    @State private var newUnitName = ""
    @State private var newUnitType = "tradicional"

    @State private var renamingUnitId: Int? = nil
    @State private var renamingName = ""

    @State private var unitToDelete: UnidadPlan? = nil
    @State private var showingDeleteAlert = false

    private let colors = ["#F59E0B", "#3B82F6", "#EF4444", "#22C55E", "#8B5CF6", "#F03E6E", "#06B6D4", "#D97706"]

    init(curso: String, asignatura: String? = nil, dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.curso = curso
        self.asignatura = asignatura
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        let cleanSubject = asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanSubject.isEmpty {
            self._activeSubject = State(initialValue: cleanSubject)
        }
    }

    var body: some View {
        Group {
            if isLoading && units.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando planificación...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailContent
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(curso)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !saveStatus.isEmpty {
                    EPStatusPill(
                        text: saveStatus,
                        icon: saveStatus.contains("Error") ? "xmark.octagon.fill" : "checkmark.circle.fill",
                        tint: saveStatus.contains("Error") ? .red : .green
                    )
                }
            }
        }
        .task {
            await loadData()
        }
        .alert("¿Eliminar unidad?", isPresented: $showingDeleteAlert, presenting: unitToDelete) { unit in
            Button("Eliminar", role: .destructive) {
                Task { await performDelete(unit: unit) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { unit in
            Text("Esto eliminará la unidad \"\(unit.name)\", su cronograma y todas sus clases planificadas.")
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                inlineCreationCard
                unitsSection
                sidebarReplica
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .refreshable {
            await loadData()
        }
    }

    private var headerCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(activeSubject.uppercased()) · \(curso.uppercased())")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(EPTheme.primary)
                        Text("Planificación por curso")
                            .font(.title3.weight(.black))
                        Text("\(units.count) unidades · \(totalHours) horas · \(overallCoverage)% cobertura")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    EPStatusPill(text: planningStateLabel, icon: "circle.fill", tint: planningStateTint)
                }

                ProgressView(value: Double(overallCoverage) / 100.0)
                    .tint(planningStateTint)

                HStack(spacing: 8) {
                    EPPlaceholderActionButton(title: "Drive", icon: "externaldrive.fill", message: "Backup Drive visible como en la web. La conexión nativa se implementará en una entrega posterior.")
                    EPPlaceholderActionButton(title: "Exportar", icon: "square.and.arrow.up", message: "Exportaciones DOCX/PDF quedan preparadas como placeholder nativo.")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var inlineCreationCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Crear unidad inline", subtitle: "Mismo flujo compacto de la web.", icon: "plus.square.fill")

                VStack(spacing: 10) {
                    TextField("Nombre de la unidad...", text: $newUnitName)
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 10) {
                        Picker("Tipo", selection: $newUnitType) {
                            Text("Tradicional").tag("tradicional")
                            Text("Invertida").tag("invertida")
                            Text("Proyecto").tag("proyecto")
                            Text("Unidad 0").tag("unidad0")
                        }
                        .pickerStyle(.menu)
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            addUnit()
                        } label: {
                            Label("Agregar", systemImage: "plus")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(newUnitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EPSectionHeader(title: "Unidades programadas", subtitle: "Filas compactas con acciones Ver, Crono y Clases.", icon: "list.bullet.rectangle")

            if units.isEmpty {
                EPWebCard {
                    VStack(spacing: 9) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("No hay unidades creadas")
                            .font(.subheadline.weight(.black))
                        Text("Usa el formulario superior para añadir tu primera unidad didáctica.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                        unitRow(unit: unit, index: index)
                    }
                }
            }
        }
    }

    private func unitRow(unit: UnidadPlan, index: Int) -> some View {
        let coverage = UnitCoverage.coverage(for: unit, asignatura: activeSubject, course: curso, cronogramasByUnit: cronogramasByUnit)
        let state = UnitPlanningState.state(for: unit)
        let routeId = UnitRouteID.routeId(for: unit, asignatura: activeSubject, course: curso, cronogramasByUnit: cronogramasByUnit)

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(EPTheme.color(hex: unit.color), in: Circle())
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 8) {
                        if renamingUnitId == unit.id {
                            TextField("Nombre de la unidad", text: $renamingName)
                                .textFieldStyle(.plain)
                                .font(.headline.weight(.black))
                                .padding(9)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onSubmit {
                                    finishRenaming(unitId: unit.id)
                                }
                        } else {
                            Text(unit.name)
                                .font(.headline.weight(.black))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .onTapGesture(count: 2) {
                                    renamingUnitId = unit.id
                                    renamingName = unit.name
                                }
                        }

                        HStack(spacing: 6) {
                            EPStatusPill(text: typeLabel(unit.type), icon: typeIcon(unit.type), tint: EPTheme.color(hex: unit.color))
                            EPStatusPill(text: state.label, icon: "circle.fill", tint: state.tint)
                        }

                        Text(unit.hasDates ? "\(PlanDateParser.short(unit.start)) al \(PlanDateParser.short(unit.end)) · \(unit.hours) horas" : "Sin fechas · \(unit.hours) horas")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        unitToDelete = unit
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.footnote.weight(.black))
                            .foregroundStyle(.red)
                            .padding(9)
                            .background(.red.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Cobertura \(coverage.assigned)/\(coverage.total)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(coverage.percent)%")
                            .font(.caption.weight(.black))
                            .foregroundStyle(coverage.percent >= 80 ? .green : coverage.percent >= 45 ? .orange : EPTheme.primary)
                    }
                    ProgressView(value: Double(coverage.percent) / 100.0)
                        .tint(coverage.percent >= 80 ? .green : coverage.percent >= 45 ? .orange : EPTheme.primary)
                }

                HStack(spacing: 8) {
                    NavigationLink(value: AppRoute.verUnidad(curso: curso, asignatura: activeSubject, unidadId: routeId, unidadNombre: unit.name, initialTab: "unidad")) {
                        actionLabel("Ver", icon: "text.alignleft")
                    }
                    NavigationLink(value: AppRoute.verUnidad(curso: curso, asignatura: activeSubject, unidadId: routeId, unidadNombre: unit.name, initialTab: "cronograma")) {
                        actionLabel("Crono", icon: "calendar")
                    }
                    NavigationLink(value: AppRoute.verUnidad(curso: curso, asignatura: activeSubject, unidadId: routeId, unidadNombre: unit.name, initialTab: "clases")) {
                        actionLabel("Clases", icon: "book.closed")
                    }

                    if renamingUnitId == unit.id {
                        Button {
                            finishRenaming(unitId: unit.id)
                        } label: {
                            actionLabel("OK", icon: "checkmark")
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(.plain)
                .foregroundStyle(EPTheme.primary)
            }
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.black))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.systemGray6), in: Capsule())
    }

    private var sidebarReplica: some View {
        VStack(alignment: .leading, spacing: 12) {
            EPWebCard {
                VStack(alignment: .leading, spacing: 12) {
                    EPSectionHeader(title: "Próximas clases", subtitle: "Resumen operativo del curso.", icon: "calendar.badge.clock")
                    let rows = upcomingRows
                    if rows.isEmpty {
                        Text("No hay próximas clases programadas en cronogramas.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows.prefix(5), id: \.id) { row in
                            HStack(spacing: 10) {
                                Text(row.badge)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(EPTheme.color(hex: row.color), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title)
                                        .font(.footnote.weight(.black))
                                        .lineLimit(1)
                                    Text(row.subtitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }

            EPWebCard {
                VStack(alignment: .leading, spacing: 10) {
                    EPSectionHeader(title: "Resumen", subtitle: nil, icon: "chart.pie.fill")
                    summaryLine("Unidades", "\(units.count)")
                    summaryLine("Horas", "\(totalHours)")
                    summaryLine("Con fechas", "\(units.filter(\.hasDates).count)")
                    summaryLine("Sin fechas", "\(units.filter { !$0.hasDates }.count)")
                    summaryLine("Cobertura", "\(overallCoverage)%")
                }
            }

            EPWebCard {
                VStack(alignment: .leading, spacing: 10) {
                    EPSectionHeader(title: "Exportar", subtitle: "Placeholder nativo para mantener la estructura web.", icon: "square.and.arrow.up")
                    EPPlaceholderActionButton(title: "Informe DOCX", icon: "doc.richtext", message: "La exportación DOCX se conectará cuando migremos el servicio web.")
                    EPPlaceholderActionButton(title: "Resumen PDF", icon: "doc.text", message: "La exportación PDF se conectará en una entrega posterior.")
                }
            }
        }
    }

    private func summaryLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote.weight(.black))
        }
    }

    private struct UpcomingRow: Identifiable {
        let id: String
        let badge: String
        let title: String
        let subtitle: String
        let color: String
        let sortDate: Date
    }

    private var upcomingRows: [UpcomingRow] {
        let today = Calendar.current.startOfDay(for: Date())
        var rows: [UpcomingRow] = []

        for unit in units {
            let key = PlanificacionRepository.cronogramaKey(asignatura: activeSubject, curso: curso, unidadId: String(unit.id))
            guard let crono = cronogramasByUnit[key] else { continue }

            for clase in crono.clases {
                guard let date = PlanDateParser.date(from: clase.fecha), date >= today else { continue }
                rows.append(UpcomingRow(
                    id: "\(unit.id)-\(clase.numero)",
                    badge: "C\(clase.numero)",
                    title: unit.name,
                    subtitle: "\(PlanDateParser.short(clase.fecha)) · \(clase.oaIds.isEmpty ? "sin OA" : clase.oaIds.joined(separator: ", "))",
                    color: unit.color,
                    sortDate: date
                ))
            }
        }

        return rows.sorted { $0.sortDate < $1.sortDate }
    }

    private var totalHours: Int {
        units.reduce(0) { $0 + $1.hours }
    }

    private var overallCoverage: Int {
        var assigned = 0
        var total = 0
        for unit in units {
            let coverage = UnitCoverage.coverage(for: unit, asignatura: activeSubject, course: curso, cronogramasByUnit: cronogramasByUnit)
            assigned += coverage.assigned
            total += coverage.total
        }
        return total > 0 ? Int((Double(assigned) / Double(total)) * 100) : 0
    }

    private var planningStateLabel: String {
        if units.isEmpty { return "Sin unidades" }
        if units.contains(where: { UnitPlanningState.state(for: $0) == .enCurso }) { return "En curso" }
        if units.contains(where: { UnitPlanningState.state(for: $0) == .proxima }) { return "Próximas" }
        if units.allSatisfy({ UnitPlanningState.state(for: $0) == .completada }) { return "Completada" }
        return "Por programar"
    }

    private var planningStateTint: Color {
        switch planningStateLabel {
        case "En curso": return .green
        case "Próximas": return .purple
        case "Completada": return .blue
        default: return .orange
        }
    }

    private func addUnit() {
        let name = newUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let nextIndex = units.count + 1
        let nextId = (units.map(\.id).max() ?? 0) + 1
        let color = colors[units.count % colors.count]

        units.append(UnidadPlan(
            id: nextId,
            name: name,
            color: color,
            hours: 8,
            start: "",
            end: "",
            type: newUnitType,
            unidadCurricularId: "unidad_\(nextIndex)"
        ))
        newUnitName = ""

        Task { await savePlan() }
    }

    private func savePlan() async {
        saveStatus = "Guardando..."
        do {
            try await planificacionRepository.guardarPlanCurso(asignatura: activeSubject, curso: curso, units: units)
            saveStatus = "Guardado"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if saveStatus == "Guardado" { saveStatus = "" }
        } catch {
            saveStatus = "Error"
        }
    }

    private func performDelete(unit: UnidadPlan) async {
        saveStatus = "Eliminando..."
        do {
            try await planificacionRepository.eliminarUnidadCompleta(asignatura: activeSubject, curso: curso, unidadId: String(unit.id))
            units.removeAll { $0.id == unit.id }
            cronogramasByUnit.removeValue(forKey: PlanificacionRepository.cronogramaKey(asignatura: activeSubject, curso: curso, unidadId: String(unit.id)))
            cronogramasByUnit.removeValue(forKey: PlanificacionRepository.cronogramaKey(curso: curso, unidadId: String(unit.id)))
            try await planificacionRepository.guardarPlanCurso(asignatura: activeSubject, curso: curso, units: units)
            saveStatus = "Guardado"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            saveStatus = ""
        } catch {
            saveStatus = "Error"
        }
    }

    private func finishRenaming(unitId: Int) {
        let name = renamingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let index = units.firstIndex(where: { $0.id == unitId }) {
            units[index].name = name
            Task { await savePlan() }
        }
        renamingUnitId = nil
        renamingName = ""
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snap = try await dashboardRepository.fetchDashboard()
            let providedSubject = asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            activeSubject = providedSubject.isEmpty ? subject(from: snap) : providedSubject

            if let plan = try await planificacionRepository.cargarPlanCurso(asignatura: activeSubject, curso: curso) {
                units = plan.units
            } else {
                units = []
            }

            let plan = PlanificacionCurso(curso: curso, asignatura: activeSubject, units: units)
            cronogramasByUnit = await planificacionRepository.cargarCronogramas(asignatura: activeSubject, planes: [plan])
            units = units.map { unit in
                guard !unit.hasDates else { return unit }
                let key = PlanificacionRepository.cronogramaKey(asignatura: activeSubject, curso: curso, unidadId: String(unit.id))
                guard let range = dateRange(from: cronogramasByUnit[key]?.clases ?? []) else { return unit }
                var next = unit
                next.start = range.start
                next.end = range.end
                return next
            }
        } catch {
            units = []
            cronogramasByUnit = [:]
            saveStatus = "Error al cargar"
        }
    }

    private func subject(from snapshot: DashboardSnapshot) -> String {
        if let subject = snapshot.preferences.asignaturasHabilitadas
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return subject
        }

        let specialty = snapshot.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines)
        return specialty.isEmpty ? "M\u{00FA}sica" : specialty
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "unidad0": return "Unidad 0"
        case "invertida": return "Invertida"
        case "proyecto": return "Proyecto"
        case "tradicional": return "Tradicional"
        default: return "Unidad"
        }
    }

    private func typeIcon(_ type: String) -> String {
        switch type {
        case "unidad0": return "0.circle.fill"
        case "invertida": return "arrow.triangle.2.circlepath"
        case "proyecto": return "target"
        default: return "book.closed.fill"
        }
    }

    private func dateRange(from clases: [ClaseCronograma]) -> (start: String, end: String)? {
        let dates = clases.compactMap { parseDDMMYYYY($0.fecha) }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        return (toISODate(first), toISODate(last))
    }

    private func parseDDMMYYYY(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func toISODate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
