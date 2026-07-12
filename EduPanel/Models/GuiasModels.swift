import Foundation
import FirebaseFirestore

struct GuiasCargaResultado {
    let guias: [GuiaTemplate]
    let isFromCache: Bool
    let warningCount: Int
}

struct GuiaEditorDraft: Equatable {
    var id: String?
    var nombre: String
    var asignatura: String
    var curso: String
    var unidadId: String
    var unidadNombre: String
    var numeroGuia: String
    var docenteNombre: String
    var tipoGuia: String
    var tiempoMinutos: Int
    var objetivo: String
    var instrucciones: [String]
    var estado: String
    var secciones: [GuiaSectionDraft]
    var cierre: [GuiaBlockDraft]
    var oas: [OAEditado]?

    static func nueva(curso: String, asignatura: String) -> Self {
        Self(
            id: nil, nombre: "", asignatura: asignatura, curso: curso,
            unidadId: "", unidadNombre: "", numeroGuia: "", docenteNombre: "",
            tipoGuia: "aprendizaje", tiempoMinutos: 45, objetivo: "",
            instrucciones: [
                "Lee atentamente el contenido y desarrolla cada actividad.",
                "Responde con letra clara y ordenada.",
                "Si tienes dudas, consulta al profesor."
            ],
            estado: "borrador", secciones: [], cierre: [], oas: []
        )
    }

    static func from(_ guide: GuiaTemplate) -> Self {
        Self(
            id: guide.id, nombre: guide.nombre, asignatura: guide.asignatura, curso: guide.curso,
            unidadId: guide.unidadId ?? "", unidadNombre: guide.unidadNombre ?? "",
            numeroGuia: guide.numeroGuia ?? "", docenteNombre: guide.docenteNombre ?? "",
            tipoGuia: guide.tipoGuia, tiempoMinutos: guide.tiempoMinutos ?? 45,
            objetivo: guide.objetivo, instrucciones: guide.instrucciones, estado: guide.estado,
            secciones: guide.secciones.map { GuiaSectionDraft.from($0) },
            cierre: guide.cierre.map { GuiaBlockDraft.from($0) }, oas: guide.oas
        )
    }

    var isValid: Bool {
        !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !curso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GuiaSectionDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var orden: Int
    var titulo: String
    var descripcion: String
    var bloques: [GuiaBlockDraft]
    var actividades: [GuiaActivityDraft]
    var isNew: Bool
    var originalIndex: Int?

    var activityCount: Int { actividades.filter { !$0.isDeleted }.count }

    static func nueva(order: Int) -> Self {
        let id = "sec_\(UUID().uuidString.lowercased())"
        return Self(id: id, documentId: id, orden: order, titulo: "Sección \(order)",
             descripcion: "", bloques: [], actividades: [], isNew: true, originalIndex: nil)
    }

    static func from(_ section: GuiaSeccion) -> Self {
        Self(id: section.id, documentId: section.sourceId ?? "sec_\(UUID().uuidString.lowercased())", orden: section.orden, titulo: section.titulo,
             descripcion: section.descripcion ?? "", bloques: section.contenido.map { GuiaBlockDraft.from($0) },
             actividades: section.actividades.map { GuiaActivityDraft.from($0) }, isNew: false,
             originalIndex: sourceIndex(from: section.id, marker: "section"))
    }

    private static func sourceIndex(from path: String, marker: String) -> Int? {
        let parts = path.split(separator: "/").map(String.init)
        guard let markerIndex = parts.firstIndex(of: marker), parts.indices.contains(markerIndex + 1) else { return nil }
        return Int(parts[markerIndex + 1])
    }
}

struct GuiaActivityEntryDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var text: String
    var correct: Bool
    var imageUrl: String
    var linkedId: String
    var correctOrder: Int
    var originalIndex: Int?
    var isNew: Bool
    var isDeleted: Bool
    var baselineFingerprint: String

