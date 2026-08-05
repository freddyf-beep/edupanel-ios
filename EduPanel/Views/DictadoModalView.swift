import SwiftUI

struct VoiceNoteStudentOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct VoiceNoteLinkOption: Identifiable, Hashable {
    var id: String {
        let classID = context.classID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dateKey = context.dateKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return classID.isEmpty ? title : "\(classID)::\(dateKey)"
    }
    let title: String
    let subtitle: String
    let context: VoiceNoteContext
    let students: [VoiceNoteStudentOption]
}

struct DictadoModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var dictadoService: DictadoService
    @State private var draft: VoiceNoteDraft
    @State private var copiedNotice = false
    @State private var didLoadInitialText = false
    @State private var isSaving = false
    @State private var isAutosaving = false
    @State private var saveErrorMessage: String?
    @State private var savedAt: Date?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var showClearConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showsGuidedContext: Bool
    @State private var shouldPersistOnDisappear = true
    @State private var editGeneration = 0
    @State private var canSaveAsNewNote = false

    private let ownerID: String?
    private let initialText: String
    private let initialContext: VoiceNoteContext
    private let restoresStoredDraft: Bool
    private let startsAutomatically: Bool
    private let linkOptions: [VoiceNoteLinkOption]
    private let draftStore: VoiceNoteDraftStore
    private let linkAction: ((VoiceNoteDraft) async throws -> Void)?

    init(
        contextualStrings: [String] = [],
        initialText: String = "",
        ownerID: String? = nil,
        mode: VoiceDictationMode = .guiado,
        context: VoiceNoteContext = VoiceNoteContext(),
        initialDraft: VoiceNoteDraft? = nil,
        linkOptions: [VoiceNoteLinkOption] = [],
        startsAutomatically: Bool = false,
        draftStore: VoiceNoteDraftStore = .shared,
        linkAction: ((VoiceNoteDraft) async throws -> Void)? = nil
    ) {
        let startingDraft = initialDraft ?? VoiceNoteDraft(
            mode: mode,
            text: initialText,
            status: context.isLinkedToClass ? .pendienteSincronizacion : .sinVincular,
            context: context
        )
        _dictadoService = State(initialValue: DictadoService(
            contextualStrings: contextualStrings + startingDraft.context.safeContextualStrings
        ))
        _draft = State(initialValue: startingDraft)
        _showsGuidedContext = State(initialValue: startingDraft.mode == .guiado)
        self.ownerID = ownerID
        self.initialText = startingDraft.text
        self.initialContext = startingDraft.context
        self.restoresStoredDraft = initialDraft != nil
        self.startsAutomatically = startsAutomatically
        self.linkOptions = linkOptions
        self.draftStore = draftStore
        self.linkAction = linkAction
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    contextStatus

                    if draft.mode == .guiado {
                        guidedContext
                    } else if !linkOptions.isEmpty {
                        classSelector
                    }

                    transcriptEditor
                    recordingStatus
                    microphoneControl
                    privacyNotice
                    secondaryActions
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .disabled(isSaving)
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(draft.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task {
            guard !didLoadInitialText else { return }
            if !initialText.isEmpty {
                dictadoService.updateText(initialText)
            }
            didLoadInitialText = true
            if startsAutomatically && dictadoService.transcribedText.isEmpty {
                dictadoService.startDictado()
            }
        }
        .onChange(of: dictadoService.transcribedText) { _, value in
            guard value != draft.text else { return }
            draft.text = value
            scheduleAutosave()
        }
        .onChange(of: draft.context) { _, _ in
            dictadoService.updateContextualStrings(draft.context.safeContextualStrings)
            scheduleAutosave()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, !isSaving else { return }
            persistBeforeLeaving()
        }
        .onDisappear {
            dictadoService.stopDictado()
            autosaveTask?.cancel()
            if shouldPersistOnDisappear && !isSaving {
                persistBeforeLeaving()
            }
        }
        // Cerrar pasa siempre por `closeKeepingDraft`, que puede mantener la
        // hoja abierta si el almacenamiento local falla.
        .interactiveDismissDisabled(true)
        .confirmationDialog(
            "¿Limpiar la transcripción?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Limpiar", role: .destructive) {
                clearTranscript()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El texto se quitará también del borrador local.")
        }
        .confirmationDialog(
            "¿Descartar esta nota?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive) {
                discardAndDismiss()
            }
            Button("Seguir editando", role: .cancel) {}
        } message: {
            Text("Esta acción elimina el borrador guardado en este dispositivo.")
        }
    }

    private var header: some View {
        VStack(spacing: 5) {
            Image(systemName: draft.mode == .rapido ? "mic.badge.plus" : "waveform.badge.magnifyingglass")
                .font(.title.weight(.semibold))
                .foregroundStyle(EPTheme.primary)
                .accessibilityHidden(true)

            Text(
                draft.mode == .rapido
                    ? "Habla ahora. Puedes ordenar o vincular la nota después."
                    : "El contexto es opcional: nunca bloqueará el guardado."
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contextStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: draft.context.isLinkedToClass ? "link.circle.fill" : "tray.full.fill")
                .foregroundStyle(draft.context.isLinkedToClass ? .green : .orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(contextStatusTitle)
                    .font(.subheadline.weight(.bold))
                Text(draft.context.contextLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if isAutosaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Guardando borrador")
            } else if savedAt != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Borrador guardado")
            }
        }
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var guidedContext: some View {
        DisclosureGroup(isExpanded: $showsGuidedContext) {
            VStack(alignment: .leading, spacing: 14) {
                classSelector

                Picker("Tipo de observación", selection: $draft.context.observationScope) {
                    ForEach(VoiceObservationScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if draft.context.observationScope != .general, !availableStudents.isEmpty {
                    studentSelector
                }

                TextField("Tema", text: optionalText(\.topic))
                    .textFieldStyle(.roundedBorder)
                TextField("Tipo de observación", text: optionalText(\.observationType))
                    .textFieldStyle(.roundedBorder)
                TextField("Estado o resultado", text: optionalText(\.outcome), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                TextField("Próximo paso", text: optionalText(\.nextStep), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                TextField("Resumen de la clase", text: optionalText(\.classSummary), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
            }
            .padding(.top, 12)
        } label: {
            Label("Contexto opcional", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var classSelector: some View {
        Menu {
            Button {
                unlinkContext()
            } label: {
                Label("Sin vincular", systemImage: draft.context.isLinkedToClass ? "tray" : "checkmark")
            }

            if !linkOptions.isEmpty {
                Divider()
                if linkOptions.count > 12 {
                    ForEach(linkOptionDateKeys, id: \.self) { dateKey in
                        Menu(linkDateTitle(dateKey)) {
                            ForEach(linkOptions.filter { $0.context.dateKey == dateKey }) { option in
                                linkOptionButton(option)
                            }
                        }
                    }
                } else {
                    ForEach(linkOptions) { option in
                        linkOptionButton(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(EPTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clase o bloque")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(selectedLinkOption?.title ?? draft.context.classTitle ?? "Elegir después")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Clase o bloque")
        .accessibilityValue(selectedLinkOption?.title ?? draft.context.classTitle ?? "Sin vincular")
    }

    private var linkOptionDateKeys: [String] {
        linkOptions.reduce(into: [String]()) { result, option in
            let key = option.context.dateKey ?? "Sin fecha"
            if !result.contains(key) { result.append(key) }
        }
    }

    private func linkDateTitle(_ dateKey: String) -> String {
        guard let date = AttendanceDate.parse(dateKey) else { return dateKey }
        return date.formatted(
            .dateTime
                .locale(Locale(identifier: "es_CL"))
                .weekday(.wide)
                .day()
                .month(.abbreviated)
        )
    }

    private func linkOptionButton(_ option: VoiceNoteLinkOption) -> some View {
        Button {
            select(option)
        } label: {
            Label(
                option.title,
                systemImage: selectedLinkOption?.id == option.id ? "checkmark" : "calendar"
            )
        }
    }

    private var studentSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.context.observationScope == .individual ? "Estudiante" : "Estudiantes")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            ReplicaFlowLayout(spacing: 7) {
                ForEach(availableStudents) { student in
                    let isSelected = draft.context.studentIDs.contains(student.id)
                    Button {
                        toggleStudent(student.id)
                    } label: {
                        Label(student.name, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSelected ? EPTheme.primary : .primary)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(
                                isSelected ? EPTheme.primary.opacity(0.12) : Color(.tertiarySystemGroupedBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isSelected ? "Seleccionado" : "No seleccionado")
                }
            }
        }
    }

    private var transcriptEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            dictadoService.state.isRecording ? EPTheme.primary.opacity(0.55) : Color(.separator).opacity(0.18),
                            lineWidth: dictadoService.state.isRecording ? 2 : 1
                        )
                }

            TextEditor(text: Binding(
                get: { dictadoService.transcribedText },
                set: { dictadoService.updateText($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(12)
            .accessibilityLabel("Transcripción editable")
            .accessibilityHint("Puedes corregir el texto antes o después de dictar")

            if dictadoService.transcribedText.isEmpty {
                Text(dictadoService.state.isRecording ? "Escuchando…" : "Tu nota aparecerá aquí. También puedes escribirla.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private var recordingStatus: some View {
        if let saveErrorMessage {
            VStack(spacing: 9) {
                Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if canSaveAsNewNote {
                    Button("Guardar como nota nueva") {
                        saveWithNewIdentity()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EPTheme.primary)
                }
            }
        } else if case .error(let message) = dictadoService.state {
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.bold))
            }
        } else if dictadoService.state.isRecording {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule()
                            .fill(EPTheme.primary)
                            .frame(
                                width: 4,
                                height: max(8, CGFloat(dictadoService.audioLevel * Float(15 + (index % 3) * 10)))
                            )
                            .animation(.easeOut(duration: 0.12), value: dictadoService.audioLevel)
                    }
                }
                .frame(height: 32)
                .accessibilityHidden(true)

                Label("Grabando", systemImage: "waveform")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EPTheme.primary)
                    .accessibilityLabel("Dictado en curso")
            }
        } else if dictadoService.state == .requestingPermission {
            ProgressView("Solicitando permisos…")
                .font(.footnote)
        }
    }

    private var microphoneControl: some View {
        Button {
            withAnimation(EPTheme.spring) {
                dictadoService.toggleDictado()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: dictadoService.state.isRecording ? "pause.fill" : "mic.fill")
                    .font(.title2.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(dictadoService.state.isRecording ? 0.2 : 0.9), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(dictadoService.state.isRecording ? "Pausar" : (dictadoService.transcribedText.isEmpty ? "Comenzar a dictar" : "Continuar dictado"))
                        .font(.headline)
                    Text(dictadoService.state.isRecording ? "El texto queda guardado" : "No necesitas completar el contexto")
                        .font(.caption)
                        .opacity(0.82)
                }
                Spacer()
            }
            .foregroundStyle(dictadoService.state.isRecording ? .white : EPTheme.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                dictadoService.state.isRecording ? AnyShapeStyle(EPTheme.heroGradient) : AnyShapeStyle(EPTheme.primary.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(dictadoService.state == .requestingPermission)
        .sensoryFeedback(.impact, trigger: dictadoService.state.isRecording)
        .accessibilityLabel(dictadoService.state.isRecording ? "Pausar dictado" : "Comenzar o continuar dictado")
        .accessibilityHint("La transcripción se conserva como borrador local")
    }

    private var privacyNotice: some View {
        VStack(spacing: 6) {
            Label(dictadoService.privacyDescription, systemImage: "hand.raised.fill")
            Text("EduPanel guarda texto y contexto mínimo en este dispositivo y no conserva audio. No añade nombres ni datos PIE como contexto; Apple puede procesar lo que pronuncies según los ajustes del dispositivo.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            Button {
                showClearConfirmation = true
            } label: {
                Label("Limpiar", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(dictadoService.transcribedText.isEmpty)

            Button {
                UIPasteboard.general.string = dictadoService.transcribedText
                copiedNotice = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copiedNotice = false
                }
            } label: {
                Label(copiedNotice ? "Copiado" : "Copiar", systemImage: copiedNotice ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(copiedNotice ? .green : EPTheme.primary)
            .disabled(dictadoService.transcribedText.isEmpty)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cerrar") {
                closeKeepingDraft()
            }
            .disabled(isSaving)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(role: .destructive) {
                showDiscardConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(isSaving || !hasDraftWorthSaving)
            .accessibilityLabel("Descartar nota")

            Button(isSaving ? "Guardando…" : "Guardar") {
                finish()
            }
            .fontWeight(.bold)
            .disabled(isSaving || !hasDraftWorthSaving)
            .accessibilityLabel(canLinkOnFinish ? "Guardar en clase" : "Guardar borrador")
        }
    }

    private var selectedLinkOption: VoiceNoteLinkOption? {
        guard let classID = draft.context.classID else { return nil }
        return linkOptions.first {
            $0.context.classID == classID && $0.context.dateKey == draft.context.dateKey
        }
    }

    private var availableStudents: [VoiceNoteStudentOption] {
        selectedLinkOption?.students ?? []
    }

    private var canLinkOnFinish: Bool {
        draft.context.isLinkedToClass && linkAction != nil
    }

    private var hasDraftWorthSaving: Bool {
        let value = currentDraft()
        guard value.hasMeaningfulContent else { return false }
        guard !restoresStoredDraft else { return true }
        return value.text != initialText || value.context != initialContext
    }

    private var contextStatusTitle: String {
        if canLinkOnFinish { return "Vinculada al guardar" }
        if draft.context.isLinkedToClass { return "Lista para vincular cuando vuelvan tus datos" }
        return "Se guardará en Notas sin vincular"
    }

    private func optionalText(_ keyPath: WritableKeyPath<VoiceNoteContext, String?>) -> Binding<String> {
        Binding(
            get: { draft.context[keyPath: keyPath] ?? "" },
            set: { draft.context[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func select(_ option: VoiceNoteLinkOption) {
        let previous = draft.context
        var next = option.context
        next.observationScope = previous.observationScope
        next.topic = previous.topic
        next.observationType = previous.observationType
        next.outcome = previous.outcome
        next.nextStep = previous.nextStep
        next.classSummary = previous.classSummary
        next.studentIDs = previous.courseID == next.courseID ? previous.studentIDs : []
        draft.context = next
        draft.status = .pendienteSincronizacion
    }

    private func unlinkContext() {
        draft.context.courseID = nil
        draft.context.courseName = nil
        draft.context.courseKind = nil
        draft.context.subjectID = nil
        draft.context.subjectName = nil
        draft.context.classID = nil
        draft.context.classTitle = nil
        draft.context.dateKey = nil
        draft.context.unitID = nil
        draft.context.unitName = nil
        draft.context.activityID = nil
        draft.context.studentIDs = []
        draft.status = .sinVincular
    }

    private func clearTranscript() {
        editGeneration &+= 1
        autosaveTask?.cancel()
        saveErrorMessage = nil
        canSaveAsNewNote = false
        guard let ownerID else {
            dictadoService.clearText()
            savedAt = nil
            return
        }

        isSaving = true
        let id = draft.id
        Task {
            do {
                try await draftStore.delete(id: id, ownerID: ownerID)
                dictadoService.clearText()
                savedAt = nil
                isSaving = false
            } catch {
                saveErrorMessage = "No pudimos eliminar el borrador local: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private func toggleStudent(_ id: String) {
        if draft.context.observationScope == .individual {
            draft.context.studentIDs = draft.context.studentIDs == [id] ? [] : [id]
        } else if draft.context.studentIDs.contains(id) {
            draft.context.studentIDs.removeAll { $0 == id }
        } else {
            draft.context.studentIDs.append(id)
        }
    }

    private func scheduleAutosave() {
        guard ownerID != nil, didLoadInitialText else { return }
        editGeneration &+= 1
        let generation = editGeneration
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard editGeneration == generation else { return }
            await persistDraft(showProgress: true, expectedGeneration: generation)
        }
    }

    private func persistBeforeLeaving() {
        guard let ownerID, hasDraftWorthSaving else { return }
        let snapshot = currentDraft()
        Task {
            do {
                _ = try await draftStore.upsert(snapshot, ownerID: ownerID)
            } catch {
                saveErrorMessage = "No pudimos guardar el borrador local: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func persistDraft(showProgress: Bool, expectedGeneration: Int) async {
        guard let ownerID, hasDraftWorthSaving, editGeneration == expectedGeneration else { return }
        if showProgress { isAutosaving = true }
        let snapshot = currentDraft()
        do {
            let stored = try await draftStore.upsert(snapshot, ownerID: ownerID)
            if editGeneration == expectedGeneration {
                savedAt = stored.updatedAt
                saveErrorMessage = nil
            }
        } catch {
            if editGeneration == expectedGeneration {
                saveErrorMessage = "No pudimos guardar el borrador local: \(error.localizedDescription)"
            }
        }
        if editGeneration == expectedGeneration { isAutosaving = false }
    }

    private func currentDraft() -> VoiceNoteDraft {
        var value = draft
        value.text = dictadoService.transcribedText
        if value.context.isLinkedToClass, value.status != .vinculada {
            value.status = .pendienteSincronizacion
        } else if !value.context.isLinkedToClass {
            value.status = .sinVincular
        }
        return value
    }

    private func finish() {
        dictadoService.stopDictado()
        autosaveTask?.cancel()
        guard hasDraftWorthSaving else { return }
        isSaving = true
        saveErrorMessage = nil
        canSaveAsNewNote = false

        Task {
            var value = currentDraft()
            do {
                if let ownerID {
                    value = try await draftStore.upsert(value, ownerID: ownerID)
                    draft = value
                }

                if value.context.isLinkedToClass, let linkAction {
                    try await linkAction(value)
                    value.status = .vinculada
                    if let ownerID {
                        // El enlace remoto ya terminó. La limpieza local no debe
                        // convertir un éxito en un reintento que duplique la nota.
                        _ = try? await draftStore.upsert(value, ownerID: ownerID)
                        try? await draftStore.delete(id: value.id, ownerID: ownerID)
                    }
                }
                shouldPersistOnDisappear = false
                dismiss()
            } catch {
                var pending = value
                pending.status = pending.context.isLinkedToClass ? .pendienteSincronizacion : .sinVincular
                if let ownerID { _ = try? await draftStore.upsert(pending, ownerID: ownerID) }
                draft = pending
                saveErrorMessage = error.localizedDescription
                canSaveAsNewNote = (error as? VoiceNoteLinkingError) == .contentChanged
                isSaving = false
            }
        }
    }

    private func saveWithNewIdentity() {
        dictadoService.stopDictado()
        autosaveTask?.cancel()
        guard let ownerID else {
            saveErrorMessage = "No hay una sesión válida para guardar esta nota."
            return
        }

        isSaving = true
        let snapshot = currentDraft()
        Task {
            do {
                let replacement = try await draftStore.reidentify(snapshot, ownerID: ownerID)
                draft = replacement
                dictadoService.updateText(replacement.text)
                editGeneration &+= 1
                savedAt = replacement.updatedAt
                saveErrorMessage = nil
                canSaveAsNewNote = false
                isSaving = false
                finish()
            } catch {
                saveErrorMessage = "No pudimos crear la nueva nota: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private func closeKeepingDraft() {
        dictadoService.stopDictado()
        autosaveTask?.cancel()
        guard hasDraftWorthSaving else {
            shouldPersistOnDisappear = false
            dismiss()
            return
        }
        guard let ownerID else {
            saveErrorMessage = "No hay una sesión válida para guardar esta nota."
            return
        }

        isSaving = true
        let snapshot = currentDraft()
        Task {
            do {
                _ = try await draftStore.upsert(snapshot, ownerID: ownerID)
                shouldPersistOnDisappear = false
                dismiss()
            } catch {
                saveErrorMessage = "No pudimos guardar el borrador local: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private func discardAndDismiss() {
        dictadoService.stopDictado()
        editGeneration &+= 1
        autosaveTask?.cancel()
        guard let ownerID else {
            shouldPersistOnDisappear = false
            dismiss()
            return
        }

        isSaving = true
        let id = draft.id
        Task {
            do {
                try await draftStore.delete(id: id, ownerID: ownerID)
                shouldPersistOnDisappear = false
                dismiss()
            } catch {
                saveErrorMessage = "No pudimos descartar el borrador: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

struct VoiceNotesInboxView: View {
    @Environment(\.dismiss) private var dismiss

    let ownerID: String
    let linkOptions: [VoiceNoteLinkOption]
    let linkAction: ((VoiceNoteDraft) async throws -> Void)?

    @State private var drafts: [VoiceNoteDraft] = []
    @State private var selectedDraft: VoiceNoteDraft?
    @State private var pendingDelete: VoiceNoteDraft?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let draftStore = VoiceNoteDraftStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && drafts.isEmpty {
                    ProgressView("Cargando notas…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, drafts.isEmpty {
                    ContentUnavailableView {
                        Label("No pudimos abrir tus notas", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Reintentar") { Task { await load() } }
                    }
                } else if drafts.isEmpty {
                    ContentUnavailableView(
                        "Sin notas pendientes",
                        systemImage: "tray",
                        description: Text("Los dictados sin clase aparecerán aquí y podrás vincularlos después.")
                    )
                } else {
                    List {
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        ForEach(drafts) { draft in
                            Button {
                                selectedDraft = draft
                            } label: {
                                VoiceNoteDraftRow(draft: draft)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Eliminar", role: .destructive) {
                                    pendingDelete = draft
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Notas sin vincular")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedDraft, onDismiss: {
            Task { await load() }
        }) { item in
            DictadoModalView(
                ownerID: ownerID,
                mode: item.mode,
                initialDraft: item,
                linkOptions: linkOptions,
                linkAction: linkAction
            )
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "¿Eliminar esta nota?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                guard let pendingDelete else { return }
                Task { await delete(pendingDelete) }
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            let stored = try await draftStore.load(ownerID: ownerID)
            drafts = stored.filter { $0.status != .vinculada }
            for linked in stored where linked.status == .vinculada {
                try? await draftStore.delete(id: linked.id, ownerID: ownerID)
            }
            errorMessage = nil
        } catch {
            errorMessage = "No pudimos abrir las notas: \(error.localizedDescription)"
        }
        isLoading = false
    }

    @MainActor
    private func delete(_ draft: VoiceNoteDraft) async {
        do {
            try await draftStore.delete(id: draft.id, ownerID: ownerID)
            pendingDelete = nil
            await load()
        } catch {
            errorMessage = "No pudimos eliminar la nota: \(error.localizedDescription)"
        }
    }
}

private struct VoiceNoteDraftRow: View {
    let draft: VoiceNoteDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(draft.mode.title, systemImage: draft.mode == .rapido ? "mic.fill" : "list.bullet.clipboard")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EPTheme.primary)
                Spacer()
                Text(draft.status.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(draft.status == .pendienteSincronizacion ? .orange : .secondary)
            }

            Text(draft.text)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack {
                Text(draft.context.contextLabel)
                Spacer()
                Text(draft.updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre la nota para editarla o vincularla")
    }
}
