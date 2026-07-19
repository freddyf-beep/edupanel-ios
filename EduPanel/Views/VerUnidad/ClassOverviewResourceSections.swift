import QuickLook
import SwiftUI

struct ClassCurriculumCategory: Identifiable {
    let title: String
    let symbol: String
    let tint: Color
    let items: [String]

    var id: String { title }
}

struct ClassCurriculumCard: View {
    let categories: [ClassCurriculumCategory]
    let onOpenCategory: (ClassCurriculumCategory) -> Void

    var body: some View {
        if !categories.isEmpty {
            UnitSectionSurface {
                VStack(alignment: .leading, spacing: 14) {
                    UnitSectionHeader(
                        title: "Currículo de la clase",
                        subtitle: "Abre cada categoría para leerla completa",
                        symbol: "books.vertical.fill",
                        tint: .blue
                    )

                    ForEach(categories) { category in
                        ClassCurriculumCategoryRow(category: category) {
                            onOpenCategory(category)
                        }
                    }
                }
            }
        }
    }
}

private struct ClassCurriculumCategoryRow: View {
    let category: ClassCurriculumCategory
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: category.symbol)
                    .font(.body.weight(.bold))
                    .foregroundStyle(category.tint)
                    .frame(width: 34, height: 34)
                    .background(category.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(category.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("\(category.items.count)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(category.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(category.tint.opacity(0.1), in: Capsule())
                    }
                    Text(category.items.first ?? "Sin contenido")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
        .accessibilityValue("\(category.items.count) elementos")
        .accessibilityHint("Abre la lista completa")
    }
}

struct ClassMaterialsCard: View {
    let materials: [String]
    let files: [ArchivoAdjunto]

    @State private var previewURL: URL?
    @State private var drivePreview: ClassDrivePreview?
    @State private var isPreparingPreview = false
    @State private var previewError: ClassMaterialPreviewError?

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 14) {
                UnitSectionHeader(
                    title: "Materiales de la clase",
                    subtitle: "Recursos declarados y archivos adjuntos",
                    symbol: "shippingbox.fill",
                    tint: .purple
                )

                if materials.isEmpty && files.isEmpty {
                    UnitEmptyMessage(
                        text: "Esta clase todavía no tiene materiales registrados.",
                        symbol: "shippingbox"
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(materials, id: \.self) { material in
                            ClassDeclaredMaterialRow(material: material)
                        }
                        ForEach(files) { file in
                            ClassAttachedMaterialRow(file: file) {
                                preparePreview(file)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if isPreparingPreview {
                ProgressView("Preparando archivo…")
                    .font(.footnote.weight(.semibold))
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .quickLookPreview($previewURL)
        .sheet(item: $drivePreview) { preview in
            ClassDrivePreviewSheet(preview: preview)
        }
        .alert(item: $previewError) { error in
            Alert(
                title: Text("No se pudo abrir el archivo"),
                message: Text(error.message),
                dismissButton: .default(Text("Aceptar"))
            )
        }
    }

    private func preparePreview(_ file: ArchivoAdjunto) {
        guard !isPreparingPreview else { return }

        if let preview = drivePreviewItem(for: file) {
            drivePreview = preview
            return
        }

        Task { await downloadForPreview(file) }
    }

    private func drivePreviewItem(for file: ArchivoAdjunto) -> ClassDrivePreview? {
        guard file.provider?.lowercased() == "drive" || file.driveFileId != nil else {
            return nil
        }

        let previewAddress: String?
        if let storedPreview = file.previewUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storedPreview.isEmpty {
            previewAddress = storedPreview
        } else if let driveFileID = file.driveFileId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !driveFileID.isEmpty {
            previewAddress = "https://drive.google.com/file/d/\(driveFileID)/preview"
        } else {
            previewAddress = nil
        }

        guard let previewAddress, let url = URL(string: previewAddress) else { return nil }
        let externalURL = [file.webViewLink, file.url]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .flatMap(URL.init(string:))
        return ClassDrivePreview(title: file.nombre, url: url, externalURL: externalURL)
    }

    @MainActor
    private func downloadForPreview(_ file: ArchivoAdjunto) async {
        guard let sourceURL = previewSourceURL(for: file) else {
            previewError = ClassMaterialPreviewError(message: "Este material no tiene un enlace disponible.")
            return
        }

        if sourceURL.isFileURL {
            previewURL = sourceURL
            return
        }

        isPreparingPreview = true
        defer { isPreparingPreview = false }

        do {
            let (downloadedURL, response) = try await URLSession.shared.download(from: sourceURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }

            let previewDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("EduPanelPreviews", isDirectory: true)
            try FileManager.default.createDirectory(
                at: previewDirectory,
                withIntermediateDirectories: true
            )

            let destination = previewDirectory.appendingPathComponent(previewFileName(file, sourceURL: sourceURL))
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: downloadedURL, to: destination)
            previewURL = destination
        } catch {
            previewError = ClassMaterialPreviewError(
                message: "Revisa tu conexión o vuelve a intentarlo más tarde."
            )
        }
    }

    private func previewSourceURL(for file: ArchivoAdjunto) -> URL? {
        [file.previewUrl, file.url, file.webViewLink]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .flatMap(URL.init(string:))
    }

    private func previewFileName(_ file: ArchivoAdjunto, sourceURL: URL) -> String {
        var name = file.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Material" }
        name = name.replacingOccurrences(of: "/", with: "-")
        if (name as NSString).pathExtension.isEmpty, !sourceURL.pathExtension.isEmpty {
            name += ".\(sourceURL.pathExtension)"
        }
        return "\(UUID().uuidString)-\(name)"
    }
}

private struct ClassDeclaredMaterialRow: View {
    let material: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(material)
                .font(.subheadline)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ClassAttachedMaterialRow: View {
    let file: ArchivoAdjunto
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            HStack(spacing: 11) {
                Image(systemName: fileSymbol)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.purple)
                    .frame(width: 38, height: 38)
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.nombre)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        if file.provider == "drive" {
                            Text("Drive")
                        } else {
                            Text("Archivo del docente")
                        }
                        Text("·")
                        Text("Vista previa")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)
                Image(systemName: "eye.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EPTheme.primary)
                    .accessibilityHidden(true)
            }
            .padding(11)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir \(file.nombre)")
        .accessibilityHint("Descarga una copia temporal y muestra la vista previa")
    }

    private var fileSymbol: String {
        let type = (file.tipo ?? "").lowercased()
        let name = file.nombre.lowercased()
        if type.contains("pdf") || name.hasSuffix(".pdf") { return "doc.richtext.fill" }
        if type.contains("image") { return "photo.fill" }
        return file.provider == "drive" ? "externaldrive.fill" : "paperclip"
    }
}

struct ClassAdvancedSummaryButton: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            UnitSectionSurface {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.indigo)
                        .frame(width: 36, height: 36)
                        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Datos pedagógicos avanzados")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Multinivel, Bloom y evaluación")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre los datos pedagógicos avanzados de esta clase")
    }
}

private struct ClassMaterialPreviewError: Identifiable {
    let id = UUID()
    let message: String
}
