import SwiftUI

struct VerUnidadCronogramaView: View {
    var viewModel: VerUnidadViewModel
    @Binding var selectedTab: String // switches to "clases" when selecting a class

    @State private var isMatrixMode = false
    @State private var classToEditOas: ClaseCronograma? = nil
    @State private var showingOaSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Control Header Bar
            HStack {
                Button {
                    Task { await viewModel.calculateDatesFromSchedule() }
                } label: {
                    Label("Calcular Fechas", systemImage: "calendar.badge.clock")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6), in: Capsule())
                }
                
                Spacer()
                
                // Matrix/List Toggle
                Button {
                    isMatrixMode.toggle()
                } label: {
                    Label(isMatrixMode ? "Vista Secuencia" : "Vista Matriz", systemImage: isMatrixMode ? "list.bullet" : "grid")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: "#F03E6E"))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .border(width: 1, edges: [.bottom], color: Color(.separator).opacity(0.15))
            
            // Content List / Grid
            if let crono = viewModel.cronograma {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isMatrixMode {
                            matrixEditor(crono)
                        } else {
                            sequenceList(crono)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            } else {
                ProgressView()
            }
        }
        .sheet(isPresented: $showingOaSheet, content: {
            if let cl = classToEditOas {
                oaSelectorSheet(for: cl)
            }
        })
    }
    
    // MARK: - Sequence List View
    
    private func sequenceList(_ crono: CronogramaUnidadData) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(crono.clases.enumerated()), id: \.element.numero) { idx, clase in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clase \(clase.numero)")
                                .font(.headline)
                            
                            // Date field
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                
                                TextField("DD/MM/YYYY", text: Binding(
                                    get: { clase.fecha },
                                    set: { val in
                                        if viewModel.cronograma != nil {
                                            viewModel.cronograma!.clases[idx].fecha = val
                                        }
                                    }
                                ))
                                .font(.caption)
                                .frame(width: 90)
                                .textFieldStyle(.plain)
                            }
                        }
                        
                        Spacer()
                        
                        // Action buttons
                        HStack(spacing: 8) {
                            Button {
                                classToEditOas = clase
                                showingOaSheet = true
                            } label: {
                                Label("OAs", systemImage: "tag")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6), in: Capsule())
                            }
                            
                            Button {
                                // Switch tab to Clases editor
                                selectedTab = "clases"
                            } label: {
                                Label("Planificar", systemImage: "chevron.right")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(hex: "#F03E6E").opacity(0.1), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(hex: "#F03E6E"))
                    }
                    
                    // Display current assigned OAs
                    if !clase.oaIds.isEmpty {
                        Divider()
                        HStack(spacing: 6) {
                            Text("OAs:")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            
                            ForEach(clase.oaIds, id: \.self) { oaId in
                                Text(oaId)
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.pink.opacity(0.1), in: Capsule())
                                    .foregroundStyle(Color(hex: "#F03E6E"))
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
    
    // MARK: - Matrix Grid Editor
    
    private func matrixEditor(_ crono: CronogramaUnidadData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MATRIZ DE DISTRIBUCIÓN CURRICULAR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            
            if let verUnidad = viewModel.verUnidad {
                let oas = verUnidad.oas.filter(\.seleccionado)
                
                if oas.isEmpty {
                    Text("Habilita objetivos de aprendizaje en la pestaña Unidad primero.")
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            // Column Headers: Clases
                            HStack(spacing: 0) {
                                Text("Objetivo")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 80, alignment: .leading)
                                
                                ForEach(1...crono.totalClases, id: \.self) { cNum in
                                    Text("C\(cNum)")
                                        .font(.system(size: 9, weight: .bold))
                                        .frame(width: 34, alignment: .center)
                                }
                            }
                            .padding(.bottom, 4)
                            
                            // Rows: OAs
                            ForEach(oas, id: \.id) { oa in
                                HStack(spacing: 0) {
                                    Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 80, alignment: .leading)
                                    
                                    ForEach(1...crono.totalClases, id: \.self) { cNum in
                                        let isAssigned = isOaAssigned(oaId: oa.id, classNum: cNum)
                                        
                                        Button {
                                            toggleOaAssignment(oaId: oa.id, classNum: cNum)
                                        } label: {
                                            Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(isAssigned ? Color(hex: "#F03E6E") : Color(.separator))
                                                .font(.body)
                                                .frame(width: 34, height: 26)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
    
    // MARK: - OA Selector Sheet
    
    private func oaSelectorSheet(for clase: ClaseCronograma) -> some View {
        NavigationStack {
            List {
                if let verUnidad = viewModel.verUnidad {
                    let oas = verUnidad.oas.filter(\.seleccionado)
                    
                    if oas.isEmpty {
                        Text("No hay OAs seleccionados en esta unidad.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(oas, id: \.id) { oa in
                            let isChecked = (classToEditOas?.oaIds.contains(oa.id)) ?? false
                            
                            Button {
                                toggleSheetOa(oaId: oa.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                            .font(.subheadline.bold())
                                        Text(oa.descripcion)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isChecked ? Color(hex: "#F03E6E") : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Asignar OAs a Clase \(clase.numero)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        // Save sheet edits back to viewModel
                        if let updated = classToEditOas,
                           let idx = viewModel.cronograma?.clases.firstIndex(where: { $0.numero == updated.numero }) {
                            viewModel.cronograma!.clases[idx].oaIds = updated.oaIds
                            Task {
                                await viewModel.saveAll()
                            }
                        }
                        showingOaSheet = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers

    private func isOaAssigned(oaId: String, classNum: Int) -> Bool {
        guard let crono = viewModel.cronograma else { return false }
        return crono.clases.first(where: { $0.numero == classNum })?.oaIds.contains(oaId) ?? false
    }

    private func toggleOaAssignment(oaId: String, classNum: Int) {
        guard var crono = viewModel.cronograma else { return }
        if let idx = crono.clases.firstIndex(where: { $0.numero == classNum }) {
            if crono.clases[idx].oaIds.contains(oaId) {
                crono.clases[idx].oaIds.removeAll { $0 == oaId }
            } else {
                crono.clases[idx].oaIds.append(oaId)
            }
            viewModel.cronograma = crono
            
            // Trigger autosave
            Task {
                await viewModel.saveAll()
            }
        }
    }

    private func toggleSheetOa(oaId: String) {
        guard var cl = classToEditOas else { return }
        if cl.oaIds.contains(oaId) {
            cl.oaIds.removeAll { $0 == oaId }
        } else {
            cl.oaIds.append(oaId)
        }
        classToEditOas = cl
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
