import SwiftUI

struct LiveClassModeView: View {
    let actividad: ActividadClase
    let students: [EstudiantePerfil]
    let dashboardRepository: PlanificacionRepository // uses Firestore DB reference
    
    @Environment(\.dismiss) private var dismiss
    
    // Timer state
    @State private var timeRemaining: Int = 45 * 60 // 45 minutes default
    @State private var isTimerRunning = true
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // Active Moment State
    @State private var activeMoment: String = "inicio" // "inicio", "desarrollo", "cierre"
    
    // Student observation logs state
    @State private var selectedStudent: EstudiantePerfil? = nil
    @State private var observationText = ""
    @State private var observationType = "general" // "academica", "conductual", "pie", "general"
    @State private var savedObservations: [String: String] = [:] // key: studentId, value: note

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Timer and Status Header
                timerHeader
                
                // Segmented Moment Timeline
                momentSelector
                
                // Instructions Display
                instructionPanel
                
                // Student observations panel title
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.purple)
                    Text("Apoyo y Observaciones de Estudiantes")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(students.filter(\.pie).count) PIE")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)
                
                // Students Grid list
                studentsList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Clase en Vivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Pausar") {
                        isTimerRunning.toggle()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(hex: "#F03E6E"))
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finalizar") {
                        dismiss()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(hex: "#F03E6E"))
                }
            }
            .onReceive(timer) { _ in
                guard isTimerRunning else { return }
                if timeRemaining > 0 {
                    timeRemaining -= 1
                }
            }
            .sheet(item: $selectedStudent) { student in
                observationModal(for: student)
            }
        }
    }
    
    // MARK: - Timer Header
    
    private var timerHeader: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(actividad.curso)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("Clase \(actividad.numeroClase): \(actividad.objetivo.isEmpty ? "Plan de Aula" : actividad.objetivo)")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Timer Display
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(.pink)
                Text(formatTimeString(timeRemaining))
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(timeRemaining < 5 * 60 ? .red : Color(.label))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .border(width: 1, edges: [.bottom], color: Color(.separator).opacity(0.15))
    }
    
    // MARK: - Moment Selector
    
    private var momentSelector: some View {
        HStack(spacing: 0) {
            momentTab(id: "inicio", label: "Inicio", icon: "arrow.right.circle.fill", activeColor: .blue)
            momentTab(id: "desarrollo", label: "Desarrollo", icon: "play.circle.fill", activeColor: .green)
            momentTab(id: "cierre", label: "Cierre", icon: "stop.circle.fill", activeColor: .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .border(width: 1, edges: [.bottom], color: Color(.separator).opacity(0.1))
    }
    
    private func momentTab(id: String, label: String, icon: String, activeColor: Color) -> some View {
        let isActive = activeMoment == id
        
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                activeMoment = id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(isActive ? activeColor : .secondary)
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isActive ? activeColor.opacity(0.12) : Color.clear, in: Capsule())
            .foregroundStyle(isActive ? activeColor : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Instruction Panel
    
    private var instructionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INSTRUCCIÓN MOMENTO ACTUAL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(activeMoment.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(activeMomentColor, in: Capsule())
            }
            
            let inst = getInstructionText()
            Text(inst)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(.label))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .multilineTextAlignment(.leading)
            
            // PIE Support badge if moment requires PIE
            if !actividad.adecuacion.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.purple)
                    Text("Adecuación PIE: \(actividad.adecuacion)")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
    
    // MARK: - Students list
    
    private var studentsList: some View {
        ScrollView(.vertical) {
            let columns = [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]
            
            LazyVGrid(columns: columns, spacing: 8) {
                if students.isEmpty {
                    Text("No hay estudiantes registrados en este curso.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(students) { student in
                        Button {
                            selectedStudent = student
                            observationText = savedObservations[student.id] ?? ""
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(student.nombre)
                                        .font(.caption.bold())
                                        .foregroundStyle(Color(.label))
                                        .lineLimit(1)
                                    
                                    HStack {
                                        if student.pie {
                                            Text("PIE")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.purple)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.purple.opacity(0.12), in: Capsule())
                                        }
                                        
                                        if savedObservations[student.id] != nil {
                                            Image(systemName: "note.text")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(student.pie ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Observation Modal
    
    private func observationModal(for student: EstudiantePerfil) -> some View {
        NavigationStack {
            Form {
                Section("Escribe una observación para \(student.nombre)") {
                    TextEditor(text: $observationText)
                        .frame(minHeight: 100)
                    
                    Picker("Tipo de Nota", selection: $observationType) {
                        Text("General").tag("general")
                        Text("Académica").tag("academica")
                        Text("Conductual").tag("conductual")
                        Text("PIE / DUA").tag("pie")
                    }
                }
            }
            .navigationTitle(student.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        selectedStudent = nil
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        if !observationText.trimmingCharacters(in: .whitespaces).isEmpty {
                            savedObservations[student.id] = observationText
                            
                            // Query/Save observation logic (simulated or real Firestore write)
                            Task {
                                let ref = Firestore.firestore()
                                guard let uid = Auth.auth().currentUser?.uid else { return }
                                let docId = "obs_" + PlanificacionRepository.buildDocId(asignatura: actividad.asignatura, nivel: actividad.curso) + "_" + student.id
                                
                                let obsItem: [String: Any] = [
                                    "id": UUID().uuidString,
                                    "texto": observationText,
                                    "fecha": DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none),
                                    "tipo": observationType
                                ]
                                
                                try? await ref.collection("users").document(uid).collection("observaciones_360").document(docId).setData([
                                    "asignatura": actividad.asignatura,
                                    "curso": actividad.curso,
                                    "estudianteId": student.id,
                                    "observaciones": FieldValue.arrayUnion([obsItem]),
                                    "updatedAt": FieldValue.serverTimestamp()
                                ], merge: true)
                            }
                        } else {
                            savedObservations.removeValue(forKey: student.id)
                        }
                        selectedStudent = nil
                    }
                    .font(.subheadline.bold())
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatTimeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    private func getInstructionText() -> String {
        switch activeMoment {
        case "inicio":
            return actividad.inicio.isEmpty ? "Inicio de clase: Activación y motivación inicial." : cleanHtml(actividad.inicio)
        case "desarrollo":
            return actividad.desarrollo.isEmpty ? "Desarrollo de clase: Explicación y actividad didáctica principal." : cleanHtml(actividad.desarrollo)
        case "cierre":
            return actividad.cierre.isEmpty ? "Cierre de clase: Preguntas finales, reflexiones y síntesis de la jornada." : cleanHtml(actividad.cierre)
        default:
            return ""
        }
    }
    
    private var activeMomentColor: Color {
        switch activeMoment {
        case "inicio": return .blue
        case "desarrollo": return .green
        case "cierre": return .orange
        default: return .pink
        }
    }
    
    private func cleanHtml(_ text: String) -> String {
        // Simple regex to clear basic HTML tags if any (e.g. from rich text editor)
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
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