    static func nueva(prefix: String, order: Int) -> Self {
        let id = "\(prefix)_\(UUID().uuidString.lowercased())"
        return Self(id: id, documentId: id, text: "", correct: false, imageUrl: "", linkedId: "",
                    correctOrder: order, originalIndex: nil, isNew: true, isDeleted: false,
                    baselineFingerprint: "")
    }

    var contentFingerprint: String {
        [text, correct.description, imageUrl, linkedId, String(correctOrder), isDeleted.description]
            .joined(separator: "\u{1F}")
    }
}

struct GuiaActivityDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var type: String
    var number: Int
    var prompt: String
    var score: Double?
    var resources: [GuiaBlockDraft]
    var linkedOA: String
    var entriesA: [GuiaActivityEntryDraft]
    var entriesB: [GuiaActivityEntryDraft]
    var text: String
    var answers: [String]
    var wordBank: [String]
    var lines: Int
    var suggestedAnswer: String
    var instruction: String
    var imageUrl: String
    var heightCm: Double
    var words: [String]
    var gridSize: Int
    var isUnknown: Bool
    var isNew: Bool
    var originalIndex: Int?
    var isDeleted: Bool
    var baselineFingerprint: String

    static func nueva(type: String, number: Int) -> Self {
        let id = "\(type)_\(UUID().uuidString.lowercased())"
        var draft = Self(
            id: id, documentId: id, type: type, number: number, prompt: "", score: nil,
            resources: [], linkedOA: "", entriesA: [], entriesB: [], text: "", answers: [],
            wordBank: [], lines: 3, suggestedAnswer: "", instruction: "", imageUrl: "",
            heightCm: 5, words: [], gridSize: 10, isUnknown: false, isNew: true,
            originalIndex: nil, isDeleted: false, baselineFingerprint: ""
        )
        switch type {
        case "seleccion_multiple", "encerrar", "marcar":
            draft.entriesA = (1...4).map { .nueva(prefix: "op", order: $0) }
        case "verdadero_falso":
            draft.entriesA = [.nueva(prefix: "af", order: 1)]
        case "ordenar":
            draft.entriesA = (1...3).map { .nueva(prefix: "paso", order: $0) }
        case "pareados":
            draft.entriesA = (1...3).map { .nueva(prefix: "a", order: $0) }
            draft.entriesB = (1...3).map { .nueva(prefix: "b", order: $0) }
        default: break
        }
        return draft
    }

    static func from(_ activity: GuiaActividad) -> Self {
        var draft = Self(
            id: activity.id,
            documentId: activity.sourceId ?? "\(activity.kind.rawValue)_\(UUID().uuidString.lowercased())",
            type: activity.rawType, number: activity.numero, prompt: activity.enunciado,
            score: activity.puntaje, resources: activity.recursos.map { GuiaBlockDraft.from($0) },
            linkedOA: activity.oaVinculado ?? "",
            entriesA: primaryEntries(activity), entriesB: secondaryEntries(activity),
            text: activity.textoCompletar ?? "", answers: activity.respuestas,
            wordBank: activity.banco, lines: activity.lineas ?? 3,
            suggestedAnswer: activity.respuestaSugerida ?? "", instruction: activity.instruccion ?? "",
            imageUrl: activity.imagenUrl ?? "", heightCm: activity.alturaCm ?? 5,
            words: activity.palabras, gridSize: min(20, max(4, activity.tamanoCuadro ?? 10)),
            isUnknown: activity.kind == .desconocida, isNew: false,
            originalIndex: sourceIndex(from: activity.id), isDeleted: false, baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    private static func primaryEntries(_ activity: GuiaActividad) -> [GuiaActivityEntryDraft] {
        if !activity.opciones.isEmpty {
            return activity.opciones.enumerated().map { index, value in
                entry(id: value.id, text: value.texto, correct: value.correcta ?? false,
                      image: value.imagenUrl ?? "", linked: "", order: index + 1, index: index)
            }
        }
        if !activity.afirmaciones.isEmpty {
            return activity.afirmaciones.enumerated().map { index, value in
                entry(id: value.id, text: value.texto, correct: value.correcta ?? false,
                      image: "", linked: "", order: index + 1, index: index)
            }
        }
        if !activity.pasos.isEmpty {
            return activity.pasos.enumerated().map { index, value in
                entry(id: value.id, text: value.texto, correct: false, image: "", linked: "",
                      order: value.numeroCorrecto ?? index + 1, index: index)
            }
        }
        return activity.columnaA.enumerated().map { index, value in
            entry(id: value.id, text: value.texto, correct: false, image: "", linked: value.pareCon ?? "",
                  order: index + 1, index: index)
        }
    }

    private static func secondaryEntries(_ activity: GuiaActividad) -> [GuiaActivityEntryDraft] {
        activity.columnaB.enumerated().map { index, value in
            entry(id: value.id, text: value.texto, correct: false, image: "", linked: value.pareCon ?? "",
                  order: index + 1, index: index)
        }
    }

    private static func entry(
        id path: String, text: String, correct: Bool, image: String,
        linked: String, order: Int, index: Int
    ) -> GuiaActivityEntryDraft {
        let source = sourceId(from: path) ?? "entrada_\(UUID().uuidString.lowercased())"
        return GuiaActivityEntryDraft(
            id: path, documentId: source, text: text, correct: correct, imageUrl: image,
            linkedId: linked, correctOrder: order, originalIndex: index, isNew: false, isDeleted: false,
            baselineFingerprint: [text, correct.description, image, linked, String(order), false.description]
                .joined(separator: "\u{1F}")
        )
    }

    private static func sourceIndex(from path: String) -> Int? {
        let parts = path.split(separator: "/").map(String.init)
        guard let marker = parts.firstIndex(of: "activity"), parts.indices.contains(marker + 1) else { return nil }
        return Int(parts[marker + 1])
    }

    private static func sourceId(from path: String) -> String? {
        let last = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return last.isEmpty || last == "missing" ? nil : last
    }

    var contentFingerprint: String {
        let entryA = entriesA.map { entryFingerprint($0) }.joined(separator: "\u{1E}")
        let entryB = entriesB.map { entryFingerprint($0) }.joined(separator: "\u{1E}")
        let resourceState = resources.map(\.contentFingerprint).joined(separator: "\u{1E}")
        return [type, String(number), prompt, score.map { String($0) } ?? "nil", linkedOA, entryA, entryB, text,
                answers.joined(separator: "\u{1F}"), wordBank.joined(separator: "\u{1F}"), String(lines),
                suggestedAnswer, instruction, imageUrl, String(heightCm), words.joined(separator: "\u{1F}"),
                String(gridSize), resourceState, isDeleted.description].joined(separator: "\u{1D}")
    }

    private func entryFingerprint(_ entry: GuiaActivityEntryDraft) -> String {
        entry.contentFingerprint
    }
}

struct GuiaBlockDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var type: String
    var html: String
    var style: String
    var url: String
    var storagePath: String
    var alt: String
    var caption: String
    var width: String
    var alignment: String
    var headers: [String]
    var rows: [[String]]
    var firstColumnHeader: Bool
    var separatorStyle: String
    var isNew: Bool
    var isUnknown: Bool
    var originalIndex: Int?
    var isDeleted: Bool
    var baselineFingerprint: String

    static func nueva(type: String) -> Self {
        let id = "bloque_\(UUID().uuidString.lowercased())"
        return Self(
            id: id, documentId: id, type: type,
            html: "", style: "normal", url: "", storagePath: "", alt: "", caption: "",
            width: "medium", alignment: "centro",
            headers: type == "tabla" ? ["Columna 1", "Columna 2"] : [],
            rows: type == "tabla" ? [["", ""]] : [], firstColumnHeader: false,
            separatorStyle: "linea", isNew: true, isUnknown: false, originalIndex: nil, isDeleted: false,
            baselineFingerprint: ""
        )
    }

    static func from(_ block: PruebaContentBlock) -> Self {
        let separatorData = block.raw["data"] as? [String: Any]
        var draft = Self(
            id: block.id, documentId: block.sourceId ?? "bloque_\(UUID().uuidString.lowercased())", type: block.rawType,
            html: block.html ?? "", style: block.estilo ?? "normal", url: block.url ?? "",
            storagePath: block.storagePath ?? "", alt: block.alt ?? "", caption: block.caption ?? "",
            width: block.ancho ?? "medium", alignment: block.alineacion ?? "centro",
            headers: block.cabeceras, rows: block.filas, firstColumnHeader: block.primeraColumnaCabecera,
            separatorStyle: (separatorData?["estilo"] as? String) ?? "linea",
            isNew: false, isUnknown: block.kind.isUnknown,
            originalIndex: sourceIndex(from: block.id), isDeleted: false, baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    private static func sourceIndex(from path: String) -> Int? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return Int(parts[parts.count - 2])
    }

    var contentFingerprint: String {
        [type, html, style, url, storagePath, alt, caption, width, alignment,
         headers.joined(separator: "\u{1F}"), rows.map { $0.joined(separator: "\u{1F}") }.joined(separator: "\u{1E}"),
         firstColumnHeader.description, separatorStyle, isDeleted.description].joined(separator: "\u{1D}")
    }
}

enum GuiaActividadKind: String, CaseIterable, Equatable {
    case seleccionMultiple = "seleccion_multiple"
    case verdaderoFalso = "verdadero_falso"
    case completar
    case respuestaCorta = "respuesta_corta"
    case ordenar
    case pareados
    case encerrar
    case marcar
    case colorear
    case dibujar
    case investigar
    case sopaLetras = "sopa_letras"
    case abierta
    case desconocida

    static func resolve(_ value: String) -> Self {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "-", with: "_")
        return Self(rawValue: normalized) ?? .desconocida
    }

    var label: String {
        switch self {
        case .seleccionMultiple: return "Selección múltiple"
        case .verdaderoFalso: return "Verdadero o falso"
        case .completar: return "Completar"
        case .respuestaCorta: return "Respuesta corta"
        case .ordenar: return "Ordenar"
        case .pareados: return "Pareados"
        case .encerrar: return "Encerrar"
        case .marcar: return "Marcar"
        case .colorear: return "Colorear"
        case .dibujar: return "Dibujar"
        case .investigar: return "Investigar"
        case .sopaLetras: return "Sopa de letras"
        case .abierta: return "Respuesta abierta"
        case .desconocida: return "Actividad compatible"
        }
    }
}

