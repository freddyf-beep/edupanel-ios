import SwiftUI

struct VerUnidadClasesView: View {
    @Bindable var viewModel: VerUnidadViewModel
    @State private var selectedClassNum: Int = 1
    @State private var showingLiveMode = false
    
    @State private var newMaterial = ""
    @State private var newTic = ""

    var body: some View {
        VStack(spacing: 0) {
            // Horizontal Class Selector Rail
            classSelectorRail
            
            // Central Editor View
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Class Header overview
                    classHeaderCard
                    
                    // Core Editor Fields
                    editorFields
                    
                    // Materials & TICs
                    resourcesSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingLiveMode) {
            if let act = viewModel.clasesActividades[selectedClassNum] {
                LiveClassModeView(
                    actividad: act,
                    students: getStudents(),
                    dashboardRepository: viewModel.planificacionRepository // matches DB ref
                )
            }
        }
    }
    
    // MARK: - Class selector rail
    
    private var classSelectorRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let crono = viewModel.cronograma {
                    ForEach(1...crono.totalClases, id: \.self) { cNum in
                        let isSelected = selectedClassNum == cNum
                        let hasData = isClassPlanificable(classNum: cNum)
                        
                        Button {
                            selectedClassNum = cNum
                        } label: {
                            HStack(spacing: 4) {
                                Text("Clase \(cNum)")
                                    .font(.caption.bold())
                                if hasData {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? .white : Color(.label))
                            .background(isSelected ? Color(hex: "#F03E6E") : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.02), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .border(width: 1, edges: [.bottom], color: Color(.separator).opacity(0.15))
    }
    
    // MARK: - Class Header Card
    
    private var classHeaderCard: some View {
        let act = activeActivity
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        let dateLabel = act.fecha.isEmpty ? "Fecha no programada" : "Programada: \(act.fecha)"
        
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DETALLE DE LA JORNADA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.pink)
                    .tracking(1.1)
                
                Text("Clase \(selectedClassNum): Plan de Aula")
                    .font(.headline)
                
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Live class button
            Button {
                showingLiveMode = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Clase en Vivo")
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(hex: "#F03E6E"), in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Editor Fields
    
    private var editorFields: some View {
        let binding = activeActivityBinding
        
        return VStack(alignment: .leading, spacing: 14) {
            Text("PLANIFICACIÓN DIARIA")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.1)
            
            // Objetivo de Clase
            VStack(alignment: .leading, spacing: 4) {
                Text("Objetivo de Aprendizaje de la Clase (Meta Diaria)")
                    .font(.caption.bold())
                TextField("Crear un primer boceto de paisaje sonoro...", text: binding.objetivo)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Contexto Docente
            VStack(alignment: .leading, spacing: 4) {
                Text("Contexto de la Clase (Opcional)")
                    .font(.caption.bold())
                TextField("Notas pedagógicas...", text: binding.contextoProfesor.toNonOptional())
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
            }
            
            Divider()
            
            // Inicio
            VStack(alignment: .leading, spacing: 4) {
                Text("Momento 1: Inicio (Activación de conocimientos)")
                    .font(.caption.bold())
                TextEditor(text: binding.inicio)
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Desarrollo
            VStack(alignment: .leading, spacing: 4) {
                Text("Momento 2: Desarrollo (Actividad principal)")
                    .font(.caption.bold())
                TextEditor(text: binding.desarrollo)
                    .frame(minHeight: 70)
                    .padding(6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Cierre
            VStack(alignment: .leading, spacing: 4) {
                Text("Momento 3: Cierre (Meta-cognición y evaluación)")
                    .font(.caption.bold())
                TextEditor(text: binding.cierre)
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
            
            Divider()
            
            // Adecuación Curricular PIE
            VStack(alignment: .leading, spacing: 4) {
                Text("Adecuación Curricular (Estrategias PIE / DUA)")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                TextEditor(text: binding.adecuacion)
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Resources Section
    
    private var resourcesSection: some View {
        let binding = activeActivityBinding
        
        return VStack(alignment: .leading, spacing: 14) {
            Text("RECURSOS Y MATERIALES DE CLASE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.1)
            
            // Materiales
            VStack(alignment: .leading, spacing: 6) {
                Text("Materiales Físicos:")
                    .font(.caption.bold())
                
                FlowLayout(spacing: 6) {
                    ForEach(binding.wrappedValue.materiales, id: \.self) { mat in
                        Text(mat)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5), in: Capsule())
                            .onLongPressGesture {
                                viewModel.clasesActividades[selectedClassNum]?.materiales.removeAll { $0 == mat }
                            }
                    }
                }
                
                HStack(spacing: 8) {
                    TextField("Añadir material...", text: $newMaterial)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let m = newMaterial.trimmingCharacters(in: .whitespaces)
                        if !m.isEmpty {
                            viewModel.clasesActividades[selectedClassNum]?.materiales.append(m)
                            newMaterial = ""
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color(hex: "#F03E6E"), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            // TICs
            VStack(alignment: .leading, spacing: 6) {
                Text("Herramientas TICs:")
                    .font(.caption.bold())
                
                FlowLayout(spacing: 6) {
                    ForEach(binding.wrappedValue.tics, id: \.self) { tic in
                        Text(tic)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5), in: Capsule())
                            .onLongPressGesture {
                                viewModel.clasesActividades[selectedClassNum]?.tics.removeAll { $0 == tic }
                            }
                    }
                }
                
                HStack(spacing: 8) {
                    TextField("Añadir TIC...", text: $newTic)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let t = newTic.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty {
                            viewModel.clasesActividades[selectedClassNum]?.tics.append(t)
                            newTic = ""
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color(hex: "#F03E6E"), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Helpers
    
    private var activeActivity: ActividadClase {
        viewModel.clasesActividades[selectedClassNum] ?? ActividadClase(
            id: "", asignatura: viewModel.activeSubject, curso: viewModel.curso,
            unidadId: viewModel.unidadId, numeroClase: selectedClassNum, fecha: "",
            oaIds: [], objetivo: "", inicio: "", desarrollo: "", cierre: "",
            adecuacion: "", habilidades: [], actitudes: [], materiales: [], tics: [],
            estado: "no_planificada", sincronizada: false
        )
    }
    
    private var activeActivityBinding: Binding<ActividadClase> {
        Binding(
            get: {
                self.activeActivity
            },
            set: { newValue in
                viewModel.clasesActividades[selectedClassNum] = newValue
            }
        )
    }

    private func isClassPlanificable(classNum: Int) -> Bool {
        guard let act = viewModel.clasesActividades[classNum] else { return false }
        return !act.objetivo.isEmpty || !act.inicio.isEmpty || !act.desarrollo.isEmpty
    }

    private func getStudents() -> [EstudiantePerfil] {
        // Simple fallback students array if snapshot list not loaded
        return viewModel.snapshot?.studentsByCourse[viewModel.curso] ?? []
    }
}

// Optional binding helper
private extension Binding whereValue: Optional<String> {
    func toNonOptional() -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}

private extension Binding where Value == Optional<String> {
    func toNonOptional() -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}

// Border Modifier
private struct BorderModifier: ViewModifier {
    var width: CGFloat
    var edges: [Edge]
    var color: Color

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                ZStack {
                    ForEach(edges, id: \.self) { edge in
                        self.border(edge: edge, geometry: geometry)
                    }
                }
            }
        )
    }

    private func border(edge: Edge, geometry: GeometryProxy) -> some View {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat

        switch edge {
        case .top:
            x = 0
            y = 0
            w = geometry.size.width
            h = width
        case .bottom:
            x = 0
            y = geometry.size.height - width
            w = geometry.size.width
            h = width
        case .leading:
            x = 0
            y = 0
            w = width
            h = geometry.size.height
        case .trailing:
            x = geometry.size.width - width
            y = 0
            w = width
            h = geometry.size.height
        }

        return Rectangle()
            .fill(color)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}

private extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        modifier(BorderModifier(width: width, edges: edges, color: color))
    }
}

// Color Hex Helper (if not globally declared)
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
