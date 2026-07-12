import SwiftUI

struct GuiaActivitiesEditor: View {
    @Binding var activities: [GuiaActivityDraft]
    var onSaveToBank: ((GuiaActivityDraft) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Actividades", systemImage: "pencil.and.list.clipboard").font(.caption.weight(.black))
                Spacer()
                addMenu
            }

            if activities.filter({ !$0.isDeleted }).isEmpty {
                Text("Sin actividades en esta sección.").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(activities.filter { !$0.isDeleted }) { activity in
                GuiaActivityDraftEditor(
                    activity: binding(id: activity.id, fallback: activity),
                    canMoveUp: canMove(id: activity.id, offset: -1),
                    canMoveDown: canMove(id: activity.id, offset: 1),
                    onSaveToBank: onSaveToBank.map { callback in { callback(activity) } },
                    moveUp: { move(id: activity.id, offset: -1) },
                    moveDown: { move(id: activity.id, offset: 1) },
                    delete: { delete(id: activity.id) }
                )
            }
        }
        .padding(12).background(.orange.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    private var addMenu: some View {
        Menu {
            ForEach(GuiaActividadKind.allCases.filter { $0 != .desconocida }, id: \.rawValue) { kind in
                Button(kind.label) { add(kind.rawValue) }
            }
        } label: {
            Label("Actividad", systemImage: "plus").font(.caption.weight(.black))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.orange.opacity(0.12), in: Capsule())
        }.foregroundStyle(.orange)
    }

    private func binding(id: String, fallback: GuiaActivityDraft) -> Binding<GuiaActivityDraft> {
        Binding(get: { activities.first { $0.id == id } ?? fallback }, set: { value in
            guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
            activities[index] = value
        })
    }
    private func add(_ type: String) {
        activities.append(.nueva(type: type, number: activities.filter { !$0.isDeleted }.count + 1))
    }
    private func visibleIds() -> [String] { activities.filter { !$0.isDeleted }.map(\.id) }
    private func canMove(id: String, offset: Int) -> Bool {
        let ids = visibleIds()
        guard let index = ids.firstIndex(of: id) else { return false }
        return ids.indices.contains(index + offset)
    }
    private func move(id: String, offset: Int) {
        let ids = visibleIds()
        guard let position = ids.firstIndex(of: id), ids.indices.contains(position + offset),
              let source = activities.firstIndex(where: { $0.id == id }),
              let destination = activities.firstIndex(where: { $0.id == ids[position + offset] }) else { return }
        activities.swapAt(source, destination)
        renumber()
    }
    private func delete(id: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }), !activities[index].isUnknown else { return }
        if activities[index].isNew { activities.remove(at: index) } else { activities[index].isDeleted = true }
        renumber()
    }
    private func renumber() {
        var number = 1
        for index in activities.indices where !activities[index].isDeleted {
            activities[index].number = number; number += 1
        }
    }
}