struct GuiaOpcion: Identifiable {
    let id: String
    let texto: String
    let correcta: Bool?
    let imagenUrl: String?
}

struct GuiaAfirmacion: Identifiable {
    let id: String
    let texto: String
    let correcta: Bool?
}

struct GuiaPaso: Identifiable {
    let id: String
    let texto: String
    let numeroCorrecto: Int?
}

struct GuiaPareado: Identifiable {
    let id: String
    let texto: String
    let pareCon: String?
}

struct GuiaActividad: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let rawType: String
    let kind: GuiaActividadKind
    let numero: Int
    let enunciado: String
    let puntaje: Double?
    let recursos: [PruebaContentBlock]
    let oaVinculado: String?
    let opciones: [GuiaOpcion]
    let afirmaciones: [GuiaAfirmacion]
    let textoCompletar: String?
    let respuestas: [String]
    let banco: [String]
    let lineas: Int?
    let respuestaSugerida: String?
    let pasos: [GuiaPaso]
    let columnaA: [GuiaPareado]
    let columnaB: [GuiaPareado]
    let instruccion: String?
    let imagenUrl: String?
    let alturaCm: Double?
    let palabras: [String]
    let tamanoCuadro: Int?
}

struct GuiaSeccion: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let orden: Int
    let titulo: String
    let descripcion: String?
    let contenido: [PruebaContentBlock]
    let actividades: [GuiaActividad]
}

