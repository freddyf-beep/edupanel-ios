import SwiftUI
import PhotosUI

struct GuiaMediaContext {
    let documentId: String?
    let repository: EvaluacionesMediaRepository
    var folder: EvaluacionMediaFolder = .guias
}

private struct GuiaMediaContextKey: EnvironmentKey {
    static let defaultValue = GuiaMediaContext(documentId: nil, repository: EvaluacionesMediaRepository())
}

extension EnvironmentValues {
    var guiaMediaContext: GuiaMediaContext {
        get { self[GuiaMediaContextKey.self] }
        set { self[GuiaMediaContextKey.self] = newValue }
    }
}

struct GuiaContentEditorView: View {
    @Binding var sections: [GuiaSectionDraft]
    @Binding var closingBlocks: [GuiaBlockDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EPSectionHeader(
                    title: "Contenido didáctico",
                    subtitle: "Secciones con texto, imágenes, tablas y separadores.",
                    icon: "rectangle.3.group.fill"
                )
                Button(action: addSection) {
                    Label("Sección", systemImage: "plus")
                        .font(.caption.weight(.black)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(EPTheme.primary, in: Capsule())
                }
            }

            if sections.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "rectangle.3.group",
                        title: "La guía aún no tiene secciones",
                        message: "Agrega una sección y luego incorpora bloques didácticos."
                    )
                }
            }

            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                GuiaSectionDraftEditor(
                    section: sectionBinding(id: section.id, fallback: section),
                    canMoveUp: index > 0,
                    canMoveDown: index + 1 < sections.count,
                    canDelete: section.isNew && section.activityCount == 0,
                    moveUp: { moveSection(from: index, offset: -1) },
                    moveDown: { moveSection(from: index, offset: 1) },
                    delete: { deleteSection(id: section.id) }
                )
            }

            GuiaBlockCollectionEditor(
                title: "Cierre y reflexión",
                subtitle: "Metacognición, autoevaluación o síntesis final.",
                icon: "checkmark.seal.fill",
                blocks: $closingBlocks
            )
        }
    }

    private func sectionBinding(id: String, fallback: GuiaSectionDraft) -> Binding<GuiaSectionDraft> {
        Binding(
            get: { sections.first { $0.id == id } ?? fallback },
            set: { updated in
                guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
                sections[index] = updated
            }
        )
    }

    private func addSection() {
        sections.append(.nueva(order: sections.count + 1))
    }

    private func moveSection(from index: Int, offset: Int) {
        let destination = index + offset
        guard sections.indices.contains(index), sections.indices.contains(destination) else { return }
        sections.swapAt(index, destination)
        for position in sections.indices { sections[position].orden = position + 1 }
    }

    private func deleteSection(id: String) {
        guard let section = sections.first(where: { $0.id == id }), section.isNew, section.activityCount == 0 else { return }
        sections.removeAll { $0.id == id }
        for position in sections.indices { sections[position].orden = position + 1 }
    }
}

private struct GuiaSectionDraftEditor: View {
    @Binding var section: GuiaSectionDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Text("\(section.orden)").font(.caption.weight(.black)).foregroundStyle(EPTheme.primary)
                        .frame(width: 26, height: 26).background(EPTheme.primary.opacity(0.1), in: Circle())
                    TextField("Título de la sección", text: $section.titulo)
                        .font(.subheadline.weight(.black)).textFieldStyle(.roundedBorder)
                    Menu {
                        Button("Subir", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                        Button("Bajar", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                        Button("Eliminar sección", systemImage: "trash", role: .destructive, action: delete)
                            .disabled(!canDelete)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 30, height: 30)
                    }
                }
                TextField("Descripción u objetivo opcional", text: $section.descripcion, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)

                if section.activityCount > 0 {
                    Label("\(section.activityCount) actividad(es)", systemImage: "pencil.and.list.clipboard")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }

                GuiaBlockCollectionEditor(
                    title: "Bloques de la sección",
                    subtitle: nil,
                    icon: "square.stack.3d.up.fill",
                    blocks: $section.bloques
                )

                GuiaActivitiesEditor(activities: $section.actividades)
            }
        }
    }
}

