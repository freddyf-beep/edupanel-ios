import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum GuiaPDFMode: String, CaseIterable, Identifiable {
    case estudiante
    case pauta

    var id: String { rawValue }
    var title: String { self == .pauta ? "PDF con pauta" : "PDF para estudiante" }
}

struct GuiaPDFArtifact: Identifiable {
    let id = UUID()
    let url: URL
    let mode: GuiaPDFMode
    let title: String
    let omittedImageCount: Int
}

private struct GuiaPDFResolvedFormat {
    let fontStack: String
    let fontSize: Double
    let primaryColor: String
    let headerAccent: String
    let marginTopMM: Double
    let marginRightMM: Double
    let marginBottomMM: Double
    let marginLeftMM: Double
    let titleAlignment: String
    let headerMode: ExportHeaderMode
    let showsCurricularData: Bool
    let showsInstructions: Bool
    let footerText: String
    let showsPageNumber: Bool
    let tableHeaderShading: String
    let usesTableBorders: Bool
    let signatureCount: Int?

    static func resolve(
        school: InfoColegio,
        formatOverride: ExportFormat?,
        documentKind: String = "guia"
    ) -> Self {
        let selected = documentKind == "prueba" ? school.testExportFormat : school.guideExportFormat
        let format = formatOverride ?? selected ?? .empty
        let uniformMargin = format.marginMM
        return Self(
            fontStack: (format.font ?? .sans).cssStack,
            fontSize: format.baseFontSize ?? 11,
            primaryColor: format.primaryColor ?? "#000000",
            headerAccent: format.primaryColor ?? "#6366f1",
            marginTopMM: uniformMargin ?? 12,
            marginRightMM: uniformMargin ?? 14,
            marginBottomMM: uniformMargin ?? 13,
            marginLeftMM: uniformMargin ?? 14,
            titleAlignment: format.titleAlignment == "izquierda" ? "left" : "center",
            headerMode: format.headerMode ?? .completo,
            showsCurricularData: format.showsCurricularData != false,
            showsInstructions: format.showsInstructions != false,
            footerText: format.footerText ?? "",
            showsPageNumber: format.showsPageNumber == true,
            tableHeaderShading: format.structure?.headerShading ?? "#efefef",
            usesTableBorders: format.structure?.usesBorders != false,
            signatureCount: format.structure?.signatureCount
        )
    }

    var hasFooter: Bool { !footerText.isEmpty || showsPageNumber }
    var signatureSpaceMM: Int? {
        guard hasFooter, let signatureCount else { return nil }
        return min(36, 14 + signatureCount * 6)
    }
}

struct GuiaPDFExporter: Sendable {
    @MainActor
    func export(
        guide: GuiaTemplate,
        school: InfoColegio,
        teacherName: String?,
        mode: GuiaPDFMode,
        formatOverride: ExportFormat? = nil
    ) async throws -> GuiaPDFArtifact {
        let format = GuiaPDFResolvedFormat.resolve(school: school, formatOverride: formatOverride)
        let sourceImageURLs = imageURLs(in: guide)
        let inlineResult = try await inlineImages(urls: sourceImageURLs)
        let html = buildHTML(
            guide: guide, teacherName: teacherName, mode: mode,
            images: inlineResult.images, format: format
        )
        let fileURL = try outputURL(guide: guide, mode: mode)
        let data = renderPDF(html: html, school: school, format: format)
        guard !data.isEmpty else { throw GuiaPDFExportError.emptyPDF }
        try data.write(to: fileURL, options: .atomic)
        return GuiaPDFArtifact(
            url: fileURL,
            mode: mode,
            title: guide.nombre.isEmpty ? "Guía de aprendizaje" : guide.nombre,
            omittedImageCount: inlineResult.omittedCount
        )
    }

    @MainActor
    func export(
        test: PruebaTemplate,
        school: InfoColegio,
        teacherName: String?,
        mode: GuiaPDFMode,
        formatOverride: ExportFormat? = nil
    ) async throws -> GuiaPDFArtifact {
        let format = GuiaPDFResolvedFormat.resolve(
            school: school,
            formatOverride: formatOverride,
            documentKind: "prueba"
        )
        let sourceImageURLs = imageURLs(in: test)
        let inlineResult = try await inlineImages(urls: sourceImageURLs)
        let html = buildTestHTML(
            test: test,
            teacherName: teacherName,
            mode: mode,
            images: inlineResult.images,
            format: format
        )
        let fileURL = try outputURL(test: test, mode: mode)
        let data = renderPDF(html: html, school: school, format: format)
        guard !data.isEmpty else { throw GuiaPDFExportError.emptyPDF }
        try data.write(to: fileURL, options: .atomic)
        return GuiaPDFArtifact(
            url: fileURL,
            mode: mode,
            title: test.nombre.isEmpty ? "Prueba" : test.nombre,
            omittedImageCount: inlineResult.omittedCount
        )
    }

    private func imageURLs(in guide: GuiaTemplate) -> [String] {
        var result: [String] = []
        func append(_ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.contains(value) else { return }
            result.append(value)
        }
        func blocks(_ values: [PruebaContentBlock]) { values.forEach { append($0.url) } }
        for section in guide.secciones {
            blocks(section.contenido)
            for activity in section.actividades {
                blocks(activity.recursos)
                activity.opciones.forEach { append($0.imagenUrl) }
                append(activity.imagenUrl)
            }
        }
        blocks(guide.cierre)
        return result
    }