struct GuiaTemplate: Identifiable {
    let id: String
    let raw: [String: Any]
    let scope: EvaluacionScope
    let isFromCache: Bool
    let nombre: String
    let asignatura: String
    let curso: String
    let unidadId: String?
    let unidadNombre: String?
    let numeroGuia: String?
    let docenteNombre: String?
    let tipoGuia: String
    let tiempoMinutos: Int?
    let objetivo: String
    let instrucciones: [String]
    let objetivos: [String]
    let indicadores: [String]
    let objetivosTransversales: [String]
    let oas: [OAEditado]?
    let secciones: [GuiaSeccion]
    let cierre: [PruebaContentBlock]
    let puntajeMaximo: Double
    let estado: String
    let fechaCreacion: Date?
    let fechaActualizacion: Date?
    let issues: [String]

    var totalActividades: Int { secciones.reduce(0) { $0 + $1.actividades.count } }
    var totalBloques: Int { secciones.reduce(cierre.count) { $0 + $1.contenido.count } }
    var tieneContenidoDesconocido: Bool {
        secciones.contains { section in
            section.contenido.contains { $0.kind.isUnknown } ||
            section.actividades.contains { activity in
                activity.kind == .desconocida || activity.recursos.contains { $0.kind.isUnknown }
            }
        } || cierre.contains { $0.kind.isUnknown }
    }
}