private struct GuiaActivityDraftEditor: View {
    @Binding var activity: GuiaActivityDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onSaveToBank: (() -> Void)?
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    private var kind: GuiaActividadKind { .resolve(activity.type) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("\(activity.number)").font(.caption.weight(.black)).foregroundStyle(.orange)
                    .frame(width: 25, height: 25).background(.orange.opacity(0.12), in: Circle())
                Label(kind.label, systemImage: "pencil.line").font(.caption.weight(.black)).foregroundStyle(.orange)
                Spacer()
                Menu {
                    if let onSaveToBank {
                        Button("Guardar en banco", systemImage: "tray.and.arrow.down.fill", action: onSaveToBank)
                            .disabled(activity.isUnknown)
                    }
                    Button("Subir", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                    Button("Bajar", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                    Button("Eliminar", systemImage: "trash", role: .destructive, action: delete).disabled(activity.isUnknown)
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
            }

            if activity.isUnknown {
                Label("Tipo futuro o heredado: se conservará intacto.", systemImage: "shield.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            } else {
                TextField("Enunciado de la actividad", text: $activity.prompt, axis: .vertical)
                    .lineLimit(2...7).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("OA vinculado", text: $activity.linkedOA).textFieldStyle(.roundedBorder)
                    TextField("Puntos", text: scoreBinding).keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder).frame(width: 82)
                }
                typeSpecificEditor
                GuiaBlockCollectionEditor(
                    title: "Recursos de la actividad", subtitle: nil,
                    icon: "photo.on.rectangle.angled", blocks: $activity.resources
                )
            }
        }
        .padding(11).background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.18)))
    }

    @ViewBuilder
    private var typeSpecificEditor: some View {
        switch kind {
        case .seleccionMultiple, .encerrar, .marcar:
            GuiaActivityEntriesEditor(entries: $activity.entriesA, style: .option, pairTargets: [])
        case .verdaderoFalso:
            GuiaActivityEntriesEditor(entries: $activity.entriesA, style: .affirmation, pairTargets: [])
        case .completar:
            TextField("Texto con espacios o marcadores", text: $activity.text, axis: .vertical)
                .lineLimit(2...6).textFieldStyle(.roundedBorder)
            commaField("Respuestas correctas", values: $activity.answers)
            commaField("Banco de palabras", values: $activity.wordBank)
        case .respuestaCorta:
            linesStepper
            TextField("Respuesta sugerida opcional", text: $activity.suggestedAnswer, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder)
        case .ordenar:
            GuiaActivityEntriesEditor(entries: $activity.entriesA, style: .step, pairTargets: [])
        case .pareados:
            Text("Columna A").font(.caption.weight(.black)).foregroundStyle(EPTheme.primary)
            GuiaActivityEntriesEditor(entries: $activity.entriesA, style: .pairA, pairTargets: [])
            Text("Columna B").font(.caption.weight(.black)).foregroundStyle(EPTheme.primary)
            GuiaActivityEntriesEditor(
                entries: $activity.entriesB, style: .pairB,
                pairTargets: activity.entriesA.filter { !$0.isDeleted }.map {
                    GuiaPairTarget(id: $0.documentId, text: $0.text)
                }
            )
        case .colorear:
            instructionField
            GuiaImageUploadControl(
                url: $activity.imageUrl,
                storagePath: .constant(""),
                alt: .constant(activity.instruction)
            )
            urlField
        case .dibujar:
            instructionField
            Stepper("Altura del recuadro: \(activity.heightCm.formatted(.number.precision(.fractionLength(0...1)))) cm",
                    value: $activity.heightCm, in: 1...20, step: 0.5)
                .font(.caption.weight(.semibold))
        case .investigar:
            instructionField
            linesStepper
        case .sopaLetras:
            commaField("Palabras", values: $activity.words)
            Stepper("Cuadrícula: \(activity.gridSize) × \(activity.gridSize)", value: $activity.gridSize, in: 4...20)
                .font(.caption.weight(.semibold))
        case .abierta:
            linesStepper
        case .desconocida:
            EmptyView()
        }
    }

    private var scoreBinding: Binding<String> {
        Binding(
            get: { activity.score.map { String(format: "%g", $0) } ?? "" },
            set: { value in activity.score = Double(value.replacingOccurrences(of: ",", with: ".")) }
        )
    }
    private var linesStepper: some View {
        Stepper("Líneas de respuesta: \(activity.lines)", value: $activity.lines, in: 1...20)
            .font(.caption.weight(.semibold))
    }
    private var instructionField: some View {
        TextField("Instrucción específica", text: $activity.instruction, axis: .vertical)
            .lineLimit(2...6).textFieldStyle(.roundedBorder)
    }
    private var urlField: some View {
        TextField("https://imagen...", text: $activity.imageUrl).keyboardType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
    }
    private func commaField(_ title: String, values: Binding<[String]>) -> some View {
        TextField(title, text: Binding(
            get: { values.wrappedValue.joined(separator: ", ") },
            set: { values.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        ), axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
    }
}

private enum GuiaEntryStyle: Equatable { case option, affirmation, step, pairA, pairB }

private struct GuiaPairTarget: Identifiable {
    let id: String
    let text: String
}

private struct GuiaActivityEntriesEditor: View {
    @Binding var entries: [GuiaActivityEntryDraft]
    let style: GuiaEntryStyle
    let pairTargets: [GuiaPairTarget]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(entries.filter { !$0.isDeleted }) { entry in
                HStack(alignment: .top, spacing: 7) {
                    TextField("Texto", text: binding(id: entry.id, \.text, fallback: entry.text), axis: .vertical)
                        .lineLimit(1...4).textFieldStyle(.roundedBorder)
                    trailingControl(entry)
                    VStack(spacing: 2) {
                        Button { move(entry.id, offset: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(!canMove(entry.id, offset: -1))
                        Button { move(entry.id, offset: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(!canMove(entry.id, offset: 1))
                    }.font(.caption2)
                    Button(role: .destructive) { remove(entry.id) } label: { Image(systemName: "trash").font(.caption) }
                }
                if style == .option {
                    GuiaImageUploadControl(
                        url: binding(id: entry.id, \.imageUrl, fallback: entry.imageUrl),
                        storagePath: .constant(""),
                        alt: .constant(entry.text)
                    )
                    TextField("URL de imagen opcional", text: binding(id: entry.id, \.imageUrl, fallback: entry.imageUrl))
                        .keyboardType(.URL).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                }
            }
            Button { add() } label: { Label("Agregar", systemImage: "plus.circle.fill").font(.caption.weight(.bold)) }
        }
    }

    @ViewBuilder
    private func trailingControl(_ entry: GuiaActivityEntryDraft) -> some View {
        switch style {
        case .option, .affirmation:
            Toggle("Correcta", isOn: binding(id: entry.id, \.correct, fallback: entry.correct)).labelsHidden()
        case .step:
            Stepper("\(entry.correctOrder)", value: binding(id: entry.id, \.correctOrder, fallback: entry.correctOrder), in: 1...30)
                .labelsHidden().fixedSize()
        case .pairB:
            Picker("Par", selection: binding(id: entry.id, \.linkedId, fallback: entry.linkedId)) {
                Text("Sin par").tag("")
                ForEach(pairTargets, id: \.id) { target in Text(target.text.isEmpty ? target.id : target.text).tag(target.id) }
            }.labelsHidden().frame(width: 105)
        case .pairA:
            EmptyView()
        }
    }

    private func binding<Value>(
        id: String,
        _ keyPath: WritableKeyPath<GuiaActivityEntryDraft, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { entries.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
                entries[index][keyPath: keyPath] = value
            }
        )
    }

    private func add() { entries.append(.nueva(prefix: "entrada", order: entries.filter { !$0.isDeleted }.count + 1)) }
    private func visibleIds() -> [String] { entries.filter { !$0.isDeleted }.map(\.id) }
    private func canMove(_ id: String, offset: Int) -> Bool {
        let ids = visibleIds()
        guard let index = ids.firstIndex(of: id) else { return false }
        return ids.indices.contains(index + offset)
    }
    private func move(_ id: String, offset: Int) {
        let ids = visibleIds()
        guard let position = ids.firstIndex(of: id), ids.indices.contains(position + offset),
              let source = entries.firstIndex(where: { $0.id == id }),
              let destination = entries.firstIndex(where: { $0.id == ids[position + offset] }) else { return }
        entries.swapAt(source, destination)
        if style == .step {
            var order = 1
            for index in entries.indices where !entries[index].isDeleted {
                entries[index].correctOrder = order; order += 1
            }
        }
    }
    private func remove(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[index].isNew { entries.remove(at: index) } else { entries[index].isDeleted = true }
    }
}
