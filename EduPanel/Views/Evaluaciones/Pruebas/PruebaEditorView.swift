import SwiftUI
import UniformTypeIdentifiers

struct PruebaEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let pruebaId: String?
    let curso: String
    let asignatura: String
    let scope: EvaluacionScope
    let repository: EvaluacionesRepository
    let dashboardRepository: DashboardRepository

    private let mediaRepository = EvaluacionesMediaRepository()
    private let itemBankRepository = ItemBankRepository()
    private let pdfExporter = GuiaPDFExporter()
    private let aiService = EvaluacionesAIService()
    private let wordService = EvaluacionesWordService()

    @State private var draft: PruebaEditorDraft
    @State private var savedDraft: PruebaEditorDraft
    @State private var nivelMapping: [String: String] = [:]
    @State private var isLoading: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveSucceeded = false
    @State private var showDiscardConfirmation = false
    @State private var showReloadConfirmation = false
    @State private var showItemBank = false
    @State private var itemBankMessage: String?
    @State private var itemBankMessageIsError = false
    @State private var school: InfoColegio = .empty
    @State private var sourceTest: PruebaTemplate?
    @State private var exportArtifact: GuiaPDFArtifact?
    @State private var exportingMode: GuiaPDFMode?
    @State private var exportErrorMessage: String?
    @State private var showAIGeneration = false
    @State private var showWordImporter = false
    @State private var wordArtifact: EvaluacionesWordArtifact?
    @State private var wordMessage: String?

    init(
        pruebaId: String?,
        curso: String,
        asignatura: String,
        scope: EvaluacionScope,
        repository: EvaluacionesRepository,
        dashboardRepository: DashboardRepository
    ) {
        self.pruebaId = pruebaId
        self.curso = curso
        self.asignatura = asignatura
        self.scope = scope
        self.repository = repository
        self.dashboardRepository = dashboardRepository
        let initial = PruebaEditorDraft.nueva(curso: curso, asignatura: asignatura)
        _draft = State(initialValue: initial)
        _savedDraft = State(initialValue: initial)
        _isLoading = State(initialValue: pruebaId != nil)
    }

    private var hasChanges: Bool {
        !isReadOnly && draft.editableFingerprint != savedDraft.editableFingerprint
    }

    private var isReadOnly: Bool {
        draft.estado.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression) == "aplicada"
    }
    private var visibleSections: [PruebaSectionDraft] { draft.secciones.filter { !$0.isDeleted } }
    private var totalItems: Int { visibleSections.reduce(0) { $0 + $1.items.filter { !$0.isDeleted }.count } }
    private var totalPoints: Double {
        visibleSections.reduce(0) { total, section in
            total + section.items.filter { !$0.isDeleted }.reduce(0) { $0 + max(0, $1.score) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    EvaluacionesLoadingCard(texto: "Cargando editor de prueba...")
                } else if let errorMessage, pruebaId != nil, draft.id == nil {
                    EvaluacionesRetryCard(
                        title: "No se pudo abrir la prueba",
                        message: errorMessage,
                        isLoading: isLoading
                    ) {
                        Task { await load() }
                    }
                } else {
                    if let errorMessage {
                        EvaluacionesErrorBanner(message: errorMessage)
                        if draft.id != nil {
                            Button { showReloadConfirmation = true } label: {
                                Label("Recargar desde EduPanel", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.black))
                            }
                            .buttonStyle(.bordered)
                            .tint(EPTheme.rose)
                        }
                    }
                    if isReadOnly { readOnlyNotice }
                    if let itemBankMessage {
                        Label(
                            itemBankMessage,
                            systemImage: itemBankMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(itemBankMessageIsError ? .orange : .green)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((itemBankMessageIsError ? Color.orange : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    }
                    if let wordMessage {
                        Label(wordMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    }
                    summaryCard
                    VStack(alignment: .leading, spacing: 14) {
                        generalCard
                        EvaluacionesCurriculoSection(
                            asignatura: draft.asignatura,
                            curso: draft.curso,
                            nivelMapping: nivelMapping,
                            autoResolveExistingUnit: draft.id == nil || draft.oas != nil,
                            unidadId: optionalStringBinding(\.unidadId),
                            unidadNombre: optionalStringBinding(\.unidadNombre),
                            oas: $draft.oas
                        )
                        instructionsCard
                        PruebaContentEditorView(
                            sections: $draft.secciones,
                            oas: draft.oas ?? [],
                            onSaveToBank: { item in Task { await saveToBank(item) } }
                        )
                            .environment(
                                \.guiaMediaContext,
                                GuiaMediaContext(
                                    documentId: draft.id,
                                    repository: mediaRepository,
                                    folder: .pruebas
                                )
                            )
                        preservationNotice
                    }
                    .disabled(isReadOnly)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(EPTheme.background)
        .navigationTitle(draft.id == nil ? "Nueva prueba" : "Editar prueba")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { showDiscardConfirmation = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isReadOnly {
                    Label("Solo lectura", systemImage: "lock.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.blue)
                } else {
                    Button { Task { await save() } } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(saveSucceeded ? "Guardado" : "Guardar")
                                .font(.footnote.weight(.black))
                                .foregroundStyle(saveSucceeded ? .green : EPTheme.rose)
                        }
                    }
                    .disabled(
                        isLoading || isSaving || (errorMessage != nil && draft.id != nil) ||
                        !draft.isValid || !hasChanges
                    )
                    .accessibilityHint(draft.isValid ? "Guarda los cambios de la prueba" : "Completa nombre, asignatura y curso")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAIGeneration = true } label: {
                    Label("Crear con IA", systemImage: "wand.and.stars")
                }
                .disabled(isLoading || isReadOnly || draft.curso.isEmpty || draft.asignatura.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showItemBank = true } label: {
                    Label("Banco", systemImage: "tray.full.fill")
                }
                .disabled(isLoading || isReadOnly || draft.curso.isEmpty || draft.asignatura.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Importar .docx", systemImage: "square.and.arrow.down") { showWordImporter = true }
                    Button("Exportar .docx", systemImage: "doc.richtext") { exportWord() }
                } label: {
                    Label("Word", systemImage: "doc.richtext")
                }
                .disabled(isLoading || isReadOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    GuiaPDFExportActions(templates: school.testExportTemplates) { mode, format in
                        beginExport(mode, formatOverride: format)
                    }
                } label: {
                    if exportingMode != nil { ProgressView() }
                    else { Label("Exportar", systemImage: "square.and.arrow.up") }
                }
                .disabled(isLoading || exportingMode != nil || !draft.isValid)
            }
        }
        .confirmationDialog("\u{00BF}Descartar cambios?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { dismiss() }
            Button("Seguir editando", role: .cancel) {}
        } message: {
            Text("Los cambios que a\u{00FA}n no guardaste se perder\u{00E1}n.")
        }
        .confirmationDialog("¿Recargar la prueba?", isPresented: $showReloadConfirmation, titleVisibility: .visible) {
            Button("Recargar y descartar cambios", role: .destructive) {
                Task { await load(force: true) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se descargará la versión más reciente del colegio activo.")
        }
        .onChange(of: draft) { _, value in
            if value.editableFingerprint != savedDraft.editableFingerprint { saveSucceeded = false }
        }
        .sheet(isPresented: $showItemBank) {
            ItemBankSheet(
                target: .prueba,
                asignatura: draft.asignatura,
                curso: draft.curso,
                onInsert: insertFromBank
            )
        }
        .sheet(isPresented: $showAIGeneration) {
            EvaluacionesAIGenerationSheet(
                title: "Crear prueba con IA",
                explanation: "Genera preguntas generales usando el curso, asignatura, unidad y OA seleccionados.",
                initialInstructions: "Crea 10 preguntas equilibradas. Incluye selección múltiple, verdadero/falso, completar, respuesta corta y desarrollo. Dificultad media. No realices adaptaciones PIE ni calibración Bloom."
            ) { instructions in
                let generated = try await aiService.generateTest(from: draft, instructions: instructions)
                await MainActor.run { appendGeneratedTestSections(generated) }
            }
        }
        .sheet(item: $exportArtifact) { artifact in
            GuiaPDFShareSheet(artifact: artifact)
        }
        .sheet(item: $wordArtifact) { artifact in
            EvaluacionesWordShareSheet(artifact: artifact)
        }
        .fileImporter(
            isPresented: $showWordImporter,
            allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data],
            allowsMultipleSelection: false,
            onCompletion: importWord
        )
        .alert("No se pudo exportar", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "Error desconocido")
        }
        .task { await load() }
    }

    private func appendGeneratedTestSections(_ generated: [PruebaSectionDraft]) {
        if draft.secciones.count == 1,
           draft.secciones[0].items.filter({ !$0.isDeleted }).isEmpty,
           draft.secciones[0].estimulo.filter({ !$0.isDeleted }).isEmpty {
            draft.secciones.removeAll()
        }
        draft.secciones.append(contentsOf: generated)
        for index in draft.secciones.indices { draft.secciones[index].orden = index + 1 }
        if draft.nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.nombre = "Prueba de \(draft.unidadNombre.isEmpty ? draft.asignatura : draft.unidadNombre)"
        }
    }

    private func importWord(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let imported = try wordService.importTest(from: url)
            if draft.secciones.count == 1,
               draft.secciones[0].items.filter({ !$0.isDeleted }).isEmpty {
                draft.secciones.removeAll()
            }
            draft.secciones.append(imported.section)
            for index in draft.secciones.indices { draft.secciones[index].orden = index + 1 }
            wordMessage = imported.warning
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportWord() {
        do {
            wordArtifact = try wordService.export(test: draft)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 9) {
            EPKPIBox(title: "Secciones", value: "\(visibleSections.count)", subtitle: "estructura", icon: "rectangle.stack.fill", tint: EPTheme.rose)
            EPKPIBox(title: "\u{00CD}tems", value: "\(totalItems)", subtitle: "preguntas", icon: "number.square.fill", tint: .blue)
            EPKPIBox(
                title: "Puntaje",
                value: totalPoints.formatted(.number.precision(.fractionLength(0...1))),
                subtitle: "m\u{00E1}ximo",
                icon: "star.circle.fill",
                tint: .orange
            )
        }
    }

    private var generalCard: some View {
        editorCard(title: "Configuraci\u{00F3}n general", icon: "doc.text.fill") {
            field("Nombre", placeholder: "Ej: Prueba Unidad 2", text: $draft.nombre)
            HStack(alignment: .top, spacing: 10) {
                field("Asignatura", placeholder: "Asignatura", text: $draft.asignatura)
                field("Curso", placeholder: "Curso", text: $draft.curso)
            }
            field("Docente", placeholder: "Nombre docente", text: $draft.docenteNombre)

            VStack(alignment: .leading, spacing: 6) {
                editorLabel("Tipo de evaluaci\u{00F3}n")
                Picker("Tipo de evaluaci\u{00F3}n", selection: $draft.tipoEvaluacion) {
                    Text("Sumativa").tag("sumativa")
                    Text("Formativa").tag("formativa")
                    Text("Diagn\u{00F3}stica").tag("diagnostica")
                }
                .pickerStyle(.segmented)
            }

            Stepper(
                "Tiempo: \(draft.tiempoMinutos) minutos",
                value: $draft.tiempoMinutos,
                in: 5...300,
                step: 5
            )
            .font(.caption.weight(.semibold))

            Stepper(
                "Ponderaci\u{00F3}n: \(draft.ponderacion.formatted(.number.precision(.fractionLength(0...1))))%",
                value: $draft.ponderacion,
                in: 0...100,
                step: 1
            )
            .font(.caption.weight(.semibold))

            Stepper(
                "Exigencia: \(Int((draft.exigencia * 100).rounded()))%",
                value: $draft.exigencia,
                in: 0.05...1,
                step: 0.05
            )
            .font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                editorLabel("Estado")
                if isReadOnly {
                    EPStatusPill(text: "Aplicada", icon: "lock.fill", tint: .blue)
                } else {
                    Picker("Estado", selection: $draft.estado) {
                        Text("Borrador").tag("borrador")
                        Text("Lista").tag("lista")
                        Text("Archivada").tag("archivada")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var instructionsCard: some View {
        editorCard(title: "Instrucciones generales", icon: "list.number") {
            ForEach(Array(draft.instruccionesGenerales.indices), id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(EPTheme.rose)
                        .frame(width: 24, height: 24)
                        .background(EPTheme.rose.opacity(0.1), in: Circle())
                    TextField("Instrucci\u{00F3}n", text: instructionBinding(index), axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        draft.instruccionesGenerales.remove(at: index)
                    } label: {
                        Image(systemName: "trash").font(.caption.weight(.bold))
                    }
                    .disabled(draft.instruccionesGenerales.count <= 1)
                }
            }
            Button { draft.instruccionesGenerales.append("") } label: {
                Label("Agregar instrucci\u{00F3}n", systemImage: "plus.circle.fill")
                    .font(.caption.weight(.black))
            }
        }
    }

    private var readOnlyNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("Prueba aplicada: solo lectura").font(.caption.weight(.black))
                Text("La prueba ya fue usada con estudiantes. Su estructura se muestra completa, pero no puede modificarse.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var preservationNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkered").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Edici\u{00F3}n compatible con EduPanel web").font(.caption.weight(.black))
                Text("Los campos heredados, adaptaciones PIE y tipos desconocidos se conservan. Las im\u{00E1}genes de bloques se habilitan despu\u{00E9}s del primer guardado.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func editorCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(EPTheme.rose)
                content()
            }
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            editorLabel(label)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorLabel(_ value: String) -> some View {
        Text(value.uppercased())
            .font(.system(size: 9.5, weight: .black))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }

    private func instructionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft.instruccionesGenerales.indices.contains(index) ? draft.instruccionesGenerales[index] : "" },
            set: { if draft.instruccionesGenerales.indices.contains(index) { draft.instruccionesGenerales[index] = $0 } }
        )
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<PruebaEditorDraft, String>) -> Binding<String?> {
        Binding(
            get: {
                let value = draft[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            },
            set: { draft[keyPath: keyPath] = $0 ?? "" }
        )
    }

    private func insertFromBank(_ entry: ItemBankEntry) -> Bool {
        guard !isReadOnly, let item = entry.pruebaDraft() else { return false }
        if draft.secciones.allSatisfy(\.isDeleted) {
            draft.secciones.append(.nueva(order: 1, type: item.type))
        }
        guard let index = draft.secciones.lastIndex(where: { !$0.isDeleted }) else { return false }
        draft.secciones[index].items.append(item)
        itemBankMessageIsError = false
        itemBankMessage = "Pregunta insertada desde el banco."
        return true
    }

    @MainActor
    private func saveToBank(_ item: PruebaItemDraft) async {
        do {
            _ = try await itemBankRepository.save(
                item: item,
                asignatura: draft.asignatura,
                curso: draft.curso,
                author: draft.docenteNombre
            )
            itemBankMessageIsError = false
            itemBankMessage = "Pregunta guardada en el banco compartido."
        } catch {
            itemBankMessageIsError = true
            itemBankMessage = error.localizedDescription
        }
    }

    @MainActor
    private func load(force: Bool = false) async {
        if nivelMapping.isEmpty || school == .empty {
            async let dashboardTask: DashboardSnapshot? = try? await dashboardRepository.fetchDashboard()
            async let schoolTask: InfoColegio? = try? await dashboardRepository.fetchExportSchool(scope: scope)
            if let snapshot = await dashboardTask { nivelMapping = snapshot.nivelMapping }
            if let exportSchool = await schoolTask { school = exportSchool }
        }
        guard let pruebaId, force || draft.id == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let test = try await repository.cargarPrueba(id: pruebaId, scope: scope) else {
                errorMessage = "La prueba ya no existe o no pertenece al colegio activo."
                return
            }
            let loaded = PruebaEditorDraft.from(test)
            sourceTest = test
            draft = loaded
            savedDraft = loaded
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard draft.isValid, !isSaving, !isReadOnly else { return }
        let previousMediaPaths = savedDraft.ownedMediaStoragePaths
        isSaving = true
        errorMessage = nil
        saveSucceeded = false
        defer { isSaving = false }
        do {
            let id = try await repository.guardarPruebaEditor(draft, scope: scope)
            do {
                guard let refreshed = try await repository.cargarPrueba(id: id, scope: scope) else {
                    throw EvaluacionesRepositoryError.invalidDocument(collection: "pruebas", id: id)
                }
                let canonical = PruebaEditorDraft.from(refreshed)
                sourceTest = refreshed
                draft = canonical
                savedDraft = canonical
                await mediaRepository.eliminarMediosHuerfanos(
                    documentId: id,
                    folder: .pruebas,
                    previousPaths: previousMediaPaths,
                    currentPaths: canonical.ownedMediaStoragePaths
                )
                saveSucceeded = true
            } catch {
                // La transacción ya terminó: conservamos el ID para no crear un
                // duplicado y exigimos recargar antes de otra edición.
                draft.id = id
                draft.baselineFingerprint = draft.editableFingerprint
                savedDraft = draft
                saveSucceeded = true
                errorMessage = "La prueba se guardó, pero no se pudo recargar su versión canónica. Recárgala antes de seguir editando."
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "No se pudo guardar la prueba. \(error.localizedDescription)"
        }
    }

    private func beginExport(_ mode: GuiaPDFMode, formatOverride: ExportFormat? = nil) {
        Task { await export(mode, formatOverride: formatOverride) }
    }

    @MainActor
    private func export(_ mode: GuiaPDFMode, formatOverride: ExportFormat?) async {
        guard draft.isValid, exportingMode == nil else { return }
        exportingMode = mode
        exportErrorMessage = nil
        defer { exportingMode = nil }
        do {
            let preview = try repository.prepararPruebaParaExportar(draft, scope: scope, base: sourceTest)
            exportArtifact = try await pdfExporter.export(
                test: preview,
                school: school,
                teacherName: draft.docenteNombre,
                mode: mode,
                formatOverride: formatOverride
            )
        } catch is CancellationError {
            return
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}