enum GuiaDocumentParser {
    static func guia(
        id: String,
        dictionary: [String: Any],
        scope: EvaluacionScope,
        isFromCache: Bool
    ) -> GuiaTemplate {
        var issues: [String] = []
        let sections = ReadGuia.dictionaryArray(dictionary["secciones"]).enumerated().map { index, value in
            section(value, path: "guia/\(id)/section/\(index)", fallbackOrder: index + 1, issues: &issues)
        }.sorted { $0.orden < $1.orden }
        let metadata = ReadGuia.dictionary(dictionary["metadatosCurriculares"]) ?? [:]
        let closing = blocks(dictionary["cierre"], path: "guia/\(id)/closing", issues: &issues)
        let calculatedScore = sections.flatMap(\.actividades).compactMap(\.puntaje).reduce(0, +)

        return GuiaTemplate(
            id: id,
            raw: dictionary,
            scope: scope,
            isFromCache: isFromCache,
            nombre: ReadGuia.string(dictionary["nombre"]),
            asignatura: ReadGuia.string(dictionary["asignatura"]),
            curso: ReadGuia.string(dictionary["curso"]),
            unidadId: ReadGuia.optionalString(dictionary["unidadId"]),
            unidadNombre: ReadGuia.optionalString(dictionary["unidadNombre"]),
            numeroGuia: ReadGuia.optionalString(dictionary["numeroGuia"]),
            docenteNombre: ReadGuia.optionalString(dictionary["docenteNombre"]),
            tipoGuia: ReadGuia.optionalString(dictionary["tipoGuia"]) ?? "aprendizaje",
            tiempoMinutos: ReadGuia.int(dictionary["tiempoMinutos"]),
            objetivo: ReadGuia.string(dictionary["objetivo"]),
            instrucciones: ReadGuia.stringArray(dictionary["instrucciones"]),
            objetivos: ReadGuia.stringArray(metadata["objetivos"]),
            indicadores: ReadGuia.stringArray(metadata["indicadores"]),
            objetivosTransversales: ReadGuia.stringArray(metadata["objetivosTransversales"]),
            oas: ReadGuia.decode([OAEditado].self, dictionary["oas"]),
            secciones: sections,
            cierre: closing,
            puntajeMaximo: ReadGuia.double(dictionary["puntajeMaximo"]) ?? calculatedScore,
            estado: ReadGuia.optionalString(dictionary["estado"]) ?? "borrador",
            fechaCreacion: ReadGuia.date(dictionary["createdAt"]),
            fechaActualizacion: ReadGuia.date(dictionary["updatedAt"]),
            issues: issues
        )
    }