    private func imageURLs(in test: PruebaTemplate) -> [String] {
        var result: [String] = []
        func append(_ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !result.contains(value) else { return }
            result.append(value)
        }
        for section in test.secciones {
            section.estimulo.forEach { append($0.url) }
            for item in section.items {
                item.recursos.forEach { append($0.url) }
                item.alternativas.forEach { append($0.imagenUrl) }
                item.columnaA.forEach { append($0.imagenUrl) }
            }
        }
        return result
    }

    private struct DownloadedImage: Sendable {
        let order: Int
        let sourceURL: String
        let data: Data
        let mimeType: String
    }

    private struct InlineImageResult: Sendable {
        let images: [String: String]
        let omittedCount: Int
    }

    private func inlineImages(urls: [String]) async throws -> InlineImageResult {
        let candidates = Array(urls.prefix(24))
        let downloaded = try await withThrowingTaskGroup(of: DownloadedImage?.self) { group in
            for (order, value) in candidates.enumerated() {
                group.addTask { try await Self.downloadImage(value, order: order) }
            }
            var values: [DownloadedImage] = []
            for try await image in group {
                if let image { values.append(image) }
            }
            return values.sorted { $0.order < $1.order }
        }

        var result: [String: String] = [:]
        var totalBytes = 0
        for image in downloaded {
            guard totalBytes + image.data.count <= 30 * 1024 * 1024 else { continue }
            totalBytes += image.data.count
            result[image.sourceURL] = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
        }
        return InlineImageResult(images: result, omittedCount: max(0, urls.count - result.count))
    }