struct GuiaBlockCollectionEditor: View {
    let title: String
    let subtitle: String?
    let icon: String
    @Binding var blocks: [GuiaBlockDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(EPTheme.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.black))
                    if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                addMenu
            }

            if blocks.isEmpty {
                Text("Sin bloques todavía.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }

            ForEach(blocks.filter { !$0.isDeleted }) { block in
                GuiaBlockDraftEditor(
                    block: blockBinding(id: block.id, fallback: block),
                    canMoveUp: canMoveBlock(id: block.id, offset: -1),
                    canMoveDown: canMoveBlock(id: block.id, offset: 1),
                    moveUp: { moveBlock(id: block.id, offset: -1) },
                    moveDown: { moveBlock(id: block.id, offset: 1) },
                    delete: { deleteBlock(id: block.id) }
                )
            }
        }
        .padding(12).background(.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private var addMenu: some View {
        Menu {
            Button("Texto", systemImage: "text.alignleft") { addBlock("texto") }
            Button("Imagen por URL", systemImage: "photo") { addBlock("imagen") }
            Button("Tabla", systemImage: "tablecells") { addBlock("tabla") }
            Button("Separador", systemImage: "minus") { addBlock("separador") }
        } label: {
            Label("Bloque", systemImage: "plus").font(.caption.weight(.black))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(EPTheme.primary.opacity(0.1), in: Capsule())
        }.foregroundStyle(EPTheme.primary)
    }

    private func blockBinding(id: String, fallback: GuiaBlockDraft) -> Binding<GuiaBlockDraft> {
        Binding(
            get: { blocks.first { $0.id == id } ?? fallback },
            set: { updated in
                guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
                blocks[index] = updated
            }
        )
    }

    private func addBlock(_ type: String) { blocks.append(.nueva(type: type)) }
    private func canMoveBlock(id: String, offset: Int) -> Bool {
        let visibleIds = blocks.filter { !$0.isDeleted }.map(\.id)
        guard let index = visibleIds.firstIndex(of: id) else { return false }
        return visibleIds.indices.contains(index + offset)
    }
    private func moveBlock(id: String, offset: Int) {
        let visibleIds = blocks.filter { !$0.isDeleted }.map(\.id)
        guard let visibleIndex = visibleIds.firstIndex(of: id),
              visibleIds.indices.contains(visibleIndex + offset),
              let source = blocks.firstIndex(where: { $0.id == id }),
              let destination = blocks.firstIndex(where: { $0.id == visibleIds[visibleIndex + offset] }) else { return }
        blocks.swapAt(source, destination)
    }
    private func deleteBlock(id: String) {
        guard let block = blocks.first(where: { $0.id == id }), !block.isUnknown else { return }
        if block.isNew {
            blocks.removeAll { $0.id == id }
        } else if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].isDeleted = true
        }
    }
}

private struct GuiaBlockDraftEditor: View {
    @Binding var block: GuiaBlockDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(typeLabel, systemImage: typeIcon).font(.caption.weight(.black)).foregroundStyle(typeTint)
                Spacer()
                Menu {
                    Button("Subir", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                    Button("Bajar", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                    Button("Eliminar", systemImage: "trash", role: .destructive, action: delete).disabled(block.isUnknown)
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
            }

            if block.isUnknown {
                Label("Bloque futuro o heredado: se conservará intacto.", systemImage: "shield.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            } else {
                editorBody
            }
        }
        .padding(11).background(.background, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(EPTheme.border))
    }

    @ViewBuilder
    private var editorBody: some View {
        switch block.type {
        case "texto":
            TextField("Contenido del bloque", text: $block.html, axis: .vertical)
                .lineLimit(3...12).textFieldStyle(.roundedBorder)
            Picker("Estilo", selection: $block.style) {
                Text("Normal").tag("normal"); Text("Destacado").tag("destacado")
                Text("Instrucciones").tag("instrucciones"); Text("Lectura").tag("lectura")
            }.pickerStyle(.menu)
        case "imagen":
            GuiaImageUploadControl(
                url: $block.url,
                storagePath: $block.storagePath,
                alt: $block.alt
            )
            TextField("https://...", text: Binding(
                get: { block.url },
                set: { value in
                    if value != block.url { block.storagePath = "" }
                    block.url = value
                }
            )).keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            TextField("Texto alternativo", text: $block.alt).textFieldStyle(.roundedBorder)
            TextField("Pie de imagen", text: $block.caption).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Ancho", selection: $block.width) {
                    Text("30%").tag("small"); Text("60%").tag("medium"); Text("100%").tag("large")
                }
                Picker("Alineación", selection: $block.alignment) {
                    Text("Izq.").tag("izq"); Text("Centro").tag("centro"); Text("Der.").tag("der")
                }
            }.pickerStyle(.menu)
            if !block.url.isEmpty { PruebaRemoteImage(urlString: block.url, alt: block.alt) }
        case "tabla":
            GuiaTableDraftEditor(block: $block)
        case "separador":
            Picker("Tipo de separador", selection: $block.separatorStyle) {
                Text("Línea").tag("linea"); Text("Espacio").tag("espacio"); Text("Salto de página").tag("saltoPagina")
            }.pickerStyle(.menu)
        default:
            EmptyView()
        }
    }

    private var typeLabel: String {
        switch block.type { case "texto": return "Texto"; case "imagen": return "Imagen"; case "tabla": return "Tabla"; case "separador": return "Separador"; default: return "Bloque compatible" }
    }
    private var typeIcon: String {
        switch block.type { case "texto": return "text.alignleft"; case "imagen": return "photo"; case "tabla": return "tablecells"; case "separador": return "minus"; default: return "questionmark.square" }
    }
    private var typeTint: Color { block.isUnknown ? .orange : EPTheme.primary }
}

