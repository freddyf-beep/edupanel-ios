import Foundation
import SwiftUI

struct PruebaItemsEditor: View {
    @Binding var items: [PruebaItemDraft]
    let oas: [OAEditado]
    var onSaveToBank: ((PruebaItemDraft) -> Void)? = nil

    private var visibleItems: [PruebaItemDraft] { items.filter { !$0.isDeleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Preguntas", systemImage: "questionmark.bubble.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(EPTheme.rose)
                Spacer()
                addMenu
            }

            if visibleItems.isEmpty {
                Text("Sin preguntas todav\u{00ED}a.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }

            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                PruebaItemDraftEditor(
                    item: itemBinding(id: item.id, fallback: item),
                    number: index + 1,
                    oas: oas,
                    canMoveUp: index > 0,
                    canMoveDown: index + 1 < visibleItems.count,
                    canDelete: !item.isUnknown && !item.resources.contains { $0.isUnknown && !$0.isDeleted },
                    onSaveToBank: onSaveToBank.map { callback in { callback(item) } },
                    moveUp: { moveItem(id: item.id, offset: -1) },
                    moveDown: { moveItem(id: item.id, offset: 1) },
                    delete: { deleteItem(id: item.id) }
                )
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private var addMenu: some View {
        Menu {
            ForEach(PruebaEditorItemType.allCases, id: \.rawValue) { type in
                Button(type.label, systemImage: type.icon) {
                    items.append(.nueva(type: type.rawValue))
                }
            }
        } label: {
            Label("Pregunta", systemImage: "plus")
                .font(.caption.weight(.black))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(EPTheme.rose.opacity(0.1), in: Capsule())
        }
        .foregroundStyle(EPTheme.rose)
    }

    private func itemBinding(id: String, fallback: PruebaItemDraft) -> Binding<PruebaItemDraft> {
        Binding(
            get: { items.first { $0.id == id } ?? fallback },
            set: { updated in
                guard let index = items.firstIndex(where: { $0.id == id }) else { return }
                items[index] = updated
            }
        )
    }

    private func moveItem(id: String, offset: Int) {
        let ids = visibleItems.map(\.id)
        guard let visibleIndex = ids.firstIndex(of: id), ids.indices.contains(visibleIndex + offset),
              let source = items.firstIndex(where: { $0.id == id }),
              let destination = items.firstIndex(where: { $0.id == ids[visibleIndex + offset] }) else { return }
        items.swapAt(source, destination)
    }

    private func deleteItem(id: String) {
        guard let item = items.first(where: { $0.id == id }),
              !item.isUnknown,
              !item.resources.contains(where: { $0.isUnknown && !$0.isDeleted }) else { return }
        if item.isNew {
            items.removeAll { $0.id == id }
        } else if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isDeleted = true
        }
    }
}

private struct PruebaItemDraftEditor: View {
    @Binding var item: PruebaItemDraft
    let number: Int
    let oas: [OAEditado]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let onSaveToBank: (() -> Void)?
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    private var resolvedType: PruebaEditorItemType? { PruebaEditorItemType.resolve(item.type) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if item.isUnknown || resolvedType == nil {
                Label(
                    "Tipo web no reconocido (\(item.type.isEmpty ? "sin tipo" : item.type)). Se conservar\u{00E1} intacto.",
                    systemImage: "shield.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            } else {
                commonFields
                typeSpecificEditor
                GuiaBlockCollectionEditor(
                    title: "Recursos de la pregunta",
                    subtitle: "Texto o imagen complementaria.",
                    icon: "photo.on.rectangle.angled",
                    blocks: $item.resources
                )
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(item.isUnknown ? Color.orange.opacity(0.45) : EPTheme.border))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.black))
                .foregroundStyle(item.isUnknown ? .orange : EPTheme.rose)
                .frame(width: 27, height: 27)
                .background((item.isUnknown ? Color.orange : EPTheme.rose).opacity(0.1), in: Circle())
            Label(resolvedType?.label ?? "Tipo desconocido", systemImage: resolvedType?.icon ?? "questionmark.diamond")
                .font(.caption.weight(.black))
                .foregroundStyle(item.isUnknown ? .orange : EPTheme.rose)
            Spacer()
            TextField("Pts", value: $item.score, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .disabled(item.isUnknown)
            Menu {
                if let onSaveToBank {
                    Button("Guardar en banco", systemImage: "tray.and.arrow.down.fill", action: onSaveToBank)
                        .disabled(item.isUnknown)
                }
                Button("Subir", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                Button("Bajar", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                Button("Eliminar", systemImage: "trash", role: .destructive, action: delete).disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 28)
            }
        }
    }

    private var commonFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Enunciado de la pregunta", text: $item.enunciado, axis: .vertical)
                .lineLimit(2...8)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Picker("OA vinculado", selection: $item.linkedOA) {
                    Text("Sin OA").tag("")
                    ForEach(oas.filter { $0.seleccionado || $0.esPropio == true || $0.id == item.linkedOA }) { oa in
                        Text(oa.numero.map { "OA \($0) · \(oa.descripcion)" } ?? oa.descripcion).tag(oa.id)
                    }
                }
                .pickerStyle(.menu)

                if resolvedType == .seleccionMultiple {
                    Picker("Habilidad", selection: $item.habilidad) {
                        Text("Sin habilidad").tag("")
                        ForEach(["recordar", "comprender", "aplicar", "analizar", "evaluar", "crear"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var typeSpecificEditor: some View {
        switch resolvedType {
        case .seleccionMultiple:
            SeleccionMultipleDraftEditor(item: $item)
        case .verdaderoFalso:
            VerdaderoFalsoDraftEditor(item: $item)
        case .pareados:
            PareadosDraftEditor(item: $item)
        case .ordenar:
            OrdenarDraftEditor(item: $item)
        case .completar:
            CompletarDraftEditor(item: $item)
        case .respuestaCorta:
            RespuestaCortaDraftEditor(item: $item)
        case .desarrollo:
            DesarrolloDraftEditor(item: $item)
        case nil:
            EmptyView()
        }
    }
}

private struct SeleccionMultipleDraftEditor: View {
    @Binding var item: PruebaItemDraft
    private var entries: [PruebaItemEntryDraft] { item.entriesA.filter { !$0.isDeleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALTERNATIVAS · MARCA UNA CORRECTA").font(.system(size: 9.5, weight: .black)).foregroundStyle(.secondary)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Button { setCorrect(entry.id) } label: {
                            Image(systemName: entry.correct ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(entry.correct ? .green : .secondary)
                        }
                        Text(pruebaAlphabeticLabel(index))
                            .font(.caption.weight(.black)).foregroundStyle(.secondary)
                        TextField("Alternativa", text: entryBinding(entry.id, \.text)).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { deleteEntry(entry.id) } label: { Image(systemName: "trash") }
                            .disabled(entries.count <= 2)
                    }
                    TextField("URL de imagen opcional", text: entryBinding(entry.id, \.imageURL))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.caption).textFieldStyle(.roundedBorder)
                }
            }
            Button { item.entriesA.append(.nueva(prefix: "alt", order: entries.count)) } label: {
                Label("Agregar alternativa", systemImage: "plus.circle.fill").font(.caption.weight(.black))
            }
        }
    }

    private func entryBinding(_ id: String, _ keyPath: WritableKeyPath<PruebaItemEntryDraft, String>) -> Binding<String> {
        Binding(
            get: { item.entriesA.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = item.entriesA.firstIndex(where: { $0.id == id }) else { return }
                item.entriesA[index][keyPath: keyPath] = value
                if keyPath == \.imageURL { item.entriesA[index].imageStoragePath = "" }
            }
        )
    }

    private func setCorrect(_ id: String) {
        for index in item.entriesA.indices where !item.entriesA[index].isDeleted {
            item.entriesA[index].correct = item.entriesA[index].id == id
        }
    }

    private func deleteEntry(_ id: String) {
        guard entries.count > 2, let entry = item.entriesA.first(where: { $0.id == id }) else { return }
        if entry.isNew { item.entriesA.removeAll { $0.id == id } }
        else if let index = item.entriesA.firstIndex(where: { $0.id == id }) { item.entriesA[index].isDeleted = true }
    }
}

private struct VerdaderoFalsoDraftEditor: View {
    @Binding var item: PruebaItemDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Respuesta correcta", selection: $item.respuestaCorrecta) {
                Text("Verdadero").tag(true)
                Text("Falso").tag(false)
            }
            .pickerStyle(.segmented)
            Toggle("Pedir justificaci\u{00F3}n cuando sea falsa", isOn: $item.pideJustificacion)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct PareadosDraftEditor: View {
    @Binding var item: PruebaItemDraft
    private var columnA: [PruebaItemEntryDraft] { item.entriesA.filter { !$0.isDeleted } }
    private var columnB: [PruebaItemEntryDraft] { item.entriesB.filter { !$0.isDeleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("T\u{00C9}RMINOS PAREADOS").font(.system(size: 9.5, weight: .black)).foregroundStyle(.secondary)
            ForEach(Array(columnA.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(index + 1).").font(.caption.weight(.black))
                        TextField("Columna A", text: aBinding(entry.id, \.text)).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { deletePair(entry.id) } label: { Image(systemName: "trash") }
                            .disabled(columnA.count <= 2)
                    }
                    TextField("URL de imagen opcional", text: aBinding(entry.id, \.imageURL))
                        .font(.caption).textFieldStyle(.roundedBorder)
                }
            }
            Divider()
            ForEach(Array(columnB.enumerated()), id: \.element.id) { index, entry in
                HStack {
                    Text("\(pruebaAlphabeticLabel(index)).")
                        .font(.caption.weight(.black))
                    TextField("Columna B", text: bBinding(entry.id, \.text)).textFieldStyle(.roundedBorder)
                    Picker("Correspondencia", selection: bBinding(entry.id, \.linkedId)) {
                        Text("Sin par").tag("")
                        ForEach(Array(columnA.enumerated()), id: \.element.id) { aIndex, a in
                            Text("= \(aIndex + 1)").tag(a.documentId)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            Button(action: addPair) {
                Label("Agregar par", systemImage: "plus.circle.fill").font(.caption.weight(.black))
            }
        }
    }

    private func aBinding(_ id: String, _ keyPath: WritableKeyPath<PruebaItemEntryDraft, String>) -> Binding<String> {
        entryBinding(array: \.entriesA, id: id, keyPath: keyPath)
    }
    private func bBinding(_ id: String, _ keyPath: WritableKeyPath<PruebaItemEntryDraft, String>) -> Binding<String> {
        entryBinding(array: \.entriesB, id: id, keyPath: keyPath)
    }
    private func entryBinding(
        array: WritableKeyPath<PruebaItemDraft, [PruebaItemEntryDraft]>,
        id: String,
        keyPath: WritableKeyPath<PruebaItemEntryDraft, String>
    ) -> Binding<String> {
        Binding(
            get: { item[keyPath: array].first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = item[keyPath: array].firstIndex(where: { $0.id == id }) else { return }
                item[keyPath: array][index][keyPath: keyPath] = value
            }
        )
    }
    private func addPair() {
        let a = PruebaItemEntryDraft.nueva(prefix: "a", order: columnA.count)
        var b = PruebaItemEntryDraft.nueva(prefix: "b", order: columnB.count)
        b.linkedId = a.documentId
        item.entriesA.append(a); item.entriesB.append(b)
    }
    private func deletePair(_ id: String) {
        guard columnA.count > 2, let a = item.entriesA.first(where: { $0.id == id }) else { return }
        let linked = a.documentId
        if a.isNew {
            item.entriesA.removeAll { $0.id == id }
        } else if let index = item.entriesA.firstIndex(where: { $0.id == id }) {
            item.entriesA[index].isDeleted = true
        }
        let linkedEntries = item.entriesB.filter { !$0.isDeleted && $0.linkedId == linked }
        for entry in linkedEntries {
            if entry.isNew {
                item.entriesB.removeAll { $0.id == entry.id }
            } else if let index = item.entriesB.firstIndex(where: { $0.id == entry.id }) {
                item.entriesB[index].isDeleted = true
            }
        }
    }
}

private func pruebaAlphabeticLabel(_ index: Int) -> String {
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    return letters.indices.contains(index) ? String(letters[index]) : "?"
}

private struct OrdenarDraftEditor: View {
    @Binding var item: PruebaItemDraft
    private var steps: [PruebaItemEntryDraft] { item.entriesA.filter { !$0.isDeleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PASOS EN EL ORDEN CORRECTO").font(.system(size: 9.5, weight: .black)).foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 6) {
                    Text("\(index + 1)").font(.caption.weight(.black)).frame(width: 22, height: 22)
                        .background(.orange.opacity(0.12), in: Circle())
                    TextField("Paso", text: binding(step.id)).textFieldStyle(.roundedBorder)
                    Button { move(step.id, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                    Button { move(step.id, 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == steps.count)
                    Button(role: .destructive) { delete(step.id) } label: { Image(systemName: "trash") }.disabled(steps.count <= 2)
                }
            }
            Button { item.entriesA.append(.nueva(prefix: "p", order: steps.count)) } label: {
                Label("Agregar paso", systemImage: "plus.circle.fill").font(.caption.weight(.black))
            }
        }
    }
    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { item.entriesA.first(where: { $0.id == id })?.text ?? "" }, set: { value in
            if let index = item.entriesA.firstIndex(where: { $0.id == id }) { item.entriesA[index].text = value }
        })
    }
    private func move(_ id: String, _ offset: Int) {
        let ids = steps.map(\.id)
        guard let visibleIndex = ids.firstIndex(of: id), ids.indices.contains(visibleIndex + offset),
              let source = item.entriesA.firstIndex(where: { $0.id == id }),
              let destination = item.entriesA.firstIndex(where: { $0.id == ids[visibleIndex + offset] }) else { return }
        item.entriesA.swapAt(source, destination)
    }
    private func delete(_ id: String) {
        guard steps.count > 2, let step = item.entriesA.first(where: { $0.id == id }) else { return }
        if step.isNew { item.entriesA.removeAll { $0.id == id } }
        else if let index = item.entriesA.firstIndex(where: { $0.id == id }) { item.entriesA[index].isDeleted = true }
    }
}

private struct CompletarDraftEditor: View {
    @Binding var item: PruebaItemDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usa __ para cada espacio en blanco.").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Texto con espacios en blanco", text: $item.textoConBlancos, axis: .vertical)
                .lineLimit(2...7).textFieldStyle(.roundedBorder)
                .onChange(of: item.textoConBlancos) { _, value in syncAnswers(with: value) }
            ForEach(item.respuestas.indices, id: \.self) { index in
                TextField("Respuesta para blanco \(index + 1)", text: answerBinding(index)).textFieldStyle(.roundedBorder)
            }
            TextField("Banco de palabras separado por comas", text: wordBankBinding)
                .textFieldStyle(.roundedBorder)
        }
    }
    private var wordBankBinding: Binding<String> {
        Binding(get: { item.wordBank.joined(separator: ", ") }, set: { value in
            item.wordBank = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        })
    }
    private func answerBinding(_ index: Int) -> Binding<String> {
        Binding(get: { item.respuestas.indices.contains(index) ? item.respuestas[index] : "" }, set: { value in
            if item.respuestas.indices.contains(index) { item.respuestas[index] = value }
        })
    }
    private func syncAnswers(with text: String) {
        let regex = try? NSRegularExpression(pattern: "__+")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let count = regex?.numberOfMatches(in: text, range: range) ?? 0
        guard count != item.respuestas.count else { return }
        item.respuestas = (0..<count).map { item.respuestas.indices.contains($0) ? item.respuestas[$0] : "" }
    }
}

private struct RespuestaCortaDraftEditor: View {
    @Binding var item: PruebaItemDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("L\u{00ED}neas para responder: \(item.lineasRespuesta)", value: $item.lineasRespuesta, in: 1...20)
                .font(.caption.weight(.semibold))
            TextField("Respuesta esperada", text: $item.respuestaEsperada, axis: .vertical)
                .lineLimit(2...6).textFieldStyle(.roundedBorder)
        }
    }
}