    private static func section(
        _ dictionary: [String: Any],
        path: String,
        fallbackOrder: Int,
        issues: inout [String]
    ) -> GuiaSeccion {
        let sourceId = ReadGuia.optionalString(dictionary["id"])
        let activities = ReadGuia.dictionaryArray(dictionary["actividades"]).enumerated().map { index, value in
            activity(value, path: "\(path)/activity/\(index)", fallbackNumber: index + 1, issues: &issues)
        }
        return GuiaSeccion(
            id: "\(path)/\(sourceId ?? "missing")",
            sourceId: sourceId,
            raw: dictionary,
            orden: ReadGuia.int(dictionary["orden"]) ?? fallbackOrder,
            titulo: ReadGuia.optionalString(dictionary["titulo"]) ?? "Sección \(fallbackOrder)",
            descripcion: ReadGuia.optionalString(dictionary["descripcion"]),
            contenido: blocks(dictionary["contenido"], path: "\(path)/content", issues: &issues),
            actividades: activities
        )
    }

    private static func activity(
        _ dictionary: [String: Any],
        path: String,
        fallbackNumber: Int,
        issues: inout [String]
    ) -> GuiaActividad {
        let sourceId = ReadGuia.optionalString(dictionary["id"])
        let rawType = ReadGuia.string(dictionary["tipo"])
        let kind = GuiaActividadKind.resolve(rawType)
        if kind == .desconocida { issues.append("Actividad de tipo '\(rawType.isEmpty ? "sin tipo" : rawType)' preservada.") }
        let data = ReadGuia.dictionary(dictionary["datos"]) ?? [:]

        return GuiaActividad(
            id: "\(path)/\(sourceId ?? "missing")",
            sourceId: sourceId,
            raw: dictionary,
            rawType: rawType,
            kind: kind,
            numero: ReadGuia.int(dictionary["numero"]) ?? fallbackNumber,
            enunciado: ReadGuia.string(dictionary["enunciado"]),
            puntaje: ReadGuia.double(dictionary["puntaje"]),
            recursos: blocks(dictionary["recursos"], path: "\(path)/resource", issues: &issues),
            oaVinculado: ReadGuia.optionalString(dictionary["oaVinculado"]),
            opciones: options(data["alternativas"] ?? data["opciones"], path: "\(path)/option"),
            afirmaciones: affirmations(data["afirmaciones"], path: "\(path)/affirmation"),
            textoCompletar: ReadGuia.optionalString(data["texto"]),
            respuestas: ReadGuia.stringArray(data["respuestas"]),
            banco: ReadGuia.stringArray(data["banco"]),
            lineas: ReadGuia.int(data["lineas"] ?? data["lineasRespuesta"]),
            respuestaSugerida: ReadGuia.optionalString(data["respuestaSugerida"]),
            pasos: steps(data["pasos"], path: "\(path)/step"),
            columnaA: pairs(data["columnaA"], path: "\(path)/column-a"),
            columnaB: pairs(data["columnaB"], path: "\(path)/column-b"),
            instruccion: ReadGuia.optionalString(data["instruccion"]),
            imagenUrl: ReadGuia.optionalString(data["imagenUrl"]),
            alturaCm: ReadGuia.double(data["alturaCm"]),
            palabras: ReadGuia.stringArray(data["palabras"]),
            tamanoCuadro: ReadGuia.int(data["tamañoCuadro"] ?? data["tamanoCuadro"])
        )
    }