struct GuiaImageUploadControl: View {
    @Environment(\.guiaMediaContext) private var mediaContext
    @Binding var url: String
    @Binding var storagePath: String
    @Binding var alt: String

    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var progress = 0.0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label(isUploading ? "Subiendo \(Int(progress * 100))%" : "Elegir foto", systemImage: "photo.badge.plus")
                    .font(.caption.weight(.black)).frame(maxWidth: .infinity).padding(.vertical, 9)
                    .foregroundStyle(mediaContext.documentId == nil ? .secondary : EPTheme.primary)
                    .background(EPTheme.primary.opacity(mediaContext.documentId == nil ? 0.04 : 0.1), in: RoundedRectangle(cornerRadius: 9))
            }
            .disabled(mediaContext.documentId == nil || isUploading)

            if isUploading {
                ProgressView(value: progress).tint(EPTheme.primary)
            } else if mediaContext.documentId == nil {
                Text(mediaContext.folder == .pruebas
                     ? "Guarda la prueba antes de subir imágenes."
                     : "Guarda la guía antes de subir imágenes.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.red)
            }
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        guard let documentId = mediaContext.documentId else { return }
        isUploading = true; progress = 0; errorMessage = nil
        defer { isUploading = false; selectedItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw EvaluacionesMediaError.invalidImage
            }
            let result = try await mediaContext.repository.subirImagen(
                documentId: documentId,
                folder: mediaContext.folder,
                data: data,
                onProgress: { value in progress = value }
            )
            url = result.url
            storagePath = result.storagePath
            if alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                alt = mediaContext.folder == .pruebas ? "Imagen de la prueba" : "Imagen de la guía"
            }
            progress = 1
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GuiaTableDraftEditor: View {
    @Binding var block: GuiaBlockDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Primera columna como cabecera", isOn: $block.firstColumnHeader).font(.caption)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        ForEach(block.headers.indices, id: \.self) { column in
                            TextField("Cabecera", text: headerBinding(column)).font(.caption.weight(.bold))
                                .textFieldStyle(.roundedBorder).frame(width: 125)
                        }
                    }
                    ForEach(block.rows.indices, id: \.self) { row in
                        HStack(spacing: 5) {
                            ForEach(block.headers.indices, id: \.self) { column in
                                TextField("Celda", text: cellBinding(row: row, column: column)).font(.caption)
                                    .textFieldStyle(.roundedBorder).frame(width: 125)
                            }
                            Button(role: .destructive) { removeRow(row) } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
            HStack {
                Button("+ Fila", action: addRow).font(.caption.weight(.bold))
                Button("+ Columna", action: addColumn).font(.caption.weight(.bold))
                Spacer()
                Button("Quitar columna", role: .destructive, action: removeColumn)
                    .font(.caption.weight(.bold)).disabled(block.headers.count <= 1)
            }
        }
    }

    private func headerBinding(_ column: Int) -> Binding<String> {
        Binding(get: { block.headers.indices.contains(column) ? block.headers[column] : "" },
                set: { if block.headers.indices.contains(column) { block.headers[column] = $0 } })
    }
    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: { block.rows.indices.contains(row) && block.rows[row].indices.contains(column) ? block.rows[row][column] : "" },
            set: { value in
                guard block.rows.indices.contains(row) else { return }
                while block.rows[row].count < block.headers.count { block.rows[row].append("") }
                guard block.rows[row].indices.contains(column) else { return }
                block.rows[row][column] = value
            }
        )
    }
    private func addRow() { block.rows.append(Array(repeating: "", count: max(1, block.headers.count))) }
    private func removeRow(_ index: Int) { if block.rows.indices.contains(index) { block.rows.remove(at: index) } }
    private func addColumn() {
        block.headers.append("Columna \(block.headers.count + 1)")
        for row in block.rows.indices { block.rows[row].append("") }
    }
    private func removeColumn() {
        guard block.headers.count > 1 else { return }
        block.headers.removeLast()
        for row in block.rows.indices where !block.rows[row].isEmpty { block.rows[row].removeLast() }
    }
}