private struct DesarrolloDraftEditor: View {
    @Binding var item: PruebaItemDraft
    private var criteria: [PruebaItemEntryDraft] { item.entriesA.filter { !$0.isDeleted } }
    private var criteriaPoints: Double { criteria.reduce(0) { $0 + max(0, $1.score) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("L\u{00ED}neas para responder: \(item.lineasRespuesta)", value: $item.lineasRespuesta, in: 1...30)
                .font(.caption.weight(.semibold))
            TextField("Pauta de correcci\u{00F3}n", text: $item.pautaCorreccion, axis: .vertical)
                .lineLimit(2...7).textFieldStyle(.roundedBorder)
            HStack {
                Text("CRITERIOS OPCIONALES").font(.system(size: 9.5, weight: .black)).foregroundStyle(.secondary)
                Spacer()
                Text("\(criteriaPoints.formatted(.number.precision(.fractionLength(0...1)))) / \(item.score.formatted(.number.precision(.fractionLength(0...1)))) pts")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(abs(criteriaPoints - item.score) < 0.001 ? .green : .orange)
            }
            ForEach(criteria) { criterion in
                HStack {
                    TextField("Criterio", text: entryText(criterion.id)).textFieldStyle(.roundedBorder)
                    TextField("Pts", value: entryScore(criterion.id), format: .number)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 70)
                    Button(role: .destructive) { deleteCriterion(criterion.id) } label: { Image(systemName: "trash") }
                }
            }
            Button { item.entriesA.append(.nueva(prefix: "crit", order: criteria.count)) } label: {
                Label("Agregar criterio", systemImage: "plus.circle.fill").font(.caption.weight(.black))
            }
        }
    }
    private func entryText(_ id: String) -> Binding<String> {
        Binding(get: { item.entriesA.first(where: { $0.id == id })?.text ?? "" }, set: { value in
            if let index = item.entriesA.firstIndex(where: { $0.id == id }) { item.entriesA[index].text = value }
        })
    }
    private func entryScore(_ id: String) -> Binding<Double> {
        Binding(get: { item.entriesA.first(where: { $0.id == id })?.score ?? 0 }, set: { value in
            if let index = item.entriesA.firstIndex(where: { $0.id == id }) { item.entriesA[index].score = max(0, value) }
        })
    }
    private func deleteCriterion(_ id: String) {
        guard let criterion = item.entriesA.first(where: { $0.id == id }) else { return }
        if criterion.isNew { item.entriesA.removeAll { $0.id == id } }
        else if let index = item.entriesA.firstIndex(where: { $0.id == id }) { item.entriesA[index].isDeleted = true }
    }
}
