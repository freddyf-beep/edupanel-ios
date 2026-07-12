import SwiftUI

struct PruebaContentEditorView: View {
    @Binding var sections: [PruebaSectionDraft]
    let oas: [OAEditado]

    private var visibleSections: [PruebaSectionDraft] {
        sections.filter { !$0.isDeleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                EPSectionHeader(
                    title: "Contenido de la prueba",
                    subtitle: "Secciones, est\u{00ED}mulos y preguntas evaluadas.",
                    icon: "list.bullet.rectangle.fill"
                )
                Spacer(minLength: 0)
                Menu {
                    ForEach(PruebaEditorItemType.allCases, id: \.rawValue) { type in
                        Button(type.label, systemImage: type.icon) {
                            addSection(type.rawValue)
                        }
                    }
                } label: {
                    Label("Secci\u{00F3}n", systemImage: "plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(EPTheme.rose, in: Capsule())
                }
            }

            if visibleSections.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "rectangle.stack.badge.plus",
                        title: "La prueba no tiene secciones",
                        message: "Agrega una secci\u{00F3}n y luego incorpora sus preguntas."
                    )
                }
            }

            ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                PruebaSectionDraftEditor(
                    section: sectionBinding(id: section.id, fallback: section),
                    oas: oas,
                    canMoveUp: index > 0,
                    canMoveDown: index + 1 < visibleSections.count,
                    canDelete: !containsProtectedContent(section),
                    moveUp: { moveSection(id: section.id, offset: -1) },
                    moveDown: { moveSection(id: section.id, offset: 1) },
                    delete: { deleteSection(id: section.id) }
                )
            }
        }
    }

    private func sectionBinding(id: String, fallback: PruebaSectionDraft) -> Binding<PruebaSectionDraft> {
        Binding(
            get: { sections.first { $0.id == id } ?? fallback },
            set: { updated in
                guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
                sections[index] = updated
            }
        )
    }

    private func addSection(_ type: String) {
        sections.append(.nueva(order: visibleSections.count + 1, type: type))
    }

    private func moveSection(id: String, offset: Int) {
        let ids = visibleSections.map(\.id)
        guard let visibleIndex = ids.firstIndex(of: id), ids.indices.contains(visibleIndex + offset),
              let source = sections.firstIndex(where: { $0.id == id }),
              let destination = sections.firstIndex(where: { $0.id == ids[visibleIndex + offset] }) else { return }
        sections.swapAt(source, destination)
        renumberSections()
    }

    private func deleteSection(id: String) {
        guard let section = sections.first(where: { $0.id == id }), !containsProtectedContent(section) else { return }
        if section.isNew {
            sections.removeAll { $0.id == id }
        } else if let index = sections.firstIndex(where: { $0.id == id }) {
            sections[index].isDeleted = true
        }
        renumberSections()
    }

    private func renumberSections() {
        var order = 1
        for index in sections.indices where !sections[index].isDeleted {
            sections[index].orden = order
            order += 1
        }
    }

    private func containsProtectedContent(_ section: PruebaSectionDraft) -> Bool {
        section.estimulo.contains { $0.isUnknown && !$0.isDeleted } ||
        section.items.contains { item in
            !item.isDeleted && (item.isUnknown || item.resources.contains { $0.isUnknown && !$0.isDeleted })
        }
    }
}

private struct PruebaSectionDraftEditor: View {
    @Binding var section: PruebaSectionDraft
    let oas: [OAEditado]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    private var visibleItems: [PruebaItemDraft] { section.items.filter { !$0.isDeleted } }
    private var points: Double { visibleItems.reduce(0) { $0 + max(0, $1.score) } }

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 9) {
                    Text(roman(section.orden))
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(EPTheme.rose, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("T\u{00ED}tulo de la secci\u{00F3}n", text: $section.titulo)
                            .font(.subheadline.weight(.black))
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 6) {
                            EPStatusPill(text: "\(visibleItems.count) \u{00ED}tems", tint: EPTheme.rose)
                            EPStatusPill(
                                text: "\(points.formatted(.number.precision(.fractionLength(0...1)))) pts",
                                icon: "star.fill",
                                tint: .orange
                            )
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("Subir", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                        Button("Bajar", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                        Button("Eliminar secci\u{00F3}n", systemImage: "trash", role: .destructive, action: delete)
                            .disabled(!canDelete)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 30, height: 30)
                    }
                }

                TextField("Instrucciones de la secci\u{00F3}n", text: $section.instrucciones, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)

                Picker("Tipo predominante", selection: $section.tipoPredominante) {
                    Text("Mixto").tag("mixto")
                    ForEach(PruebaEditorItemType.allCases, id: \.rawValue) { type in
                        Text(type.label).tag(type.rawValue)
                    }
                }
                .pickerStyle(.menu)

                GuiaBlockCollectionEditor(
                    title: "Est\u{00ED}mulo de la secci\u{00F3}n",
                    subtitle: "Lectura, imagen, tabla o material previo.",
                    icon: "text.page.badge.magnifyingglass",
                    blocks: $section.estimulo
                )

                PruebaItemsEditor(items: $section.items, oas: oas)

                if !canDelete {
                    Label("Esta secci\u{00F3}n contiene datos web desconocidos y no puede eliminarse completa.", systemImage: "shield.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func roman(_ value: Int) -> String {
        let map: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        guard value > 0, value < 40 else { return String(value) }
        var number = value
        var result = ""
        for (amount, symbol) in map {
            while number >= amount { result += symbol; number -= amount }
        }
        return result
    }
}