    private static func downloadImage(_ value: String, order: Int) async throws -> DownloadedImage? {
        if value.lowercased().hasPrefix("data:image/") {
            return inlineImage(value, order: order)
        }
        guard let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard data.count <= 8 * 1024 * 1024,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let detectedMIME: String?
            if let identifier = CGImageSourceGetType(source) {
                detectedMIME = UTType(identifier as String)?.preferredMIMEType
            } else {
                detectedMIME = nil
            }
            let responseMIME = response.mimeType.flatMap { $0.hasPrefix("image/") ? $0 : nil }
            guard let mimeType = detectedMIME ?? responseMIME else { return nil }
            return DownloadedImage(order: order, sourceURL: value, data: data, mimeType: mimeType)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private static func inlineImage(_ value: String, order: Int) -> DownloadedImage? {
        guard value.utf8.count <= 12 * 1024 * 1024,
              let comma = value.firstIndex(of: ",") else { return nil }
        let metadata = String(value[..<comma]).lowercased()
        guard metadata.hasPrefix("data:image/"), metadata.hasSuffix(";base64") else { return nil }
        let payload = String(value[value.index(after: comma)...])
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let mimeType = UTType(identifier as String)?.preferredMIMEType else { return nil }
        return DownloadedImage(order: order, sourceURL: value, data: data, mimeType: mimeType)
    }

    private func buildHTML(
        guide: GuiaTemplate,
        teacherName: String?,
        mode: GuiaPDFMode,
        images: [String: String],
        format: GuiaPDFResolvedFormat
    ) -> String {
        let rawTitle = guide.numeroGuia.flatMap { $0.isEmpty ? nil : $0 }
            .map { "\($0) - \(guide.nombre.isEmpty ? "Guía" : guide.nombre)" }
            ?? (guide.nombre.isEmpty ? "Guía de aprendizaje" : guide.nombre)
        let title = plainText(rawTitle)
        let teacher = (teacherName?.isEmpty == false ? teacherName : guide.docenteNombre) ?? ""
        let factValues = [
            fact("Asignatura", guide.asignatura), fact("Curso", guide.curso),
            teacher.isEmpty ? "" : fact("Profesor(a)", teacher),
            guide.tiempoMinutos.map { fact("Tiempo", "\($0) min") } ?? "",
            fact("Nombre", "_______________________________"),
            guide.unidadNombre.map { fact("Unidad", $0) } ?? ""
        ].filter { !$0.isEmpty }
        let factRows = stride(from: 0, to: factValues.count, by: 2).map { index in
            let second = index + 1 < factValues.count ? factValues[index + 1] : "<td></td>"
            return "<tr>\(factValues[index])\(second)</tr>"
        }.joined()
        let objective = guide.objetivo.isEmpty ? "" : "<div class='objective'><b>Objetivo:</b> \(escape(plainText(guide.objetivo)))</div>"
        let curriculum = !format.showsCurricularData || guide.objetivos.isEmpty ? "" : "<div class='curriculum'><b>OA(s):</b><ul>\(guide.objetivos.map { "<li>\(escape($0))</li>" }.joined())</ul></div>"
        let instructions = !format.showsInstructions || guide.instrucciones.isEmpty ? "" : "<div class='instructions'><b>Instrucciones:</b><ul>\(guide.instrucciones.map { "<li>\(escape($0))</li>" }.joined())</ul></div>"
        let sections = guide.secciones.map { sectionHTML($0, mode: mode, images: images) }.joined()
        let closing = guide.cierre.isEmpty ? "" : "<div class='closing'><h3>Cierre y reflexión</h3>\(blocksHTML(guide.cierre, images: images))</div>"
        let pautaClass = mode == .pauta ? "pauta" : ""
        let pautaTitle = mode == .pauta ? "<div class='pauta-title'>PAUTA DE CORRECCIÓN</div>" : ""
        let borderOverride = format.usesTableBorders ? "" : ".content-table th, .content-table td { border-color:transparent !important; }"
        let signatureSpace = format.signatureSpaceMM.map { "<div style='height:\($0)mm'></div>" } ?? ""

        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8"><style>
        @page { size: A4 portrait; margin: 0; }
        * { box-sizing: border-box; } body { margin:0; font-family: \(format.fontStack); color:#111827; font-size:\(format.fontSize)pt; line-height:1.26; }
        h1 { color:\(format.primaryColor); text-align:\(format.titleAlignment); font-size:14.5pt; margin:2mm 0 1mm; } .pauta-title { color:#b91c1c; text-align:\(format.titleAlignment); font-size:9.5pt; font-weight:bold; margin:0 0 3mm; }
        .facts { width:100%; background:#f5f5f5; border:1px solid #9ca3af; } .facts td { width:50%; border:0; padding:2mm; font-size:9.5pt; }
        .objective { border:1px solid #9ca3af; border-left:3px solid #374151; padding:2mm 3mm; margin:2mm 0; font-size:9.5pt; } .curriculum { border:1px solid #d1d5db; padding:2mm 3mm; font-size:9.5pt; }
        .instructions { border:1px solid #9ca3af; padding:2mm 3mm; margin:2mm 0; font-size:9.5pt; } ul { margin:1mm 0 1mm 5mm; padding-left:4mm; }
        section { margin:3mm 0 0; } h2 { color:\(format.primaryColor); border-bottom:1.2px solid \(format.primaryColor); font-size:11pt; text-transform:uppercase; margin-bottom:2mm; page-break-after:avoid; } .desc { color:#4b5563; font-size:9.5pt; font-style:italic; }
        .text { margin:2mm 0; } .featured { border:1px solid #6b7280; padding:2mm; } .instructions-text { color:#4b5563; font-style:italic; } .reading { border:1px dashed #6b7280; padding:3mm; }
        .image { text-align:center; margin:3mm 0; } .image.align-izq { text-align:left; } .image.align-der { text-align:right; }
        .image img { max-width:100%; max-height:75mm; object-fit:contain; } .alt img, .grid-option img { max-width:100%; max-height:18mm; object-fit:contain; } .image-missing { border:1px dashed #6b7280; min-height:24mm; padding:8mm 2mm; color:#4b5563; text-align:center; font-style:italic; } .caption { color:#6b7280; font-size:8.5pt; font-style:italic; }
        table { border-collapse:collapse; width:100%; margin:2mm 0; } th,td { border:1px solid #9ca3af; padding:1.5mm; } th { background:\(format.tableHeaderShading); }
        .activity { padding:0; margin:2mm 0 0; page-break-inside:avoid; } .prompt { font-weight:400; line-height:1.3; page-break-after:avoid; } .points { color:#374151; font-size:9pt; font-style:italic; }
        .alt { margin:0.5mm 0; } .two-column { margin:0.8mm 0 0 5mm; } .two-column td { width:50%; border:0; padding:0.5mm 3mm 0.5mm 0; vertical-align:top; }
        .grid-option { border:1px solid #777; padding:1mm 2mm; } .correct { background:#d8f3df; } .answer { color:#b91c1c; border:1px solid #b91c1c; border-left:3px solid #b91c1c; padding:2mm; margin-top:2mm; } .inline-answer { color:#b91c1c; font-weight:bold; }
        .line { border-bottom:1px solid #6b7280; height:7mm; margin:1mm 5mm; } .drawing { border:2px dashed #9ca3af; min-height:45mm; margin:2mm 4mm; }
        .separator { border-top:1px solid #6b7280; margin:4mm 0; } .pagebreak { page-break-after:always; } .closing { border:2px solid #374151; padding:4mm; }
        .soup { width:auto; margin:2mm auto; } .soup td { width:7mm; height:7mm; padding:0; text-align:center; }
        tr, img { page-break-inside:avoid; } \(borderOverride)
        </style></head><body class="\(pautaClass)"><h1>\(escape(title))</h1>\(pautaTitle)<table class='facts'>\(factRows)</table>\(objective)\(curriculum)\(instructions)\(sections)\(closing)\(signatureSpace)</body></html>
        """
    }

    private func sectionHTML(_ section: GuiaSeccion, mode: GuiaPDFMode, images: [String: String]) -> String {
        let description = section.descripcion.flatMap { $0.isEmpty ? nil : $0 }.map { "<div class='desc'>\(escape($0))</div>" } ?? ""
        let score = section.actividades.compactMap(\.puntaje).reduce(0, +)
        let points = score > 0 ? " <span class='points'>(\(format(score)) pts)</span>" : ""
        return "<section><h2>\(escape(section.titulo))\(points)</h2>\(description)\(blocksHTML(section.contenido, images: images))\(section.actividades.map { activityHTML($0, mode: mode, images: images) }.joined())</section>"
    }

    private func blocksHTML(_ blocks: [PruebaContentBlock], images: [String: String]) -> String {
        blocks.map { block in
            switch block.kind {
            case .texto:
                let css = block.estilo == "destacado" ? "featured" : (block.estilo == "instrucciones" ? "instructions-text" : (block.estilo == "lectura" ? "reading" : ""))
                return "<div class='text \(css)'>\(safeRichHTML(block.html ?? ""))</div>"
            case .imagen:
                let caption = block.caption.map { "<div class='caption'>\(escape($0))</div>" } ?? ""
                let alignment = ["izq", "centro", "der"].contains(block.alineacion ?? "") ? (block.alineacion ?? "centro") : "centro"
                let width = block.ancho == "small" ? "30%" : (block.ancho == "medium" ? "60%" : "100%")
                let media = imageSource(block.url, images: images)
                    .map { "<img src='\($0)' alt='\(escape(block.alt ?? "Imagen"))' style='max-width:\(width)'>" }
                    ?? "<div class='image-missing'>Imagen no disponible</div>"
                return "<div class='image align-\(alignment)'>\(media)\(caption)</div>"
            case .tabla:
                let headers = block.cabeceras.map { "<th>\(escape($0))</th>" }.joined()
                let rows = block.filas.map { row in
                    let cells = row.enumerated().map { index, value in
                        let tag = block.primeraColumnaCabecera && index == 0 ? "th" : "td"
                        return "<\(tag)>\(escape(value))</\(tag)>"
                    }.joined()
                    return "<tr>\(cells)</tr>"
                }.joined()
                return "<table class='content-table'><thead><tr>\(headers)</tr></thead><tbody>\(rows)</tbody></table>"
            case .separador:
                let style = block.estilo
                if style == "saltoPagina" { return "<div class='pagebreak'></div>" }
                if style == "linea" { return "<div class='separator'></div>" }
                return "<div style='height:5mm'></div>"
            case .unknown:
                return ""
            }
        }.joined()
    }

    private func activityHTML(_ activity: GuiaActividad, mode: GuiaPDFMode, images: [String: String]) -> String {
        let points = activity.puntaje.map { " <span class='points'>(\(format($0)) pts)</span>" } ?? ""
        let header = "<div class='prompt'><b>\(activity.numero).</b> \(escape(activity.enunciado))\(points)</div>"
        let resources = blocksHTML(activity.recursos, images: images)
        let body: String
        switch activity.kind {
        case .seleccionMultiple:
            let options = activity.opciones.enumerated().map { index, option in
                let correct = mode == .pauta && option.correcta == true
                let mark = correct ? "✓" : "○"
                let image = optionImage(option.imagenUrl, images: images)
                return "<div class='alt \(correct ? "correct" : "")'>\(mark) <b>\(letter(index)))</b> \(escape(option.texto))\(image)</div>"
            }
            let compact = activity.opciones.allSatisfy { $0.texto.count <= 48 && ($0.imagenUrl?.isEmpty ?? true) }
            body = compact ? twoColumnTable(options) : options.joined()
        case .encerrar, .marcar:
            let options = activity.opciones.map { option in
                let correct = mode == .pauta && option.correcta == true
                let mark = activity.kind == .marcar ? "□" : "○"
                let image = optionImage(option.imagenUrl, images: images)
                return "<div class='grid-option \(correct ? "correct" : "")'>\(mark) \(escape(option.texto))\(image)</div>"
            }
            body = twoColumnTable(options)
        case .verdaderoFalso:
            body = "<table><tbody>" + activity.afirmaciones.enumerated().map { index, item in
                let answer = mode == .pauta ? (item.correcta == true ? "V" : "F") : "_____"
                return "<tr><td>\(index + 1).</td><td><b>\(answer)</b></td><td>\(escape(item.texto))</td></tr>"
            }.joined() + "</tbody></table>"
        case .completar:
            let bank = activity.banco.isEmpty ? "" : "<div><b>Banco:</b> \(activity.banco.map(escape).joined(separator: " · "))</div>"
            let text = completionHTML(activity.textoCompletar ?? "", answers: activity.respuestas, mode: mode)
            body = "\(bank)<p>\(text)</p>"
        case .respuestaCorta:
            body = responseLines(activity.lineas ?? 2) + (mode == .pauta ? activity.respuestaSugerida.map { "<div class='answer'>Sugerida: \(escape($0))</div>" } ?? "" : "")
        case .ordenar:
            let steps = mode == .pauta ? activity.pasos.sorted { ($0.numeroCorrecto ?? 0) < ($1.numeroCorrecto ?? 0) } : activity.pasos
            body = steps.map { "<div>\(mode == .pauta ? String($0.numeroCorrecto ?? 0) : "_____") &nbsp; \(escape($0.texto))</div>" }.joined()
        case .pareados:
            let a = activity.columnaA.enumerated().map { "<tr><td>\($0.offset + 1).</td><td>\(escape($0.element.texto))</td><td>_____</td></tr>" }.joined()
            let b = activity.columnaB.enumerated().map { index, value in
                let match = activity.columnaA.firstIndex { sourceId(from: $0.id) == value.pareCon }
                let answer = mode == .pauta ? " → \(match.map { String($0 + 1) } ?? "?")" : ""
                return "<tr><td>\(letter(index)))</td><td>\(escape(value.texto))\(answer)</td></tr>"
            }.joined()
            body = "<table><tr><th>Columna A</th><th>Columna B</th></tr><tr><td><table>\(a)</table></td><td><table>\(b)</table></td></tr></table>"
        case .colorear:
            let image: String
            if let imageURL = activity.imagenUrl, !imageURL.isEmpty {
                image = imageSource(imageURL, images: images)
                    .map { "<div class='image'><img src='\($0)'></div>" }
                    ?? "<div class='image-missing'>Imagen no disponible</div>"
            } else {
                image = "<div class='drawing'>Espacio para colorear</div>"
            }
            body = "<i>\(escape(activity.instruccion ?? ""))</i>\(image)"
        case .dibujar:
            let requestedHeight = activity.alturaCm ?? 8
            let height = requestedHeight > 0 ? requestedHeight : 8
            body = "<i>\(escape(activity.instruccion ?? ""))</i><div class='drawing' style='min-height:\(height)cm'></div>"
        case .investigar:
            body = "<i>\(escape(activity.instruccion ?? ""))</i>" + responseLines(activity.lineas ?? 4)
        case .sopaLetras:
            let size = min(20, max(4, activity.tamanoCuadro ?? 12))
            let grid = (0..<size).map { _ in "<tr>" + (0..<size).map { _ in "<td>&nbsp;</td>" }.joined() + "</tr>" }.joined()
            let words = activity.palabras.isEmpty ? "" : "<div><b>Palabras:</b> \(activity.palabras.map(escape).joined(separator: " · "))</div>"
            body = "\(words)<table class='soup'>\(grid)</table>"
        case .abierta, .desconocida:
            body = responseLines(activity.lineas ?? 4)
        }
        return "<div class='activity'>\(header)\(resources)\(body)</div>"
    }

    private func buildTestHTML(
        test: PruebaTemplate,
        teacherName: String?,
        mode: GuiaPDFMode,
        images: [String: String],
        format: GuiaPDFResolvedFormat
    ) -> String {
        let title = escape(plainText(test.nombre.isEmpty ? "Prueba" : test.nombre))
        let teacher = teacherName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let facts = [
            fact("Asignatura", test.asignatura),
            fact("Curso", test.curso),
            (teacher?.isEmpty == false ? fact("Profesor(a)", teacher ?? "") : ""),
            test.tiempoMinutos.map { fact("Tiempo", "\($0) min") } ?? "",
            fact("Puntaje", "\(self.format(test.puntajeMaximo)) puntos"),
            fact("Nombre", "_______________________________")
        ].filter { !$0.isEmpty }
        let factRows = stride(from: 0, to: facts.count, by: 2).map { index in
            let second = facts.indices.contains(index + 1) ? facts[index + 1] : "<td></td>"
            return "<tr>\(facts[index])\(second)</tr>"
        }.joined()
        let selectedOAs = test.oas?.filter(\.seleccionado).map { oa in
            let code = oa.numero.map { "OA \($0)" } ?? oa.id
            return "<li><b>\(escape(code)):</b> \(escape(oa.descripcion))</li>"
        } ?? test.metadatosCurriculares.objetivos.map { "<li>\(escape($0))</li>" }
        let curriculum = format.showsCurricularData && !selectedOAs.isEmpty
            ? "<div class='curriculum'><b>Objetivos de Aprendizaje:</b><ul>\(selectedOAs.joined())</ul></div>"
            : ""
        let instructions = format.showsInstructions && !test.instruccionesGenerales.isEmpty
            ? "<div class='instructions'><b>Instrucciones:</b><ol>\(test.instruccionesGenerales.map { "<li>\(escape($0))</li>" }.joined())</ol></div>"
            : ""
        var itemNumber = 0
        let sections = test.secciones.sorted { $0.orden < $1.orden }.map { section -> String in
            let stimulus = section.estimulo.isEmpty ? "" : "<div class='stimulus'>\(blocksHTML(section.estimulo, images: images))</div>"
            let items = section.items.map { item -> String in
                itemNumber += 1
                return testItemHTML(item, number: itemNumber, mode: mode, images: images)
            }.joined()
            return """
            <section><h2>\(escape(section.titulo.isEmpty ? "Sección \(section.orden)" : section.titulo))</h2>
            \(section.instrucciones.isEmpty ? "" : "<p class='section-instructions'>\(escape(plainText(section.instrucciones)))</p>")
            \(stimulus)\(items)</section>
            """
        }.joined()
        let pautaTitle = mode == .pauta ? "<div class='pauta-title'>PAUTA DE CORRECCIÓN</div>" : ""
        let borderOverride = format.usesTableBorders ? "" : "table th, table td { border-color: transparent !important; }"

        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8"><style>
        @page { size:A4; margin:0; }
        * { box-sizing:border-box; }
        body { margin:0; color:#151515; font-family:\(format.fontStack); font-size:\(format.fontSize)pt; line-height:1.35; }
        h1 { margin:0 0 10px; text-align:\(format.titleAlignment); color:\(format.primaryColor); font-size:\(format.fontSize + 7)pt; }
        h2 { margin:18px 0 6px; padding-bottom:4px; border-bottom:1.5px solid \(format.headerAccent); color:\(format.primaryColor); font-size:\(format.fontSize + 2)pt; }
        .pauta-title { margin:0 0 12px; padding:6px; text-align:center; font-weight:bold; color:#166534; border:1px solid #86efac; background:#f0fdf4; }
        .facts { width:100%; border-collapse:collapse; margin:0 0 10px; }
        .facts td { width:50%; padding:4px 6px; border:1px solid #d4d4d4; }
        .curriculum,.instructions,.stimulus { margin:8px 0; padding:8px 10px; border:1px solid #dedede; background:#fafafa; }
        .curriculum ul,.instructions ol { margin:4px 0 0 20px; padding:0; }
        .section-instructions { margin:4px 0 10px; font-style:italic; color:#444; }
        .test-item { break-inside:avoid; margin:10px 0 15px; padding:9px 10px; border:1px solid #d9d9d9; border-radius:5px; }
        .item-head { display:flex; justify-content:space-between; gap:12px; margin-bottom:7px; font-weight:bold; }
        .points { white-space:nowrap; color:#555; }
        .resource { margin:7px 0; }
        img { max-width:100%; max-height:230px; object-fit:contain; }
        .option { margin:5px 0; padding:3px 5px; }
        .correct { color:#166534; font-weight:bold; background:#f0fdf4; }
        .wrong { color:#991b1b; }
        .line { height:21px; border-bottom:1px solid #777; }
        .answer { margin-top:7px; padding:6px 8px; color:#166534; border-left:3px solid #22c55e; background:#f0fdf4; }
        table { width:100%; border-collapse:collapse; margin:7px 0; }
        th,td { padding:5px 7px; border:1px solid #bbb; vertical-align:top; }
        th { background:\(format.tableHeaderShading); }
        \(borderOverride)
        </style></head><body class='\(mode == .pauta ? "pauta" : "")'>
        \(pautaTitle)<h1>\(title)</h1><table class='facts'>\(factRows)</table>
        \(curriculum)\(instructions)\(sections)
        </body></html>
        """
    }

    private func testItemHTML(
        _ item: PruebaItem,
        number: Int,
        mode: GuiaPDFMode,
        images: [String: String]
    ) -> String {
        let prompt = escape(plainText(item.enunciado))
        let header = "<div class='item-head'><span>\(number). \(prompt)</span><span class='points'>\(format(item.puntaje)) pts</span></div>"
        let resources = item.recursos.isEmpty ? "" : "<div class='resource'>\(blocksHTML(item.recursos, images: images))</div>"
        let body: String

        switch item.kind {
        case .seleccionMultiple:
            body = item.alternativas.enumerated().map { index, option in
                let isCorrect = option.esCorrecta && mode == .pauta
                let image = optionImage(option.imagenUrl, images: images)
                return "<div class='option \(isCorrect ? "correct" : "")'>\(letter(index)).) \(escape(option.texto))\(image)\(isCorrect ? " ✓" : "")</div>"
            }.joined()
        case .verdaderoFalso:
            let mark = mode == .pauta ? (item.respuestaCorrecta == true ? "<b class='correct'>V</b> / F" : "V / <b class='correct'>F</b>") : "V / F"
            let justification = item.pideJustificacion ? "<div class='line'></div><div class='line'></div>" : ""
            body = "<div>Respuesta: \(mark)</div>\(justification)"
        case .pareados:
            let left = item.columnaA.enumerated().map { "<div>\($0.offset + 1). \(escape($0.element.texto))</div>" }.joined()
            let right = item.columnaB.enumerated().map { "<div>\(letter($0.offset)). \(escape($0.element.texto))</div>" }.joined()
            let answer = mode == .pauta ? item.columnaA.compactMap { a -> String? in
                guard let aId = a.sourceId,
                      let b = item.columnaB.first(where: { $0.correctaParaAId == aId }),
                      let bIndex = item.columnaB.firstIndex(where: { $0.id == b.id }) else { return nil }
                return "\(escape(a.texto)) → \(letter(bIndex)). \(escape(b.texto))"
            }.joined(separator: "<br>") : ""
            body = "<table><tr><th>Columna A</th><th>Columna B</th></tr><tr><td>\(left)</td><td>\(right)</td></tr></table>" + (answer.isEmpty ? "" : "<div class='answer'>\(answer)</div>")
        case .ordenar:
            let steps: [PruebaPaso]
            if mode == .pauta || item.pasos.count < 2 { steps = item.pasos }
            else { steps = Array(item.pasos.dropFirst()) + Array(item.pasos.prefix(1)) }
            body = steps.enumerated().map { index, step in
                let order = mode == .pauta
                    ? String((item.pasos.firstIndex(where: { $0.id == step.id }) ?? index) + 1)
                    : "_____"
                return "<div>\(order) &nbsp; \(escape(step.texto))</div>"
            }.joined()
        case .completar:
            let expression = item.textoConBlancos ?? item.enunciado
            let completed = completionHTML(expression, answers: item.respuestasCorrectas, mode: mode)
            let bank = item.bancoPalabras.isEmpty ? "" : "<div><b>Banco:</b> \(item.bancoPalabras.map(escape).joined(separator: " · "))</div>"
            body = "<div>\(completed)</div>\(bank)"
        case .respuestaCorta:
            let answer = mode == .pauta && item.respuestaEsperada?.isEmpty == false
                ? "<div class='answer'><b>Esperada:</b> \(escape(item.respuestaEsperada ?? ""))</div>" : ""
            body = responseLines(item.lineasRespuesta ?? 2) + answer
        case .desarrollo:
            var answerParts: [String] = []
            if let guide = item.pautaCorreccion, !guide.isEmpty { answerParts.append("<b>Pauta:</b> \(escape(guide))") }
            if !item.criterios.isEmpty {
                answerParts.append("<b>Criterios:</b><ul>\(item.criterios.map { "<li>\(escape($0.texto)) (\(format($0.puntaje)) pts)</li>" }.joined())</ul>")
            }
            let answer = mode == .pauta && !answerParts.isEmpty ? "<div class='answer'>\(answerParts.joined(separator: "<br>"))</div>" : ""
            body = responseLines(item.lineasRespuesta ?? 5) + answer
        case .unknown:
            body = "<div class='answer'>Tipo de ítem no compatible con la exportación nativa; el documento Firestore no fue modificado.</div>"
        }
        return "<div class='test-item'>\(header)\(resources)\(body)</div>"
    }

    @MainActor
    private func renderPDF(html: String, school: InfoColegio, format: GuiaPDFResolvedFormat) -> Data {
        let renderer = A4PrintRenderer()
        renderer.school = school
        renderer.headerMode = format.headerMode
        renderer.titleAlignment = format.titleAlignment == "left" ? .left : .center
        renderer.headerAccent = UIColor(epHex: format.headerAccent) ?? UIColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1)
        renderer.marginTop = CGFloat(format.marginTopMM * 72 / 25.4)
        renderer.marginRight = CGFloat(format.marginRightMM * 72 / 25.4)
        renderer.marginBottom = CGFloat(format.marginBottomMM * 72 / 25.4)
        renderer.marginLeft = CGFloat(format.marginLeftMM * 72 / 25.4)
        renderer.footerText = format.footerText
        renderer.showsPageNumber = format.showsPageNumber
        renderer.headerHeight = renderer.preferredHeaderHeight
        renderer.footerHeight = renderer.preferredFooterHeight
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        let pageCount = renderer.numberOfPages
        guard pageCount > 0 else { return Data() }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pageCount))
        let pdf = UIGraphicsPDFRenderer(bounds: renderer.paperRect)
        return pdf.pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                renderer.drawPage(at: page, in: renderer.paperRect)
            }
        }
    }

    private func outputURL(guide: GuiaTemplate, mode: GuiaPDFMode) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EduPanelExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = mode == .pauta ? "-pauta.pdf" : "-alumno.pdf"
        let base = sanitizeFileName(guide.nombre.isEmpty ? "guia" : plainText(guide.nombre), limit: 90)
        return directory.appendingPathComponent("\(base)\(suffix)")
    }

    private func outputURL(test: PruebaTemplate, mode: GuiaPDFMode) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EduPanelExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = mode == .pauta ? "-pauta.pdf" : "-alumno.pdf"
        let base = sanitizeFileName(test.nombre.isEmpty ? "prueba" : plainText(test.nombre), limit: 90)
        return directory.appendingPathComponent("\(base)\(suffix)")
    }

    private func fact(_ label: String, _ value: String) -> String { "<td><b>\(escape(label)):</b> \(escape(value))</td>" }
    private func responseLines(_ count: Int) -> String { (0..<min(100, max(1, count))).map { _ in "<div class='line'></div>" }.joined() }
    private func letter(_ index: Int) -> String {
        UnicodeScalar(97 + min(25, max(0, index))).map { String($0) } ?? "a"
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func imageSource(_ value: String?, images: [String: String]) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return images[value]
    }
    private func optionImage(_ value: String?, images: [String: String]) -> String {
        guard let value, !value.isEmpty else { return "" }
        return imageSource(value, images: images)
            .map { "<br><img src='\($0)' alt='Imagen de opción'>" }
            ?? "<div class='image-missing'>Imagen no disponible</div>"
    }
    private func twoColumnTable(_ items: [String]) -> String {
        let rows = stride(from: 0, to: items.count, by: 2).map { index in
            let second = index + 1 < items.count ? "<td>\(items[index + 1])</td>" : "<td></td>"
            return "<tr><td>\(items[index])</td>\(second)</tr>"
        }.joined()
        return "<table class='two-column'><tbody>\(rows)</tbody></table>"
    }
    private func sourceId(from path: String) -> String? {
        let value = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return value.isEmpty || value == "missing" ? nil : value
    }
    private func completionHTML(_ value: String, answers: [String], mode: GuiaPDFMode) -> String {
        guard let expression = try? NSRegularExpression(pattern: "__+") else { return escape(value) }
        let matches = expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
        guard !matches.isEmpty else { return escape(value) }
        var result = ""
        var cursor = value.startIndex
        for (index, match) in matches.enumerated() {
            guard let range = Range(match.range, in: value) else { continue }
            result += escape(String(value[cursor..<range.lowerBound]))
            if mode == .pauta {
                let answer = answers.indices.contains(index) ? answers[index] : "____"
                result += "<u class='inline-answer'>\(escape(answer))</u>"
            } else {
                result += "<u>__________</u>"
            }
            cursor = range.upperBound
        }
        result += escape(String(value[cursor...]))
        return result
    }
    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    private func plainText(_ value: String) -> String {
        var result = value.replacingOccurrences(
            of: "(?is)</?[a-z][^>]*>", with: " ", options: .regularExpression
        )
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&#160;", " "),
            ("&aacute;", "á"), ("&eacute;", "é"), ("&iacute;", "í"), ("&oacute;", "ó"), ("&uacute;", "ú"),
            ("&Aacute;", "Á"), ("&Eacute;", "É"), ("&Iacute;", "Í"), ("&Oacute;", "Ó"), ("&Uacute;", "Ú"),
            ("&ntilde;", "ñ"), ("&Ntilde;", "Ñ"), ("&uuml;", "ü"), ("&Uuml;", "Ü"),
            ("&iquest;", "¿"), ("&iexcl;", "¡"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func safeRichHTML(_ value: String) -> String {
        var result = value
        for pattern in [
            "(?is)<(script|style|iframe|object|embed)[^>]*>.*?</\\1>",
            "(?is)<(script|style|iframe|object|embed|link|meta|base|img)[^>]*?/?>",
            "(?i)\\son[a-z]+\\s*=\\s*(?:['\"][^'\"]*['\"]|[^\\s>]+)",
            "(?i)javascript:"
        ] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }
    private func sanitizeFileName(_ value: String, limit: Int) -> String {
        let folded = value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_CL"))
        let clean = folded.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((clean.isEmpty ? "documento" : clean).prefix(limit))
    }
}

@MainActor
private final class A4PrintRenderer: UIPrintPageRenderer {
    private let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    var school: InfoColegio = .empty
    var headerMode: ExportHeaderMode = .completo
    var titleAlignment: NSTextAlignment = .center
    var headerAccent = UIColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1)
    var marginTop: CGFloat = 34
    var marginRight: CGFloat = 39.7
    var marginBottom: CGFloat = 36.9
    var marginLeft: CGFloat = 39.7
    var footerText = ""
    var showsPageNumber = false

    private var hasFullInstitutionalHeader: Bool {
        headerMode == .completo && school.encabezadoHabilitado && (
            !school.nombre.isEmpty || !school.encabezadoTextoIzq.isEmpty || !school.encabezadoTextoDer.isEmpty ||
            school.logoBase64 != nil || school.logoDerBase64 != nil
        )
    }

    var hasInstitutionalHeader: Bool {
        switch headerMode {
        case .oculto: return false
        case .compacto: return !school.nombre.isEmpty
        case .completo: return hasFullInstitutionalHeader || !school.nombre.isEmpty
        }
    }

    var preferredHeaderHeight: CGFloat {
        hasFullInstitutionalHeader ? 58 : (hasInstitutionalHeader ? 28 : 0)
    }

    var preferredFooterHeight: CGFloat {
        guard !footerText.isEmpty || showsPageNumber else { return 0 }
        return footerText.count > 90 || footerText.contains("\n") ? 34 : 22
    }

    override var paperRect: CGRect { page }
    override var printableRect: CGRect {
        CGRect(
            x: marginLeft,
            y: marginTop,
            width: max(1, page.width - marginLeft - marginRight),
            height: max(1, page.height - marginTop - marginBottom)
        )
    }

    override func drawHeaderForPage(at pageIndex: Int, in headerRect: CGRect) {
        guard hasInstitutionalHeader else { return }
        if !hasFullInstitutionalHeader {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = headerMode == .compacto ? titleAlignment : .center
            NSAttributedString(string: school.nombre, attributes: [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]).draw(in: headerRect.insetBy(dx: 0, dy: 5))
            drawHeaderSeparator(in: headerRect)
            return
        }
        let contentRect = headerRect.insetBy(dx: 0, dy: 5)
        let logoSize = min(38, contentRect.height - 8)
        let leftLogoRect = CGRect(x: contentRect.minX, y: contentRect.midY - logoSize / 2, width: logoSize, height: logoSize)
        let rightLogoRect = CGRect(x: contentRect.maxX - logoSize, y: leftLogoRect.minY, width: logoSize, height: logoSize)
        drawLogo(school.logoBase64, in: leftLogoRect)
        drawLogo(school.logoDerBase64, in: rightLogoRect)

        let leftInset = school.logoBase64 == nil ? 0 : logoSize + 8
        let rightInset = school.logoDerBase64 == nil ? 0 : logoSize + 8
        let textRect = CGRect(
            x: contentRect.minX + leftInset,
            y: contentRect.minY + 2,
            width: max(1, contentRect.width - leftInset - rightInset),
            height: contentRect.height - 9
        )
        drawHeaderText(in: textRect)

        drawHeaderSeparator(in: headerRect)
    }

    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        guard preferredFooterHeight > 0 else { return }
        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: footerRect.minX, y: footerRect.minY + 1))
        separator.addLine(to: CGPoint(x: footerRect.maxX, y: footerRect.minY + 1))
        headerAccent.setStroke()
        separator.lineWidth = 0.6
        separator.stroke()

        var components: [String] = []
        if !footerText.isEmpty { components.append(footerText) }
        if showsPageNumber { components.append("Página \(pageIndex + 1) de \(numberOfPages)") }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(string: components.joined(separator: " · "), attributes: [
            .font: UIFont.systemFont(ofSize: 8.5),
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: paragraph
        ]).draw(in: footerRect.insetBy(dx: 0, dy: 6))
    }

    private func drawHeaderText(in rect: CGRect) {
        let halfWidth = rect.width / 2
        let leftText = school.encabezadoTextoIzq.isEmpty ? school.nombre : school.encabezadoTextoIzq
        drawDetail(leftText, alignment: .left,
                   in: CGRect(x: rect.minX, y: rect.minY, width: halfWidth - 4, height: rect.height))
        drawDetail(school.encabezadoTextoDer, alignment: .right,
                   in: CGRect(x: rect.midX + 4, y: rect.minY, width: halfWidth - 4, height: rect.height))
    }

    private func drawHeaderSeparator(in rect: CGRect) {
        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: rect.minX, y: rect.maxY - 1))
        separator.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
        headerAccent.setStroke()
        separator.lineWidth = 0.6
        separator.stroke()
    }

    private func drawDetail(_ value: String, alignment: NSTextAlignment, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5),
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: value, attributes: attributes).draw(in: rect)
    }

    private func drawLogo(_ encoded: String?, in rect: CGRect) {
        guard let encoded,
              let payload = encoded.split(separator: ",", maxSplits: 1).last.map(String.init),
              let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              let image = UIImage(data: data) else { return }
        image.draw(in: aspectFitRect(for: image.size, inside: rect))
    }

    private func aspectFitRect(for size: CGSize, inside rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

private extension UIColor {
    convenience init?(epHex value: String) {
        let raw = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let expanded: String
        if raw.count == 3 {
            expanded = raw.map { "\($0)\($0)" }.joined()
        } else if raw.count == 6 {
            expanded = raw
        } else {
            return nil
        }
        guard let number = UInt64(expanded, radix: 16) else { return nil }
        self.init(
            red: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum GuiaPDFExportError: LocalizedError {
    case emptyPDF
    var errorDescription: String? { "No se pudo generar el documento PDF." }
}
