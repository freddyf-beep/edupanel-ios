import SwiftUI

struct GuiaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let guiaId: String?
    let curso: String
    let asignatura: String
    let scope: EvaluacionScope
    let repository: EvaluacionesRepository
    let dashboardRepository: DashboardRepository
    private let mediaRepository = EvaluacionesMediaRepository()
    private let pdfExporter = GuiaPDFExporter()
    private let itemBankRepository = ItemBankRepository()
    private let aiService = EvaluacionesAIService()
    private let wordService = EvaluacionesWordService()

    @State private var draft: GuiaEditorDraft
    @State private var savedDraft: GuiaEditorDraft
    @State private var isLoading: Bool
    @State private var isSaving = false
    @State private var saveSucceeded = false
    @State private var errorMessage: String?
    @State private var showDiscardConfirmation = false
    @State private var nivelMapping: [String: String] = [:]
    @State private var school: InfoColegio = .empty
    @State private var sourceGuide: GuiaTemplate?
    @State private var exportArtifact: GuiaPDFArtifact?
    @State private var exportingMode: GuiaPDFMode?
    @State private var exportErrorMessage: String?
    @State private var showItemBank = false
    @State private var itemBankMessage: String?
    @State private var itemBankMessageIsError = false
    @State private var showAIGeneration = false
    @State private var wordArtifact: EvaluacionesWordArtifact?

    init(
        guiaId: String?, curso: String, asignatura: String, scope: EvaluacionScope,
        repository: EvaluacionesRepository,
        dashboardRepository: DashboardRepository
    ) {
        self.guiaId = guiaId
        self.curso = curso
        self.asignatura = asignatura
        self.scope = scope
        self.repository = repository
        self.dashboardRepository = dashboardRepository
        let initial = GuiaEditorDraft.nueva(curso: curso, asignatura: asignatura)
        _draft = State(initialValue: initial)
        _savedDraft = State(initialValue: initial)
        _isLoading = State(initialValue: guiaId != nil)
    }

    private var hasChanges: Bool { draft != savedDraft }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    EvaluacionesLoadingCard(texto: "Cargando editor de guía...")
                } else if let errorMessage, guiaId != nil, draft.id == nil {
                    EvaluacionesRetryCard(title: "No se pudo abrir la guía", message: errorMessage, isLoading: isLoading) {
                        Task { await load() }
                    }
                } else {
                    if let errorMessage { EvaluacionesErrorBanner(message: errorMessage) }
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
                    identityCard
                    teachingCard
                    EvaluacionesCurriculoSection(
                        asignatura: draft.asignatura,
                        curso: draft.curso,
                        nivelMapping: nivelMapping,
                        unidadId: optionalStringBinding(\.unidadId),
                        unidadNombre: optionalStringBinding(\.unidadNombre),
                        oas: $draft.oas
                    )
                    instructionsCard
                    GuiaContentEditorView(
                        sections: $draft.secciones,
                        closingBlocks: $draft.cierre,
                        onSaveToBank: { activity in Task { await saveToBank(activity) } }
                    )
                        .environment(
                            \.guiaMediaContext,
                            GuiaMediaContext(documentId: draft.id, repository: mediaRepository)
                        )
                    preservationNotice
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 30)
        }
        .background(EPTheme.background)
        .navigationTitle(draft.id == nil ? "Nueva guía" : "Editar guía")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { showDiscardConfirmation = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { exportWord() } label: {
                    Label("Word", systemImage: "doc.richtext")
                }
                .disabled(isLoading || !draft.isValid)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    GuiaPDFExportActions(templates: school.guideExportTemplates) { mode, format in
                        beginExport(mode, formatOverride: format)
                    }
                } label: {
                    if exportingMode != nil { ProgressView() }
                    else { Label("Exportar", systemImage: "square.and.arrow.up") }
                }
                .disabled(isLoading || isSaving || exportingMode != nil || !draft.isValid)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAIGeneration = true } label: {
                    Label("Crear con IA", systemImage: "wand.and.stars")
                }
                .disabled(isLoading || draft.curso.isEmpty || draft.asignatura.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showItemBank = true } label: {
                    Label("Banco", systemImage: "tray.full.fill")
                }
                .disabled(isLoading || draft.curso.isEmpty || draft.asignatura.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await save() } } label: {
                    if isSaving { ProgressView() }
                    else { Text(saveSucceeded ? "Guardado" : "Guardar").font(.footnote.weight(.black)).foregroundStyle(saveSucceeded ? .green : EPTheme.primary) }
                }
                .disabled(isLoading || isSaving || !draft.isValid || !hasChanges)
                .accessibilityHint(draft.isValid ? "Guarda los cambios de la guía" : "Completa nombre, asignatura y curso")
            }
        }
        .confirmationDialog("¿Descartar cambios?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { dismiss() }
            Button("Seguir editando", role: .cancel) {}
        } message: {
            Text("Los cambios que aún no guardaste se perderán.")
        }
        .sheet(item: $exportArtifact) { artifact in
            GuiaPDFShareSheet(artifact: artifact)
        }
        .sheet(item: $wordArtifact) { artifact in
            EvaluacionesWordShareSheet(artifact: artifact)
        }
        .sheet(isPresented: $showItemBank) {
            ItemBankSheet(
                target: .guia,
                asignatura: draft.asignatura,
                curso: draft.curso,
                onInsert: insertFromBank
            )
        }
        .sheet(isPresented: $showAIGeneration) {
            EvaluacionesAIGenerationSheet(
                title: "Crear guía con IA",
                explanation: "Genera contenido general usando el curso, asignatura, objetivo, unidad y OA seleccionados.",
                initialInstructions: "Crea 3 secciones con explicación breve y actividades variadas para \(draft.tiempoMinutos) minutos. Incluye selección múltiple, completar, respuesta corta y una actividad abierta. No realices adaptaciones PIE ni calibración Bloom."
            ) { instructions in
                let generated = try await aiService.generateGuide(from: draft, instructions: instructions)
                await MainActor.run { appendGeneratedGuideSections(generated) }
            }
        }
        .alert("No se pudo exportar", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "Error desconocido")
        }
        .onChange(of: draft) { _, value in
            if value != savedDraft { saveSucceeded = false }
        }
        .task { await load() }
    }

    private func appendGeneratedGuideSections(_ generated: [GuiaSectionDraft]) {
        draft.secciones.append(contentsOf: generated)
        for index in draft.secciones.indices { draft.secciones[index].orden = index + 1 }
        if draft.nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.nombre = "Guía de \(draft.unidadNombre.isEmpty ? draft.asignatura : draft.unidadNombre)"
        }
    }

    private func exportWord() {
        do {
            wordArtifact = try wordService.export(guide: draft)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private var identityCard: some View {
        editorCard(title: "Información general", icon: "doc.text.fill") {
            field("Nombre", placeholder: "Ej: Guía de aprendizaje Unidad 2", text: $draft.nombre)
            HStack(alignment: .top, spacing: 10) {
                field("Número", placeholder: "Guía N° 1", text: $draft.numeroGuia)
                field("Docente", placeholder: "Nombre docente", text: $draft.docenteNombre)
            }
            field("Asignatura", placeholder: "Asignatura", text: $draft.asignatura)
            field("Curso", placeholder: "Curso", text: $draft.curso)
            HStack(alignment: .top, spacing: 10) {
                field("ID unidad", placeholder: "unidad_1", text: $draft.unidadId)
                field("Unidad", placeholder: "Unidad 1", text: $draft.unidadNombre)
            }
        }
    }

    private var teachingCard: some View {
        editorCard(title: "Propósito pedagógico", icon: "scope") {
            VStack(alignment: .leading, spacing: 6) {
                editorLabel("Tipo de guía")
                Picker("Tipo de guía", selection: $draft.tipoGuia) {
                    Text("Aprendizaje").tag("aprendizaje")
                    Text("Refuerzo").tag("refuerzo")
                    Text("Ejercitación").tag("ejercitacion")
                    Text("Evaluación formativa").tag("evaluacion_formativa")
                }.pickerStyle(.menu).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                editorLabel("Estado")
                Picker("Estado", selection: $draft.estado) {
                    Text("Borrador").tag("borrador")
                    Text("Lista").tag("lista")
                    Text("Archivada").tag("archivada")
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack { editorLabel("Tiempo estimado"); Spacer(); Text("\(draft.tiempoMinutos) min").font(.caption.weight(.black)).foregroundStyle(EPTheme.primary) }
                Slider(value: Binding(get: { Double(draft.tiempoMinutos) }, set: { draft.tiempoMinutos = Int($0) }), in: 10...180, step: 5)
                    .tint(EPTheme.primary)
            }
            VStack(alignment: .leading, spacing: 6) {
                editorLabel("Objetivo")
                TextField("Qué debe lograr el estudiante", text: $draft.objetivo, axis: .vertical)
                    .lineLimit(3...7).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var instructionsCard: some View {
        editorCard(title: "Instrucciones para el estudiante", icon: "list.number") {
            ForEach(Array(draft.instrucciones.indices), id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)").font(.caption.weight(.black)).foregroundStyle(EPTheme.primary)
                        .frame(width: 24, height: 24).background(EPTheme.primary.opacity(0.1), in: Circle())
                    TextField("Instrucción", text: instructionBinding(index), axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { draft.instrucciones.remove(at: index) } label: {
                        Image(systemName: "trash").font(.caption.weight(.bold))
                    }.disabled(draft.instrucciones.count <= 1)
                }
            }
            Button {
                draft.instrucciones.append("")
            } label: {
                Label("Agregar instrucción", systemImage: "plus.circle.fill").font(.caption.weight(.black))
            }
        }
    }

    private var preservationNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkered").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Edición compatible con la web").font(.caption.weight(.black))
                Text("El currículo y los campos desconocidos permanecen intactos. Bloques y actividades conocidas se fusionan sobre el documento más reciente; lo no tocado no se normaliza.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(12).background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func editorCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: icon).font(.subheadline.weight(.black)).foregroundStyle(EPTheme.primary)
                content()
            }
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            editorLabel(label)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorLabel(_ value: String) -> some View {
        Text(value.uppercased()).font(.system(size: 9.5, weight: .black)).tracking(0.7).foregroundStyle(.secondary)
    }

    private func instructionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft.instrucciones.indices.contains(index) ? draft.instrucciones[index] : "" },
            set: { if draft.instrucciones.indices.contains(index) { draft.instrucciones[index] = $0 } }
        )
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<GuiaEditorDraft, String>) -> Binding<String?> {
        Binding(
            get: {
                let value = draft[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            },
            set: { draft[keyPath: keyPath] = $0 ?? "" }
        )
    }

    private func insertFromBank(_ entry: ItemBankEntry) -> Bool {
        if draft.secciones.isEmpty {
            draft.secciones.append(.nueva(order: 1))
        }
        guard let index = draft.secciones.indices.last,
              let activity = entry.guiaActivityDraft(
                number: draft.secciones[index].actividades.filter { !$0.isDeleted }.count + 1
              ) else { return false }
        draft.secciones[index].actividades.append(activity)
        itemBankMessageIsError = false
        itemBankMessage = "Actividad insertada desde el banco."
        return true
    }

    @MainActor
    private func saveToBank(_ activity: GuiaActivityDraft) async {
        do {
            _ = try await itemBankRepository.save(
                activity: activity,
                asignatura: draft.asignatura,
                curso: draft.curso,
                author: draft.docenteNombre
            )
            itemBankMessageIsError = false
            itemBankMessage = "Actividad guardada en el banco compartido."
        } catch {
            itemBankMessageIsError = true
            itemBankMessage = error.localizedDescription
        }
    }

    private func load() async {
        if nivelMapping.isEmpty || school == .empty {
            async let dashboardTask: DashboardSnapshot? = try? await dashboardRepository.fetchDashboard()
            async let schoolTask: InfoColegio? = try? await dashboardRepository.fetchExportSchool(scope: scope)
            if let snapshot = await dashboardTask { nivelMapping = snapshot.nivelMapping }
            if let exportSchool = await schoolTask { school = exportSchool }
        }
        guard let guiaId, draft.id == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let guide = try await repository.cargarGuia(id: guiaId, scope: scope) else {
                errorMessage = "La guía ya no existe o no pertenece al colegio activo."
                return
            }
            let loaded = GuiaEditorDraft.from(guide)
            sourceGuide = guide
            draft = loaded; savedDraft = loaded
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard draft.isValid, !isSaving else { return }
        let previousMediaPaths = savedDraft.ownedMediaStoragePaths
        isSaving = true; errorMessage = nil; saveSucceeded = false
        defer { isSaving = false }
        do {
            let id = try await repository.guardarGuiaEditor(draft, scope: scope)
            if let refreshed = try await repository.cargarGuia(id: id, scope: scope) {
                let canonical = GuiaEditorDraft.from(refreshed)
                sourceGuide = refreshed
                draft = canonical
                savedDraft = canonical
                await mediaRepository.eliminarMediosHuerfanos(
                    documentId: id,
                    folder: .guias,
                    previousPaths: previousMediaPaths,
                    currentPaths: canonical.ownedMediaStoragePaths
                )
            } else {
                draft.id = id
                savedDraft = draft
            }
            saveSucceeded = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "No se pudo guardar la guía. \(error.localizedDescription)"
        }
    }

    private func beginExport(_ mode: GuiaPDFMode, formatOverride: ExportFormat? = nil) {
        Task { await export(mode, formatOverride: formatOverride) }
    }

    private func export(_ mode: GuiaPDFMode, formatOverride: ExportFormat?) async {
        guard draft.isValid, exportingMode == nil else { return }
        exportingMode = mode
        exportErrorMessage = nil
        defer { exportingMode = nil }
        do {
            let preview = repository.prepararGuiaParaExportar(draft, scope: scope, base: sourceGuide)
            exportArtifact = try await pdfExporter.export(
                guide: preview,
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