    private static func blocks(_ value: Any?, path: String, issues: inout [String]) -> [PruebaContentBlock] {
        ReadGuia.dictionaryArray(value).enumerated().map { index, dictionary in
            let sourceId = ReadGuia.optionalString(dictionary["id"])
            let rawType = ReadGuia.string(dictionary["tipo"])
            let kind = PruebaContentBlockKind.resolve(rawType)
            if kind == PruebaContentBlockKind.unknown { issues.append("Bloque '\(rawType.isEmpty ? "sin tipo" : rawType)' preservado.") }
            let data = ReadGuia.dictionary(dictionary["data"]) ?? [:]
            return PruebaContentBlock(
                id: "\(path)/\(index)/\(sourceId ?? "missing")", sourceId: sourceId,
                raw: dictionary, rawType: rawType, kind: kind,
                html: ReadGuia.optionalString(data["html"]), estilo: ReadGuia.optionalString(data["estilo"]),
                url: ReadGuia.optionalString(data["url"]), storagePath: ReadGuia.optionalString(data["storagePath"]),
                alt: ReadGuia.optionalString(data["alt"]), caption: ReadGuia.optionalString(data["caption"]),
                ancho: ReadGuia.optionalString(data["ancho"]), alineacion: ReadGuia.optionalString(data["alineacion"]),
                cabeceras: ReadGuia.stringArray(data["cabeceras"]), filas: ReadGuia.nestedStringArray(data["filas"]),
                primeraColumnaCabecera: ReadGuia.bool(data["primeraColumnaCabecera"]) ?? false
            )
        }
    }

    private static func options(_ value: Any?, path: String) -> [GuiaOpcion] {
        ReadGuia.dictionaryArray(value).enumerated().map { index, item in
            GuiaOpcion(id: "\(path)/\(index)/\(ReadGuia.string(item["id"]))", texto: ReadGuia.string(item["texto"]),
                       correcta: ReadGuia.bool(item["correcta"]), imagenUrl: ReadGuia.optionalString(item["imagenUrl"]))
        }
    }

    private static func affirmations(_ value: Any?, path: String) -> [GuiaAfirmacion] {
        ReadGuia.dictionaryArray(value).enumerated().map { index, item in
            GuiaAfirmacion(id: "\(path)/\(index)/\(ReadGuia.string(item["id"]))", texto: ReadGuia.string(item["texto"]),
                           correcta: ReadGuia.bool(item["correcta"]))
        }
    }

    private static func steps(_ value: Any?, path: String) -> [GuiaPaso] {
        ReadGuia.dictionaryArray(value).enumerated().map { index, item in
            GuiaPaso(id: "\(path)/\(index)/\(ReadGuia.string(item["id"]))", texto: ReadGuia.string(item["texto"]),
                      numeroCorrecto: ReadGuia.int(item["numeroCorrecto"]))
        }
    }

    private static func pairs(_ value: Any?, path: String) -> [GuiaPareado] {
        ReadGuia.dictionaryArray(value).enumerated().map { index, item in
            GuiaPareado(id: "\(path)/\(index)/\(ReadGuia.string(item["id"]))", texto: ReadGuia.string(item["texto"]),
                        pareCon: ReadGuia.optionalString(item["pareCon"]))
        }
    }
}

private enum ReadGuia {
    static func string(_ value: Any?) -> String { optionalString(value) ?? "" }
    static func optionalString(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case is Bool: return nil
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }
    static func double(_ value: Any?) -> Double? {
        switch value {
        case is Bool: return nil
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value.replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }
    static func int(_ value: Any?) -> Int? { double(value).map { Int($0) } }
    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.intValue != 0 }
        if let value = value as? String {
            if ["true", "1", "si", "sí"].contains(value.lowercased()) { return true }
            if ["false", "0", "no"].contains(value.lowercased()) { return false }
        }
        return nil
    }
    static func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    static func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }
    static func stringArray(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { optionalString($0) } ?? []
    }
    static func nestedStringArray(_ value: Any?) -> [[String]] {
        (value as? [Any])?.map { stringArray($0) } ?? []
    }
    static func date(_ value: Any?) -> Date? {
        if let value = value as? Timestamp { return value.dateValue() }
        if let value = value as? Date { return value }
        if let seconds = double(value) { return Date(timeIntervalSince1970: seconds) }
        if let value = value as? String { return ISO8601DateFormatter().date(from: value) }
        return nil
    }
    static func decode<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
