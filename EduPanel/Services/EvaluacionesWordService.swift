import Foundation

struct EvaluacionesWordArtifact: Identifiable {
    let id = UUID()
    let url: URL
}

struct PruebaWordImportResult {
    let section: PruebaSectionDraft
    let warning: String
}

struct EvaluacionesWordService {
    func importTest(from url: URL) throws -> PruebaWordImportResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 10 * 1_024 * 1_024 else { throw EvaluacionesWordError.fileTooLarge }

        let attributed = try NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        let lines = attributed.string.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw EvaluacionesWordError.emptyDocument }

        var groups: [[String]] = []
        for line in lines {
            if isQuestionStart(line), !groups.isEmpty { groups.append([line]) }
            else if groups.isEmpty { groups = [[line]] }
            else { groups[groups.count - 1].append(line) }
        }

        var section = PruebaSectionDraft.nueva(order: 1)
        section.titulo = "Contenido importado desde Word"
        section.instrucciones = "Revisa enunciados, alternativas y respuestas antes de aplicar."
        section.items = groups.prefix(50).compactMap(makeTestItem)
        guard !section.items.isEmpty else { throw EvaluacionesWordError.emptyDocument }
        section.tipoPredominante = section.items.first?.type ?? PruebaEditorItemType.respuestaCorta.rawValue
        section.baselineFingerprint = section.contentFingerprint
        return PruebaWordImportResult(
            section: section,
            warning: "Word se importó de forma aproximada. En preguntas con alternativas se marcó la primera como correcta: revísala antes de guardar."
        )
    }

    func export(test: PruebaEditorDraft) throws -> EvaluacionesWordArtifact {
        var lines = [test.nombre.isEmpty ? "Prueba" : test.nombre, "\(test.asignatura) · \(test.curso)", ""]
        var number = 0
        for section in test.secciones where !section.isDeleted {
            lines.append(section.titulo)
            for item in section.items where !item.isDeleted {
                number += 1
                lines.append("\(number). \(item.enunciado)")
                appendTestDetails(item, to: &lines)
                lines.append("")
            }
        }
        return try write(lines: lines, name: test.nombre.isEmpty ? "prueba" : test.nombre)
    }

    func export(guide: GuiaEditorDraft) throws -> EvaluacionesWordArtifact {
        var lines = [guide.nombre.isEmpty ? "Guía" : guide.nombre, "\(guide.asignatura) · \(guide.curso)", guide.objetivo, ""]
        var number = 0
        for section in guide.secciones {
            lines.append(section.titulo)
            if !section.descripcion.isEmpty { lines.append(section.descripcion) }
            for block in section.bloques where !block.isDeleted {
                let text = block.type == "texto" ? plainText(block.html) : block.caption
                if !text.isEmpty { lines.append(text) }
            }
            for activity in section.actividades where !activity.isDeleted {
                number += 1
                lines.append("\(number). \(activity.prompt)")
                activity.entriesA.filter { !$0.isDeleted }.enumerated().forEach { index, entry in
                    lines.append("\(letter(index)). \(entry.text)")
                }
                lines.append("")
            }
        }
        return try write(lines: lines, name: guide.nombre.isEmpty ? "guia" : guide.nombre)
    }

    private func makeTestItem(_ group: [String]) -> PruebaItemDraft? {
        guard let first = group.first else { return nil }
        let prompt = first.replacingOccurrences(of: "^\\s*\\d+[.)-]\\s*", with: "", options: .regularExpression)
        let alternatives = group.dropFirst().filter { $0.range(of: "^\\s*[A-Ha-h][.)-]\\s+", options: .regularExpression) != nil }
        if alternatives.count >= 2 {
            var item = PruebaItemDraft.nueva(type: PruebaEditorItemType.seleccionMultiple.rawValue)
            item.enunciado = prompt
            item.entriesA = alternatives.enumerated().map { index, value in
                var entry = PruebaItemEntryDraft.nueva(prefix: "alt", order: index + 1)
                entry.text = value.replacingOccurrences(of: "^\\s*[A-Ha-h][.)-]\\s+", with: "", options: .regularExpression)
                entry.correct = index == 0
                entry.baselineFingerprint = entry.contentFingerprint
                return entry
            }
            item.baselineFingerprint = item.contentFingerprint
            return item
        }
        var item = PruebaItemDraft.nueva(type: PruebaEditorItemType.respuestaCorta.rawValue)
        item.enunciado = ([prompt] + group.dropFirst()).joined(separator: " ")
        item.baselineFingerprint = item.contentFingerprint
        return item
    }

    private func appendTestDetails(_ item: PruebaItemDraft, to lines: inout [String]) {
        switch PruebaEditorItemType.resolve(item.type) {
        case .seleccionMultiple:
            item.entriesA.filter { !$0.isDeleted }.enumerated().forEach { index, entry in lines.append("\(letter(index)). \(entry.text)") }
        case .verdaderoFalso: lines.append("V / F")
        case .pareados:
            item.entriesA.filter { !$0.isDeleted }.forEach { lines.append("• \($0.text)") }
            item.entriesB.filter { !$0.isDeleted }.forEach { lines.append("• \($0.text)") }
        case .ordenar: item.entriesA.filter { !$0.isDeleted }.forEach { lines.append("___ \($0.text)") }
        case .completar: lines.append(item.textoConBlancos)
        case .respuestaCorta, .desarrollo: (0..<max(1, item.lineasRespuesta)).forEach { _ in lines.append("________________________________") }
        case nil: break
        }
    }

    private func write(lines: [String], name: String) throws -> EvaluacionesWordArtifact {
        let text = lines.joined(separator: "\n")
        let attributed = NSAttributedString(string: text)
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EduPanelExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_CL"))
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
        let url = directory.appendingPathComponent("\(base.isEmpty ? "documento" : base).rtf")
        try data.write(to: url, options: .atomic)
        return EvaluacionesWordArtifact(url: url)
    }

    private func isQuestionStart(_ value: String) -> Bool {
        value.range(of: "^\\s*\\d+[.)-]\\s+", options: .regularExpression) != nil
    }
    private func letter(_ index: Int) -> String { String(UnicodeScalar(65 + min(25, index))!) }
    private func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum EvaluacionesWordError: LocalizedError {
    case fileTooLarge
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "El archivo Word supera el máximo de 10 MB."
        case .emptyDocument: return "No se encontró texto importable en el archivo Word."
        }
    }
}
