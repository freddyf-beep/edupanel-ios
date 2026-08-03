import SwiftUI

struct PlanificacionesDetailView: View {
    let curso: String
    let asignatura: String?
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository
    private let curriculoRepository = CurriculoRepository()

    @State private var units: [UnidadPlan] = []
    @State private var cronogramasByUnit: [String: CronogramaUnidadData] = [:]
    @State private var curriculumUnits: [UnidadCurricular] = []
    @State private var availableCurriculumLevels: [String] = []
    @State private var curriculumLevel: String?
    @State private var curriculumMessage: String?
    @State private var isLoading = false
    @State private var activeSubject = "M\u{00FA}sica"
    @State private var saveStatus = ""
    @State private var driveConnected = false
    @State private var presentedSheet: PresentedSheet?

    @State private var renamingUnitId: Int? = nil
    @State private var renamingName = ""

    @State private var unitToDelete: UnidadPlan? = nil
    @State private var showingDeleteAlert = false

    private static let maxUnidades = 12

    private enum PresentedSheet: String, Identifiable {
        case newUnit

        var id: String { rawValue }
    }

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
                    Text("Cargando planificación…")
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !saveStatus.isEmpty {
                    EPStatusPill(
                        text: saveStatus,
                        icon: saveStatus.contains("Error") ? "xmark.octagon.fill" : "checkmark.circle.fill",
                        tint: saveStatus.contains("Error") ? .red : .green
                    )
                }

