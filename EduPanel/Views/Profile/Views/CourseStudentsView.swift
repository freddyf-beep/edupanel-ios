import SwiftUI

struct CourseStudentsView: View {
    let courseName: String
    let repository: DashboardRepository

    @State private var students: [EstudiantePerfil] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var savingStatus: ProfileSaveStatus = .idle

    // Sheet controls
    @State private var isShowingEditor = false
    @State private var editingStudent: EstudiantePerfil?
    @State private var editorName = ""
    @State private var editorOrder = 1
    @State private var editorIsPie = false
    @State private var editorPieDiagnostico = ""
    @State private var editorPieEspecialista = ""
    @State private var editorPieNotas = ""

    // Import controls
    @State private var isShowingImporter = false
    @State private var rawImportText = ""

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando lista de estudiantes...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gestión manual y masiva")
                                    .font(.footnote.weight(.black))
                                Text("Puedes agregar estudiantes uno por uno o usar importación rápida por texto.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)

                        HStack(spacing: 12) {
                            Button {
                                openAddEditor()
                            } label: {
                                Label("Agregar estudiante", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(EPTheme.primary)

                            Button {
                                rawImportText = ""
                                isShowingImporter = true
                            } label: {
                                Label("Importar texto", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                        .font(.footnote.weight(.bold))
                    }
                    .listRowBackground(Color.clear)

                    if students.isEmpty {
                        Section {
                            EPEmptyState(
                                icon: "person.2.slash.fill",
                                title: "Sin estudiantes registrados",
                                message: "Toca los botones superiores para poblar el curso."
                            )
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Section("Estudiantes (\(students.count))") {
                            ForEach(students) { student in
                                Button {
                                    openEditEditor(student)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text("\(student.orden)")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28, height: 28)
                                            .background(Color(.systemGray5), in: Circle())

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(student.nombre)
                                                .font(.footnote.weight(.bold))
                                                .foregroundStyle(.primary)

                                            if student.pie {
                                                let details = [student.pieDiagnostico, student.pieEspecialista]
                                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                                    .filter { !$0.isEmpty }
                                                Text("PIE" + (details.isEmpty ? "" : ": \(details.joined(separator: " · "))"))
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }

                                        Spacer()

                                        if student.pie {
                                            Image(systemName: "exclamationmark.shield.fill")
                                                .foregroundStyle(.orange)
                                                .font(.caption)
                                        }

                                        Image(systemName: "pencil")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteStudents)
                        }
                    }
                }
            }

            if let errorMessage {
                ProfileErrorBanner(message: errorMessage)
                    .padding()
            }

            if savingStatus != .idle {
                HStack {
                    ProfileSaveBadge(status: savingStatus)
                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .navigationTitle(courseName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Guardar") {
                    Task { await saveList() }
                }
                .font(.subheadline.weight(.black))
                .tint(EPTheme.primary)
                .disabled(isLoading || savingStatus == .saving)
            }
        }
        .task {
            await loadStudents()
        }
        .sheet(isPresented: $isShowingEditor) {
            studentEditorSheet
        }
        .sheet(isPresented: $isShowingImporter) {
            importerSheet
        }
    }

    private var studentEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Información básica") {
                    TextField("Nombre completo", text: $editorName)
                        .font(.footnote)
                    
                    Stepper("Número de lista (Orden): \(editorOrder)", value: $editorOrder, in: 1...200)
                        .font(.footnote)
                }

                Section("Necesidades Educativas Especiales") {
                    Toggle("Estudiante PIE", isOn: $editorIsPie)
                        .font(.footnote.weight(.semibold))

                    if editorIsPie {
                        TextField("Diagnóstico (Ej: TDAH, FIL, DEA)", text: $editorPieDiagnostico)
                            .font(.footnote)
                        TextField("Especialista a cargo", text: $editorPieEspecialista)
                            .font(.footnote)
                        TextField("Notas o adecuaciones", text: $editorPieNotas)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(editingStudent == nil ? "Nuevo Estudiante" : "Editar Estudiante")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { isShowingEditor = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aceptar") {
                        commitStudent()
                    }
                    .font(.footnote.weight(.black))
                    .disabled(editorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var importerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Carga rápida de alumnos")
                    .font(.subheadline.weight(.black))
                
                Text("Pega una lista de nombres de estudiantes (uno por línea), o un arreglo JSON con estructura de estudiantes. Los números de orden se asignarán automáticamente según el orden en que aparezcan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $rawImportText)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

                Button {
                    processImportText()
                } label: {
                    Label("Importar ahora", systemImage: "arrow.right.doc.on.clipboard")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(rawImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
            .navigationTitle("Importación Masiva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { isShowingImporter = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Logic Helpers

    private func loadStudents() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard()
            students = next.studentsByCourse[courseName] ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func saveList() async {
        savingStatus = .saving
        errorMessage = nil
        do {
            try await repository.saveStudents(students, for: courseName)
            savingStatus = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                savingStatus = .idle
            }
        } catch {
            errorMessage = error.localizedDescription
            savingStatus = .error
        }
    }

    private func openAddEditor() {
        editingStudent = nil
        editorName = ""
        editorOrder = (students.map(\.orden).max() ?? 0) + 1
        editorIsPie = false
        editorPieDiagnostico = ""
        editorPieEspecialista = ""
        editorPieNotas = ""
        isShowingEditor = true
    }

    private func openEditEditor(_ student: EstudiantePerfil) {
        editingStudent = student
        editorName = student.nombre
        editorOrder = student.orden
        editorIsPie = student.pie
        editorPieDiagnostico = student.pieDiagnostico
        editorPieEspecialista = student.pieEspecialista
        editorPieNotas = student.pieNotas
        isShowingEditor = true
    }

    private func commitStudent() {
        let name = editorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let item = EstudiantePerfil(
            id: editingStudent?.id ?? "est_\(UUID().uuidString.prefix(6))",
            nombre: name,
            orden: editorOrder,
            pie: editorIsPie,
            pieDiagnostico: editorIsPie ? editorPieDiagnostico : "",
            pieEspecialista: editorIsPie ? editorPieEspecialista : "",
            pieNotas: editorIsPie ? editorPieNotas : ""
        )

        if let index = students.firstIndex(where: { $0.id == item.id }) {
            students[index] = item
        } else {
            students.append(item)
        }

        // Keep list sorted by order
        students.sort { $0.orden < $1.orden }
        isShowingEditor = false
    }

    private func deleteStudents(at offsets: IndexSet) {
        students.remove(atOffsets: offsets)
        // reorder order values
        for i in 0..<students.count {
            let s = students[i]
            students[i] = EstudiantePerfil(
                id: s.id,
                nombre: s.nombre,
                orden: i + 1,
                pie: s.pie,
                pieDiagnostico: s.pieDiagnostico,
                pieEspecialista: s.pieEspecialista,
                pieNotas: s.pieNotas
            )
        }
    }

    private func processImportText() {
        let text = rawImportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var imported: [EstudiantePerfil] = []

        // Try JSON first
        if text.hasPrefix("[") && text.hasSuffix("]") {
            if let data = text.data(using: .utf8),
               let jsonList = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for (index, dict) in jsonList.enumerated() {
                    if let student = EstudiantePerfil.from(dictionary: dict, index: index) {
                        imported.append(student)
                    }
                }
            }
        }

        // Fallback to plain list of names
        if imported.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            var index = 0
            for line in lines {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                let student = EstudiantePerfil(
                    id: "est_imp_\(UUID().uuidString.prefix(5))",
                    nombre: clean,
                    orden: index + 1,
                    pie: false,
                    pieDiagnostico: "",
                    pieEspecialista: "",
                    pieNotas: ""
                )
                imported.append(student)
                index += 1
            }
        }

        if !imported.isEmpty {
            self.students = imported.sorted { $0.orden < $1.orden }
            isShowingImporter = false
        }
    }
}
