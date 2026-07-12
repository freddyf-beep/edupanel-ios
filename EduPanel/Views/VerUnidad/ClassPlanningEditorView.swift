import SwiftUI

@MainActor
struct ClassPlanningEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: VerUnidadViewModel
    let classNumber: Int

    private let originalActivity: ActividadClase

    @State private var draft: ActividadClase
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingDiscardConfirmation = false
    @State private var allowsFormattingSimplification = false
    @State private var contextWasEdited = false

    private var hasChanges: Bool {
        draft != originalActivity
    }

    private var requiresFormattingConsent: Bool {
        let editedFields = [
            (originalActivity.objetivo, draft.objetivo),
            (originalActivity.inicio, draft.inicio),
            (originalActivity.desarrollo, draft.desarrollo),
            (originalActivity.cierre, draft.cierre),
            (originalActivity.adecuacion, draft.adecuacion)
        ]

        return editedFields.contains { original, edited in
            original != edited && containsAdvancedHTML(original)
        }
    }

    private var linkedOAs: [OAEditado] {
        guard let unit = viewModel.verUnidad else { return [] }
        return unit.oas.filter { oa in
            draft.oaIds.contains { matchesOAId($0, oa: oa) }
        }
    }

    private var skillSuggestions: [String] {
        viewModel.verUnidad?.habilidades
            .filter(\.seleccionado)
            .map(\.texto) ?? []
    }

    private var attitudeSuggestions: [String] {
        viewModel.verUnidad?.actitudes
            .filter(\.seleccionado)
            .map(\.texto) ?? []
    }

    private var materialSuggestions: [String] {
        viewModel.verUnidad?.recursosMaterialesUnidad ?? []
    }

    init(viewModel: VerUnidadViewModel, classNumber: Int) {
        self.viewModel = viewModel
        self.classNumber = classNumber

        let activity = viewModel.clasesActividades[classNumber]
            ?? viewModel.activityTemplate(for: classNumber)
        originalActivity = activity
        _draft = State(initialValue: activity)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ClassEditorSummaryCard(activity: $draft, classNumber: classNumber)
                    if requiresFormattingConsent {
                        ClassFormattingWarning(allowsSimplification: $allowsFormattingSimplification)
                    }
                    ClassOAEditorSection(
                        oas: linkedOAs,
                        rawOAIds: draft.oaIds,
                        selection: { oa in indicatorSelection(for: oa) }
                    )
                    ClassPlanEditorSection(activity: $draft)
                    ClassContextEditorSection(
                        context: contextBinding,
                        adaptation: $draft.adecuacion
                    )
                    ClassCurriculumEditorSection(
                        activity: $draft,
                        skillSuggestions: skillSuggestions,
                        attitudeSuggestions: attitudeSuggestions,
                        materialSuggestions: materialSuggestions
                    )
                    ClassPreservedDataSection(activity: draft)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(EPTheme.background)
            .navigationTitle("Planificar clase \(classNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar { editorToolbar }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .confirmationDialog(
            "Descartar cambios",
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive) { dismiss() }
            Button("Seguir editando", role: .cancel) {}
        } message: {
            Text("Los cambios de esta clase no se han guardado.")
        }
        .alert("No se pudo guardar", isPresented: errorBinding) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Intenta nuevamente.")
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancelar", action: cancel)
                .disabled(isSaving)
                .accessibilityIdentifier("cancelar-editor-clase")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button(action: save) {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Guardar")
                        .fontWeight(.bold)
                }
            }
            .disabled(
                isSaving
                || viewModel.isSaving
                || !hasChanges
                || (requiresFormattingConsent && !allowsFormattingSimplification)
            )
            .accessibilityIdentifier("guardar-editor-clase")
        }
    }

    private var contextBinding: Binding<String> {
        Binding(
            get: { draft.contextoProfesor ?? "" },
            set: {
                draft.contextoProfesor = $0
                contextWasEdited = true
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }

    private func indicatorSelection(for oa: OAEditado) -> Binding<[String]> {
        Binding(
            get: {
                let key = indicatorStorageKey(for: oa)
                if let stored = draft.indicadoresPorOa?[key] {
                    return stored
                }
                return oa.indicadores.filter(\.seleccionado).map(\.id)
            },
            set: { values in
                var map = draft.indicadoresPorOa ?? [:]
                map[indicatorStorageKey(for: oa)] = values
                draft.indicadoresPorOa = map
            }
        )
    }

    private func indicatorStorageKey(for oa: OAEditado) -> String {
        guard let map = draft.indicadoresPorOa else { return oa.id }

        var candidates = [oa.id]
        if let number = oa.numero {
            candidates += ["OA\(number)", String(number), "oa-\(number)", "oa_\(number)"]
        }

        if let exact = candidates.first(where: { map[$0] != nil }) {
            return exact
        }

        let normalizedCandidates = Set(candidates.map(normalizePedagogicalId))
        return map.keys.first(where: { normalizedCandidates.contains(normalizePedagogicalId($0)) })
            ?? oa.id
    }

    private func cancel() {
        if hasChanges {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard !isSaving, !viewModel.isSaving else { return }
        guard !requiresFormattingConsent || allowsFormattingSimplification else { return }
        saveDraft()
    }

    private func saveDraft() {
        isSaving = true
        errorMessage = nil

        var activity = normalizedDraft()
        activity.sincronizada = false

        do {
            try viewModel.saveActivity(original: originalActivity, updated: activity)
            draft = viewModel.clasesActividades[classNumber] ?? activity
            isSaving = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func normalizedDraft() -> ActividadClase {
        var activity = draft
        activity.habilidades = normalizedItems(activity.habilidades)
        activity.actitudes = normalizedItems(activity.actitudes)
        activity.materiales = normalizedItems(activity.materiales)
        activity.tics = normalizedItems(activity.tics)

        if contextWasEdited {
            activity.contextoProfesor = RichTextHTML.plainText(from: activity.contextoProfesor ?? "")
        } else {
            activity.contextoProfesor = originalActivity.contextoProfesor
        }
        return activity
    }

    private func normalizedItems(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "es_CL")
            )
            guard !clean.isEmpty, seen.insert(key).inserted else { return nil }
            return clean
        }
    }

    private func matchesOAId(_ value: String, oa: OAEditado) -> Bool {
        var candidates = [oa.id]
        if let number = oa.numero {
            candidates += ["OA\(number)", String(number), "oa-\(number)", "oa_\(number)"]
        }
        let normalized = normalizePedagogicalId(value)
        return candidates.contains(value)
            || candidates.map(normalizePedagogicalId).contains(normalized)
    }

    private func normalizePedagogicalId(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func containsAdvancedHTML(_ value: String) -> Bool {
        let withoutSimpleBlocks = value.replacingOccurrences(
            of: "</?(p|ul|li)>|<br\\s*/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return withoutSimpleBlocks.range(
            of: "<[^>]+>",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

private struct ClassFormattingWarning: View {
    @Binding var allowsSimplification: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Esta clase contiene formato enriquecido de la web", systemImage: "text.badge.exclamationmark")
                .font(.footnote.weight(.black))
                .foregroundStyle(.orange)

            Text("Al guardar los campos editados, títulos, negritas u otros estilos avanzados se convertirán a texto y listas simples. Los campos que no cambies conservarán su HTML original.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Toggle("Permitir formato simplificado", isOn: $allowsSimplification)
                .font(.caption.weight(.bold))
                .tint(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ClassEditorSummaryCard: View {
    @Binding var activity: ActividadClase

    let classNumber: Int

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Clase \(classNumber)",
                    subtitle: activity.fecha.isEmpty ? "Sin fecha programada" : activity.fecha,
                    icon: "calendar.badge.clock"
                )

                HStack(spacing: 10) {
                    Text("Estado")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("Estado", selection: $activity.estado) {
                        Text("No planificada").tag("no_planificada")
                        Text("Planificada").tag("planificada")
                        Text("Realizada").tag("realizada")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(EPTheme.primary)
                }
            }
        }
    }
}

private struct ClassOAEditorSection: View {
    let oas: [OAEditado]
    let rawOAIds: [String]
    let selection: (OAEditado) -> Binding<[String]>

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Objetivos vinculados",
                    subtitle: "La asignaci\u{00F3}n de OA se administra en Cronograma. Aqu\u{00ED} puedes elegir sus indicadores.",
                    icon: "tag.fill"
                )

                if oas.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Esta clase no tiene OA vinculados", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.orange)

                        if !rawOAIds.isEmpty {
                            ReplicaFlowLayout(spacing: 6) {
                                ForEach(rawOAIds, id: \.self) { oaId in
                                    EPStatusPill(text: oaId, tint: .orange)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(oas) { oa in
                        ClassOAIndicatorPicker(oa: oa, selectedValues: selection(oa))
                    }
                }
            }
        }
    }
}

private struct ClassOAIndicatorPicker: View {
    let oa: OAEditado

    @Binding var selectedValues: [String]

    private var customSelectedValues: [String] {
        let known = Set(oa.indicadores.flatMap { [$0.id, $0.texto] }.map { normalizedKey($0) })
        return selectedValues.filter { !known.contains(normalizedKey($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                EPStatusPill(text: oa.numero.map { "OA \($0)" } ?? oa.id, tint: EPTheme.primary)
                Text(oa.descripcion)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if oa.indicadores.isEmpty && customSelectedValues.isEmpty {
                Text("Sin indicadores disponibles para este OA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !oa.indicadores.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(oa.indicadores) { indicator in
                            Button {
                                toggle(indicator)
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: isSelected(indicator) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected(indicator) ? EPTheme.primary : .secondary)
                                    Text(indicator.texto)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    isSelected(indicator) ? EPTheme.primary.opacity(0.08) : EPTheme.subtle,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !customSelectedValues.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Indicadores personalizados")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ReplicaFlowLayout(spacing: 6) {
                            ForEach(customSelectedValues, id: \.self) { value in
                                HStack(spacing: 5) {
                                    Text(value)
                                        .font(.caption2.weight(.bold))
                                    Button {
                                        selectedValues.removeAll { $0 == value }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Quitar indicador \(value)")
                                }
                                .foregroundStyle(EPTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(EPTheme.primary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func isSelected(_ indicator: IndicadorEditado) -> Bool {
        selectedValues.contains(indicator.id) || selectedValues.contains(indicator.texto)
    }

    private func toggle(_ indicator: IndicadorEditado) {
        if isSelected(indicator) {
            selectedValues.removeAll { $0 == indicator.id || $0 == indicator.texto }
        } else {
            selectedValues.append(indicator.id)
        }
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

private struct ClassPlanEditorSection: View {
    @Binding var activity: ActividadClase

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 16) {
                EPSectionHeader(
                    title: "Plan de la clase",
                    subtitle: "Redacta el objetivo y los tres momentos de la sesi\u{00F3}n.",
                    icon: "text.book.closed.fill"
                )

                RichTextEditor(
                    title: "Objetivo de la clase",
                    placeholder: "\u{00BF}Qu\u{00E9} lograr\u{00E1}n los estudiantes al terminar?",
                    html: $activity.objetivo,
                    minHeight: 88
                )

                RichTextEditor(
                    title: "Inicio",
                    placeholder: "Activaci\u{00F3}n de conocimientos previos y motivaci\u{00F3}n...",
                    html: $activity.inicio,
                    minHeight: 104
                )

                RichTextEditor(
                    title: "Desarrollo",
                    placeholder: "Actividades centrales, mediaci\u{00F3}n y pr\u{00E1}ctica...",
                    html: $activity.desarrollo,
                    minHeight: 150
                )

                RichTextEditor(
                    title: "Cierre",
                    placeholder: "S\u{00ED}ntesis, evaluaci\u{00F3}n formativa y retroalimentaci\u{00F3}n...",
                    html: $activity.cierre,
                    minHeight: 104
                )
            }
        }
    }
}

private struct ClassContextEditorSection: View {
    @Binding var context: String
    @Binding var adaptation: String

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 16) {
                EPSectionHeader(
                    title: "Contexto e inclusi\u{00F3}n",
                    subtitle: "Registra decisiones metodol\u{00F3}gicas y apoyos PIE/DUA.",
                    icon: "person.text.rectangle"
                )

                ClassPlainTextEditor(
                    title: "Contexto docente",
                    placeholder: "Caracter\u{00ED}sticas del curso, recursos disponibles o foco de la sesi\u{00F3}n...",
                    text: $context,
                    minHeight: 88
                )

                RichTextEditor(
                    title: "Adecuaci\u{00F3}n curricular",
                    placeholder: "Adaptaciones metodol\u{00F3}gicas, apoyos y formas de participaci\u{00F3}n...",
                    html: $adaptation,
                    minHeight: 104
                )
            }
        }
    }
}

private struct ClassPlainTextEditor: View {
    let title: String
    let placeholder: String

    @Binding var text: String

    let minHeight: CGFloat

    @State private var plainText = ""
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))

            TextEditor(text: $plainText)
                .font(.subheadline)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .onAppear {
            isSyncing = true
            plainText = RichTextHTML.plainText(from: text)
            DispatchQueue.main.async { isSyncing = false }
        }
        .onChange(of: plainText) { _, newValue in
            guard !isSyncing else { return }
            text = newValue
        }
    }
}

private struct ClassCurriculumEditorSection: View {
    @Binding var activity: ActividadClase

    let skillSuggestions: [String]
    let attitudeSuggestions: [String]
    let materialSuggestions: [String]

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 16) {
                EPSectionHeader(
                    title: "Curr\u{00ED}culo y recursos",
                    subtitle: "Selecciona elementos de la unidad o agrega otros propios.",
                    icon: "tray.full.fill"
                )

                ClassTagListEditor(
                    title: "Habilidades",
                    icon: "figure.mind.and.body",
                    tint: EPTheme.primary,
                    items: $activity.habilidades,
                    suggestions: skillSuggestions
                )

                Divider()

                ClassTagListEditor(
                    title: "Actitudes",
                    icon: "heart.fill",
                    tint: .orange,
                    items: $activity.actitudes,
                    suggestions: attitudeSuggestions
                )

                Divider()

                ClassTagListEditor(
                    title: "Materiales",
                    icon: "shippingbox.fill",
                    tint: .blue,
                    items: $activity.materiales,
                    suggestions: materialSuggestions
                )

                Divider()

                ClassTagListEditor(
                    title: "Herramientas TIC",
                    icon: "laptopcomputer",
                    tint: .purple,
                    items: $activity.tics,
                    suggestions: []
                )

                if let files = activity.archivos, !files.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Archivos adjuntos", systemImage: "paperclip")
                            .font(.caption.weight(.black))

                        ForEach(files) { file in
                            if let url = URL(string: file.url), !file.url.isEmpty {
                                Link(destination: url) {
                                    ClassAttachedFileRow(file: file, showsExternalLink: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                ClassAttachedFileRow(file: file, showsExternalLink: false)
                            }
                        }

                        Text("Los adjuntos se conservan al guardar. La gesti\u{00F3}n de archivos de Drive sigue disponible en EduPanel web.")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ClassTagListEditor: View {
    let title: String
    let icon: String
    let tint: Color

    @Binding var items: [String]

    let suggestions: [String]

    @State private var newItem = ""

    private var availableSuggestions: [String] {
        var seen = Set<String>()
        let existing = Set(items.map { normalizedKey($0) })
        return suggestions.compactMap { suggestion in
            let clean = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedKey(clean)
            guard !clean.isEmpty, !existing.contains(key), seen.insert(key).inserted else { return nil }
            return clean
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)

            if !items.isEmpty {
                ReplicaFlowLayout(spacing: 7) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 5) {
                            Text(item)
                                .font(.caption2.weight(.bold))
                            Button {
                                remove(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Quitar \(item)")
                        }
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(tint.opacity(0.11), in: Capsule())
                    }
                }
            }

            if !availableSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sugerencias de la unidad")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ReplicaFlowLayout(spacing: 6) {
                        ForEach(availableSuggestions, id: \.self) { suggestion in
                            Button {
                                add(suggestion)
                            } label: {
                                Label(suggestion, systemImage: "plus")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(tint)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(EPTheme.subtle, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Agregar \(title.lowercased())", text: $newItem)
                    .font(.subheadline)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit { addNewItem() }

                Button(action: addNewItem) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Agregar a \(title)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func addNewItem() {
        add(newItem)
        newItem = ""
    }

    private func add(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !items.contains(where: { normalizedKey($0) == normalizedKey(clean) }) else { return }
        items.append(clean)
    }

    private func remove(_ value: String) {
        items.removeAll { $0 == value }
    }

    private func normalizedKey(_ value: String) -> String {
        value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "es_CL")
        )
    }
}

private struct ClassAttachedFileRow: View {
    let file: ArchivoAdjunto
    let showsExternalLink: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.blue)
            Text(file.nombre)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if showsExternalLink {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ClassPreservedDataSection: View {
    let activity: ActividadClase

    private var hasAdvancedData: Bool {
        activity.objetivoMultinivel != nil
        || activity.analisisBloom?.isEmpty == false
        || activity.indicadoresEvaluacion?.isEmpty == false
        || activity.actividadEvaluacion != nil
        || activity.desarrolloFormal != nil
    }

    var body: some View {
        if hasAdvancedData {
            Label(
                "El an\u{00E1}lisis Bloom, objetivo multinivel y evaluaci\u{00F3}n avanzada existentes se conservar\u{00E1}n al guardar.",
                systemImage: "checkmark.shield.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