                Button {
                    presentedSheet = .newUnit
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.black))
                        .foregroundStyle(EPTheme.primary)
                        .frame(width: 34, height: 34)
                        .background(EPTheme.primary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(units.count >= Self.maxUnidades)
                .opacity(units.count >= Self.maxUnidades ? 0.4 : 1)
                .accessibilityLabel("Crear nueva unidad")
                .accessibilityHint("Abre el formulario para agregar una unidad al curso")
            }
        }
        .task {
            await loadData()
        }
        .sensoryFeedback(.success, trigger: saveStatus) { _, newValue in
            newValue == "Guardado"
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newUnit:
                NewUnitSheet(curriculumUnits: curriculumUnits) { name, type, curriculumUnitID in
                    addUnit(name: name, type: type, curriculumUnitID: curriculumUnitID)
                }
                .presentationDetents([.height(curriculumUnits.isEmpty ? 390 : 500), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("¿Eliminar unidad?", isPresented: $showingDeleteAlert, presenting: unitToDelete) { unit in
            Button("Sí, borrar", role: .destructive) {
                Task { await performDelete(unit: unit) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { unit in
            Text("Se eliminará la planificación, el cronograma y todas las clases planificadas de \"\(unit.name)\". No se puede deshacer.")
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                listaUnidades
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .tabBarPageBottomPadding()
        }
        .refreshable {
            await loadData(forceRefresh: true)
        }
    }

    // MARK: - Header

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
                        Text("\(units.count) unidades · \(totalHoras) horas · \(coberturaGeneral)% cobertura")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    EPStatusPill(text: estadoGeneral.label, icon: estadoGeneral.icon, tint: estadoGeneral.tint)
                }

                ProgressView(value: Double(coberturaGeneral) / 100.0)
                    .tint(estadoGeneral.tint)

                HStack {
                    EPStatusPill(
                        text: driveConnected ? "Drive conectado" : "Drive no conectado",
                        icon: driveConnected ? "checkmark.circle.fill" : "xmark.circle.fill",
                        tint: driveConnected ? .green : .red
                    )
                    Spacer(minLength: 0)
                }

                if !availableCurriculumLevels.isEmpty {
                    Menu {
                        ForEach(availableCurriculumLevels, id: \.self) { level in
                            Button {
                                selectCurriculumLevel(level)
                            } label: {
                                if level == curriculumLevel {
                                    Label(level, systemImage: "checkmark")
                                } else {
                                    Text(level)
                                }
                            }
                        }
                    } label: {
                        Label(
                            curriculumLevel.map { "Bases curriculares: \($0)" } ?? "Elegir nivel curricular",
                            systemImage: "link"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(curriculumLevel == nil ? .orange : EPTheme.primary)
                    }
                } else if let curriculumLevel {
                    Label(
                        "Bases curriculares: \(curriculumLevel)",
                        systemImage: "link"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EPTheme.primary)
                } else {
                    Label(
                        "Define el nivel curricular del curso para vincular sus unidades.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Lista de unidades

    private var listaUnidades: some View {
        VStack(alignment: .leading, spacing: 12) {
            if units.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "square.stack.3d.up.slash",
                        title: "No hay unidades en \(curso) todavía",
                        message: "Toca el botón + de arriba para crear la primera."
                    )
                }
            } else {
                ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                    unitRow(unit: unit, index: index)
                }
            }
        }
    }

    private func unitRow(unit: UnidadPlan, index: Int) -> some View {
        let coverage = UnitCoverage.coverage(for: unit, asignatura: activeSubject, course: curso, cronogramasByUnit: cronogramasByUnit)
        let state = UnitPlanningState.state(for: unit)
        let routeId = UnitRouteID.routeId(for: unit, asignatura: activeSubject, course: curso, cronogramasByUnit: cronogramasByUnit)

        return EPWebCard(padding: 13) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(EPTheme.color(hex: unit.color), in: Circle())
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 7) {
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
                            EPStatusPill(text: TipoUnidad.label(unit.type), icon: TipoUnidad.icon(unit.type), tint: TipoUnidad.tint(unit.type))
                            EPStatusPill(text: state.label, icon: state.icon, tint: state.tint)
                        }

                        Text(unit.hasDates
                             ? "\(PlanDateParser.short(unit.start)) al \(PlanDateParser.short(unit.end)) · \(unit.hours) horas"
                             : "Sin fechas · \(unit.hours) horas")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        curriculumPicker(for: unit)
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

                if coverage.total > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Clases con fecha \(coverage.assigned)/\(coverage.total)")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(coverage.percent)%")
                                .font(.caption.weight(.black))
                                .foregroundStyle(barraCobertura(coverage.percent))
                        }
                        ProgressView(value: Double(coverage.percent) / 100.0)
                            .tint(barraCobertura(coverage.percent))
                    }
                }

                HStack(spacing: 8) {
                    NavigationLink(value: AppRoute.verUnidad(curso: curso, asignatura: activeSubject, unidadId: routeId, unidadNombre: unit.name, initialTab: "unidad")) {
                        actionLabel("Ver", icon: "book.closed.fill", destacado: true)
                    }
                    NavigationLink(value: AppRoute.verUnidad(curso: curso, asignatura: activeSubject, unidadId: routeId, unidadNombre: unit.name, initialTab: "cronograma")) {
                        actionLabel("Crono", icon: "calendar")
                    }
                    NavigationLink(value: AppRoute.verUnidad(curso: curso, asignatura: activeSubject, unidadId: routeId, unidadNombre: unit.name, initialTab: "clases")) {
                        actionLabel("Clases", icon: "text.book.closed")
                    }

                    if renamingUnitId == unit.id {
                        Button {
                            finishRenaming(unitId: unit.id)
                        } label: {
                            actionLabel("OK", icon: "checkmark", destacado: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionLabel(_ title: String, icon: String, destacado: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(destacado ? EPTheme.primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(destacado ? EPTheme.primary.opacity(0.1) : Color(.systemGray6), in: Capsule())
            .overlay {
                if destacado {
                    Capsule().stroke(EPTheme.primary.opacity(0.4), lineWidth: 1)
                }
            }
    }

    @ViewBuilder
    private func curriculumPicker(for unit: UnidadPlan) -> some View {
        if !curriculumUnits.isEmpty {
            Menu {
                Button {
                    updateCurriculumLink(unitID: unit.id, curriculumUnitID: nil)
                } label: {
                    Label("Sin vincular", systemImage: unit.unidadCurricularId == nil ? "checkmark" : "link.badge.plus")
                }

                ForEach(curriculumUnits) { curriculumUnit in
                    Button {
                        updateCurriculumLink(unitID: unit.id, curriculumUnitID: curriculumUnit.id)
                    } label: {
                        if unit.unidadCurricularId == curriculumUnit.id {
                            Label(curriculumUnit.displayName, systemImage: "checkmark")
                        } else {
                            Text(curriculumUnit.displayName)
                        }
                    }
                }
            } label: {
                Label(
                    curriculumLabel(for: unit),
                    systemImage: unit.unidadCurricularId == nil ? "link.badge.plus" : "link.circle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(unit.unidadCurricularId == nil ? .orange : EPTheme.primary)
                .lineLimit(2)
            }
            .accessibilityLabel("Unidad curricular vinculada")
            .accessibilityHint("Permite elegir la unidad oficial correspondiente")
        } else if let curriculumMessage {
            Label(curriculumMessage, systemImage: "exclamationmark.triangle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    private func barraCobertura(_ pct: Int) -> Color {
        pct == 100 ? .green : pct >= 50 ? .orange : pct > 0 ? .red : .gray
    }

    // MARK: - Datos derivados

    private var totalHoras: Int {
        units.reduce(0) { $0 + $1.hours }
    }

    private var coberturaGeneral: Int {
        var assigned = 0
        var total = 0
        for unit in units {
            let coverage = UnitCoverage.coverage(for: unit, asignatura: activeSubject, course: curso, cronogramasByUnit: cronogramasByUnit)
            assigned += coverage.assigned
            total += coverage.total
        }
        return total > 0 ? Int(round(Double(assigned) / Double(total) * 100)) : 0
    }

    private var estadoGeneral: (label: String, icon: String, tint: Color) {
        guard !units.isEmpty else { return ("Sin unidades", "tray", .gray) }
        let estados = units.map { UnitPlanningState.state(for: $0) }
        if estados.contains(.actual) { return ("En curso", "waveform.path.ecg", .green) }
        if estados.contains(.futura) { return ("Próximas", "clock.fill", .blue) }
        if estados.allSatisfy({ $0 == .pasada }) { return ("Cerrada", "checkmark", .gray) }
        return ("Sin fechas", "exclamationmark.triangle.fill", .orange)
    }

    // MARK: - Acciones

    private func addUnit(name rawName: String, type: String, curriculumUnitID: String?) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, units.count < Self.maxUnidades else { return }

        let nextId = (units.map(\.id).max() ?? 0) + 1

        units.append(UnidadPlan(
            id: nextId,
            name: name,
            color: CursoPalette.color(at: units.count),
            hours: 8,
            start: "",
            end: "",
            type: type,
            unidadCurricularId: curriculumUnitID
        ))

        Task { await savePlan() }
    }

    private func savePlan() async {
        saveStatus = "Guardando…"
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
        saveStatus = "Eliminando…"
        do {
            try await planificacionRepository.eliminarUnidadCompleta(
                asignatura: activeSubject,
                curso: curso,
                unidadIds: PlanificacionRepository.unidadIdCandidates(unit: unit)
            )
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

    private func updateCurriculumLink(unitID: Int, curriculumUnitID: String?) {
        guard let index = units.firstIndex(where: { $0.id == unitID }) else { return }
        units[index].unidadCurricularId = curriculumUnitID
        Task { await savePlan() }
    }

    private func curriculumLabel(for unit: UnidadPlan) -> String {
        guard let id = unit.unidadCurricularId else { return "Vincular con currículum" }
        return curriculumUnits.first(where: { $0.id == id })?.displayName ?? "Vinculada a \(id)"
    }

    private func selectCurriculumLevel(_ level: String) {
        curriculumLevel = level
        Task {
            do {
                try await dashboardRepository.saveSubjectLevelMapping(
                    course: curso,
                    subject: activeSubject,
                    level: level
                )
                await loadCurriculum(level: level)
            } catch {
                curriculumMessage = "No se pudo guardar el nivel curricular."
            }
        }
    }

    private func loadCurriculum(level: String) async {
        do {
            curriculumUnits = try await curriculoRepository.getUnidades(
                asignatura: activeSubject,
                nivel: level
            )
            curriculumMessage = curriculumUnits.isEmpty
                ? "No hay unidades curriculares publicadas para este nivel."
                : nil
        } catch {
            curriculumUnits = []
            curriculumMessage = "No se pudo cargar el currículum. Reintenta más tarde."
        }
    }

    // MARK: - Carga

    private func loadData(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snap = try await dashboardRepository.fetchDashboard(forceRefresh: forceRefresh)
            driveConnected = snap.preferences.googleDriveConnected
            let providedSubject = asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            activeSubject = providedSubject.isEmpty ? subject(from: snap) : providedSubject
            let catalogLevel = snap.course(id: nil, named: curso)?
                .level?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            curriculumLevel = CurriculoNivel.resolver(
                curso: curso,
                asignatura: activeSubject,
                catalogLevel: catalogLevel,
                mapping: snap.nivelMapping,
                subjectMapping: snap.subjectLevelMapping
            )

            do {
                availableCurriculumLevels = try await curriculoRepository.getNivelesDisponibles(
                    asignatura: activeSubject
                )
            } catch {
                availableCurriculumLevels = []
            }

            if let curriculumLevel {
                await loadCurriculum(level: curriculumLevel)
            } else {
                curriculumUnits = []
                curriculumMessage = "Falta asociar un nivel curricular al curso."
            }

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
            saveStatus = "Error al cargar"
        }
    }

    private func subject(from snapshot: DashboardSnapshot) -> String {
        if let subject = snapshot.course(id: nil, named: curso)?.subjects.first?.label {
            return subject
        }
        if let subject = snapshot.preferences.asignaturasHabilitadas
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return subject
        }

        let specialty = snapshot.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines)
        return specialty.isEmpty ? "M\u{00FA}sica" : specialty
    }

    private func dateRange(from clases: [ClaseCronograma]) -> (start: String, end: String)? {
        let dates = clases.compactMap { PlanDateParser.date(from: $0.fecha) }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: first), formatter.string(from: last))
    }
}

private struct NewUnitSheet: View {
    let curriculumUnits: [UnidadCurricular]
    let onAdd: (String, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = "tradicional"
    @State private var curriculumUnitID: String?

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nueva unidad")
                        .font(.title3.weight(.black))
                    Text("Agrégala a tu planificación del curso.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Nombre")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                TextField("Nombre de la nueva unidad", text: $name)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit(addUnit)
                    .accessibilityIdentifier("new-unit-name")
            }

            if !curriculumUnits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VINCULAR CON EL CURRÍCULUM")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Picker("Unidad curricular", selection: $curriculumUnitID) {
                        Text("Elegir después").tag(String?.none)
                        ForEach(curriculumUnits) { unit in
                            Text(unit.displayName).tag(Optional(unit.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tipo")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Picker("Tipo de unidad", selection: $type) {
                    ForEach(TipoUnidad.all, id: \.self) { option in
                        Text("\(TipoUnidad.emoji(option)) \(TipoUnidad.label(option))").tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button(action: addUnit) {
                Label("Agregar unidad", systemImage: "plus")
                    .font(.body.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .opacity(canAdd ? 1 : 0.4)
            .accessibilityIdentifier("add-new-unit")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
    }

    private func addUnit() {
        guard canAdd else { return }
        onAdd(name, type, curriculumUnitID)
        dismiss()
    }
}

private extension UnidadCurricular {
    var displayName: String {
        let name = nombreUnidad.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unidad \(numeroUnidad)" : name
    }
}
