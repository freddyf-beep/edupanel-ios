import SwiftUI

struct PlanificacionesDetailView: View {
    let curso: String
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository
    
    @State private var units: [UnidadPlan] = []
    @State private var isLoading = false
    @State private var activeSubject = "Música"
    @State private var saveStatus = ""
    
    // Inline creation state
    @State private var newUnitName = ""
    @State private var newUnitType = "tradicional"
    
    // Inline rename state
    @State private var renamingUnitId: Int? = nil
    @State private var renamingName = ""
    
    // Delete confirmation state
    @State private var unitToDelete: UnidadPlan? = nil
    @State private var showingDeleteAlert = false
    
    private let colors = ["#F59E0B", "#3B82F6", "#EF4444", "#22C55E", "#8B5CF6", "#F03E6E", "#06B6D4", "#D97706"]

    init(curso: String, dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.curso = curso
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && units.isEmpty {
                ProgressView("Cargando planificación...")
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
                    Text(saveStatus)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(saveStatus.contains("Error") ? .red : .gray, in: Capsule())
                }
            }
        }
        .task {
            await loadData()
        }
        .alert("¿Eliminar Unidad?", isPresented: $showingDeleteAlert, presenting: unitToDelete) { unit in
            Button("Eliminar", role: .destructive) {
                Task { await performDelete(unit: unit) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { unit in
            Text("Esto eliminará la unidad \"\(unit.name)\", su cronograma y todas sus clases planificadas permanentemente.")
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header overview card
                overviewCard
                
                // Add unit inline form
                inlineCreationCard
                
                // Units list
                Text("UNIDADES PROGRAMADAS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                
                if units.isEmpty {
                    emptyState
                } else {
                    unitsList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
    }

    private var overviewCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeSubject.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.pink)
                
                Text(curso)
                    .font(.title3.bold())
                
                Text("\(units.count) unidades planificadas · \(totalHours) horas totales")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            Image(systemName: "book.pages.fill")
                .font(.largeTitle)
                .foregroundStyle(.pink.opacity(0.15))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var inlineCreationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AGREGAR NUEVA UNIDAD")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                TextField("Nombre de la unidad...", text: $newUnitName)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Tipo", selection: $newUnitType) {
                    Text("Tradicional").tag("tradicional")
                    Text("Invertida").tag("invertida")
                    Text("Proyecto").tag("proyecto")
                    Text("Unidad 0").tag("unidad0")
                }
                .font(.caption)
                .pickerStyle(.menu)
                .padding(.horizontal, 6)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                
                Button {
                    addUnit()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Color(hex: "#F03E6E"), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(newUnitName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No hay unidades creadas")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text("Usa el formulario superior para añadir tu primera unidad didáctica.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var unitsList: some View {
        VStack(spacing: 12) {
            ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        // Colored number badge
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color(hex: unit.color), in: Circle())
                            .offset(y: 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // Name display / inline edit
                            if renamingUnitId == unit.id {
                                TextField("Nombre de la unidad", text: $renamingName, onCommit: {
                                    finishRenaming(unitId: unit.id)
                                })
                                .font(.headline)
                                .textFieldStyle(.roundedBorder)
                            } else {
                                Text(unit.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .onTapGesture(count: 2) {
                                        renamingUnitId = unit.id
                                        renamingName = unit.name
                                    }
                            }
                            
                            // Type and Dates Info
                            HStack(spacing: 6) {
                                // Type badge
                                Text(typeEmojiAndLabel(for: unit.type))
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray6), in: Capsule())
                                
                                // Date badge
                                if unit.hasDates {
                                    Text("\(unit.start) al \(unit.end)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Sin fechas")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.1), in: Capsule())
                                }
                                
                                Text("· \(unit.hours) hrs")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Delete button
                        Button {
                            unitToDelete = unit
                            showingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.8))
                                .padding(8)
                                .background(Color.red.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Route Navigation buttons (tabs in ver-unidad)
                    HStack(spacing: 8) {
                        NavigationLink(value: AppRoute.verUnidad(curso: curso, unidadId: String(unit.id), unidadNombre: unit.name, initialTab: "unidad")) {
                            Label("Unidad", systemImage: "text.alignleft")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6), in: Capsule())
                        }
                        
                        NavigationLink(value: AppRoute.verUnidad(curso: curso, unidadId: String(unit.id), unidadNombre: unit.name, initialTab: "cronograma")) {
                            Label("Cronograma", systemImage: "calendar")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6), in: Capsule())
                        }
                        
                        NavigationLink(value: AppRoute.verUnidad(curso: curso, unidadId: String(unit.id), unidadNombre: unit.name, initialTab: "clases")) {
                            Label("Clases", systemImage: "book.closed")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: "#F03E6E"))
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Actions

    private func addUnit() {
        let name = newUnitName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        let nextIndex = units.count + 1
        let nextId = (units.map(\.id).max() ?? 0) + 1
        let color = colors[units.count % colors.count]
        
        let newUnit = UnidadPlan(
            id: nextId,
            name: name,
            color: color,
            hours: 8,
            start: "",
            end: "",
            type: newUnitType,
            unidadCurricularId: "unidad_\(nextIndex)"
        )
        
        units.append(newUnit)
        newUnitName = ""
        
        Task {
            await savePlan()
        }
    }

    private func performDelete(unit: UnidadPlan) async {
        saveStatus = "Eliminando..."
        do {
            try await planificacionRepository.eliminarUnidadCompleta(asignatura: activeSubject, curso: curso, unidadId: String(unit.id))
            units.removeAll { $0.id == unit.id }
            try await planificacionRepository.guardarPlanCurso(asignatura: activeSubject, curso: curso, units: units)
            saveStatus = "Guardado"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            saveStatus = ""
        } catch {
            saveStatus = "Error"
        }
    }

    private func finishRenaming(unitId: Int) {
        let name = renamingName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            if let index = units.firstIndex(where: { $0.id == unitId }) {
                units[index].name = name
                Task {
                    await savePlan()
                }
            }
        }
        renamingUnitId = nil
        renamingName = ""
    }

    private func loadData() async {
        isLoading = true
        do {
            let snap = try await dashboardRepository.fetchDashboard()
            activeSubject = snap.preferences.asignaturasHabilitadas.first ?? "Música"
            
            if let plan = try await planificacionRepository.cargarPlanCurso(asignatura: activeSubject, curso: curso) {
                units = plan.units
            } else {
                units = []
            }
        } catch {
            saveStatus = "Error al cargar"
        }
        isLoading = false
    }

    private var totalHours: Int {
        units.reduce(0) { $0 + $1.hours }
    }

    private func typeEmojiAndLabel(for type: String) -> String {
        switch type {
        case "unidad0": return "0️⃣ U. Cero"
        case "tradicional": return "📘 Tradicional"
        case "invertida": return "🔄 Invertida"
        case "proyecto": return "🎯 Proyecto"
        default: return "📘 Unidad"
        }
    }
}

// MARK: - Color Hex Helper (if not globally declared)
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
