import Foundation

// MARK: - Borrador de prueba

struct PruebaEditorDraft: Equatable {
    var id: String?
    var nombre: String
    var asignatura: String
    var curso: String
    var unidadId: String
    var unidadNombre: String
    var docenteNombre: String
    var tipoEvaluacion: String
    var ponderacion: Double
    var tiempoMinutos: Int
    var exigencia: Double
    var instruccionesGenerales: [String]
    var oas: [OAEditado]?
    var secciones: [PruebaSectionDraft]
    var estado: String
    var bloqueada: Bool
    var baselineFingerprint: String

    static func nueva(curso: String, asignatura: String) -> Self {
        var draft = Self(
            id: nil,
            nombre: "",
            asignatura: asignatura,
            curso: curso,
            unidadId: "",
            unidadNombre: "",
            docenteNombre: "",
            tipoEvaluacion: "sumativa",
            ponderacion: 15,
            tiempoMinutos: 90,
            exigencia: 0.6,
            instruccionesGenerales: [
                "Escribe tu nombre y apellido con letra clara.",
                "Escucha con atenci\u{00F3}n las instrucciones del docente previas a la evaluaci\u{00F3}n.",
                "Lee cada pregunta con detenci\u{00F3}n.",
                "Contesta tu evaluaci\u{00F3}n con l\u{00E1}piz de grafito y letra legible. Cuando est\u{00E9}s seguro/a de tus respuestas, m\u{00E1}rcalas con l\u{00E1}piz pasta.",
                "Revisa tu evaluaci\u{00F3}n antes de entregarla."
            ],
            oas: [],
            secciones: [.nueva(order: 1)],
            estado: "borrador",
            bloqueada: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.editableFingerprint
        return draft
    }

    static func from(_ test: PruebaTemplate) -> Self {
        var draft = Self(
            id: test.id,
            nombre: test.nombre,
            asignatura: test.asignatura,
            curso: test.curso,
            unidadId: test.unidadId ?? "",
            unidadNombre: test.unidadNombre ?? "",
            docenteNombre: test.docenteNombre ?? "",
            tipoEvaluacion: test.tipoEvaluacion,
            ponderacion: test.ponderacion ?? 0,
            tiempoMinutos: test.tiempoMinutos ?? 90,
            exigencia: test.exigencia,
            instruccionesGenerales: test.instruccionesGenerales,
            oas: test.oas,
            secciones: test.secciones.map(PruebaSectionDraft.from),
            estado: test.estado,
            bloqueada: test.bloqueada,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.editableFingerprint
        return draft
    }

    var isValid: Bool {
        !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !curso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var editableFingerprint: String {
        pruebaFingerprint([
            nombre,
            asignatura,
            curso,
            unidadId,
            unidadNombre,
            docenteNombre,
            tipoEvaluacion,
            pruebaDoubleFingerprint(ponderacion),
            String(tiempoMinutos),
            pruebaDoubleFingerprint(exigencia),
            pruebaFingerprint(instruccionesGenerales),
            pruebaOAsFingerprint(oas),
            pruebaFingerprint(secciones.map(\.contentFingerprint)),
            estado,
            bloqueada.description
        ])
    }
}

// MARK: - Secciones

struct PruebaSectionDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var sourceId: String?
    var orden: Int
    var titulo: String
    var instrucciones: String
    var estimulo: [GuiaBlockDraft]
    var tipoPredominante: String
    var items: [PruebaItemDraft]
    var isNew: Bool
    var originalIndex: Int?
    var isDeleted: Bool
    var baselineFingerprint: String

    static func nueva(order: Int, type: String = PruebaEditorItemType.seleccionMultiple.rawValue) -> Self {
        let documentId = "sec_\(UUID().uuidString.lowercased())"
        let itemType = PruebaEditorItemType.resolve(type) ?? .seleccionMultiple
        var draft = Self(
            id: "ui_\(UUID().uuidString.lowercased())",
            documentId: documentId,
            sourceId: documentId,
            orden: order,
            titulo: "\u{00CD}tem \(pruebaRoman(order))",
            instrucciones: itemType.defaultInstructions,
            estimulo: [],
            tipoPredominante: itemType.rawValue,
            items: [],
            isNew: true,
            originalIndex: nil,
            isDeleted: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    static func from(_ section: PruebaSeccion) -> Self {
        var draft = Self(
            id: section.id,
            documentId: section.sourceId ?? "sec_\(UUID().uuidString.lowercased())",
            sourceId: section.sourceId,
            orden: section.orden,
            titulo: section.titulo,
            instrucciones: section.instrucciones,
            estimulo: section.estimulo.map(GuiaBlockDraft.from),
            tipoPredominante: section.tipoPredominante ?? "",
            items: section.items.map(PruebaItemDraft.from),
            isNew: false,
            originalIndex: pruebaSourceIndex(from: section.id, marker: "section"),
            isDeleted: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    var contentFingerprint: String {
        pruebaFingerprint([
            sourceId ?? "<missing>",
            String(orden),
            titulo,
            instrucciones,
            pruebaFingerprint(estimulo.map(\.contentFingerprint)),
            tipoPredominante,
            pruebaFingerprint(items.map(\.contentFingerprint)),
            isDeleted.description
        ])
    }
}

// MARK: - Entradas de items

struct PruebaItemEntryDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var sourceId: String?
    var text: String
    var imageURL: String
    var imageStoragePath: String
    var linkedId: String
    var correct: Bool
    var score: Double
    var isNew: Bool
    var originalIndex: Int?
    var isDeleted: Bool
    var baselineFingerprint: String

    static func nueva(prefix: String, order: Int) -> Self {
        let documentId = "\(prefix)_\(UUID().uuidString.lowercased())"
        var draft = Self(
            id: "ui_\(order)_\(UUID().uuidString.lowercased())",
            documentId: documentId,
            sourceId: documentId,
            text: "",
            imageURL: "",
            imageStoragePath: "",
            linkedId: "",
            correct: false,
            score: 0,
            isNew: true,
            originalIndex: nil,
            isDeleted: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    var contentFingerprint: String {
        pruebaFingerprint([
            sourceId ?? "<missing>",
            text,
            imageURL,
            imageStoragePath,
            linkedId,
            correct.description,
            pruebaDoubleFingerprint(score),
            isDeleted.description
        ])
    }
}

// MARK: - Items

struct PruebaItemDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var sourceId: String?
    var type: String
    var enunciado: String
    var linkedOA: String
    var habilidad: String
    var score: Double
    var resources: [GuiaBlockDraft]
    var entriesA: [PruebaItemEntryDraft]
    var entriesB: [PruebaItemEntryDraft]
    var respuestaCorrecta: Bool
    var pideJustificacion: Bool
    var textoConBlancos: String
    var respuestas: [String]
    var wordBank: [String]
    var respuestaEsperada: String
    var lineasRespuesta: Int
    var pautaCorreccion: String
    var isUnknown: Bool
    var isNew: Bool
    var originalIndex: Int?
    var isDeleted: Bool
    var baselineFingerprint: String

    static func nueva(type: String) -> Self {
        let itemType = PruebaEditorItemType.resolve(type) ?? .seleccionMultiple
        let documentId = "item_\(itemType.rawValue)_\(UUID().uuidString.lowercased())"
        var entriesA: [PruebaItemEntryDraft] = []
        var entriesB: [PruebaItemEntryDraft] = []

        switch itemType {
        case .seleccionMultiple:
            entriesA = (1...4).map { .nueva(prefix: "alt", order: $0) }
        case .pareados:
            entriesA = (1...2).map { .nueva(prefix: "par_a", order: $0) }
            entriesB = (1...2).map { .nueva(prefix: "par_b", order: $0) }
        case .ordenar:
            entriesA = (1...3).map { .nueva(prefix: "paso", order: $0) }
        case .desarrollo:
            break
        case .verdaderoFalso, .completar, .respuestaCorta:
            break
        }

        var draft = Self(
            id: "ui_\(UUID().uuidString.lowercased())",
            documentId: documentId,
            sourceId: documentId,
            type: itemType.rawValue,
            enunciado: "",
            linkedOA: "",
            habilidad: "",
            score: itemType == .desarrollo ? 2 : 1,
            resources: [],
            entriesA: entriesA,
            entriesB: entriesB,
            respuestaCorrecta: itemType == .verdaderoFalso,
            pideJustificacion: false,
            textoConBlancos: "",
            respuestas: [],
            wordBank: [],
            respuestaEsperada: "",
            lineasRespuesta: itemType == .desarrollo ? 5 : itemType == .respuestaCorta ? 2 : 3,
            pautaCorreccion: "",
            isUnknown: false,
            isNew: true,
            originalIndex: nil,
            isDeleted: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    static func from(_ item: PruebaItem) -> Self {
        let entries: ([PruebaItemEntryDraft], [PruebaItemEntryDraft])
        switch item.kind {
        case .seleccionMultiple:
            entries = (item.alternativas.map { entry(from: $0) }, [])
        case .pareados:
            entries = (item.columnaA.map { entry(from: $0) }, item.columnaB.map { entry(from: $0) })
        case .ordenar:
            entries = (item.pasos.map { entry(from: $0) }, [])
        case .desarrollo:
            entries = (item.criterios.map { entry(from: $0) }, [])
        case .verdaderoFalso, .completar, .respuestaCorta, .unknown:
            entries = ([], [])
        }

        var draft = Self(
            id: item.id,
            documentId: item.sourceId ?? "item_\(UUID().uuidString.lowercased())",
            sourceId: item.sourceId,
            type: item.rawType,
            enunciado: item.enunciado,
            linkedOA: item.oaVinculado ?? "",
            habilidad: item.habilidad ?? "",
            score: item.puntaje,
            resources: item.recursos.map(GuiaBlockDraft.from),
            entriesA: entries.0,
            entriesB: entries.1,
            respuestaCorrecta: item.respuestaCorrecta ?? false,
            pideJustificacion: item.pideJustificacion,
            textoConBlancos: item.textoConBlancos ?? "",
            respuestas: item.respuestasCorrectas,
            wordBank: item.bancoPalabras,
            respuestaEsperada: item.respuestaEsperada ?? "",
            lineasRespuesta: item.lineasRespuesta ?? 3,
            pautaCorreccion: item.pautaCorreccion ?? "",
            isUnknown: item.kind.isUnknown,
            isNew: false,
            originalIndex: pruebaSourceIndex(from: item.id, marker: "item"),
            isDeleted: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    var contentFingerprint: String {
        pruebaFingerprint([
            sourceId ?? "<missing>",
            type,
            enunciado,
            linkedOA,
            habilidad,
            pruebaDoubleFingerprint(score),
            pruebaFingerprint(resources.map(\.contentFingerprint)),
            pruebaFingerprint(entriesA.map(\.contentFingerprint)),
            pruebaFingerprint(entriesB.map(\.contentFingerprint)),
            respuestaCorrecta.description,
            pideJustificacion.description,
            textoConBlancos,
            pruebaFingerprint(respuestas),
            pruebaFingerprint(wordBank),
            respuestaEsperada,
            String(lineasRespuesta),
            pautaCorreccion,
            isUnknown.description,
            isDeleted.description
        ])
    }

    private static func entry(from alternative: PruebaAlternativa) -> PruebaItemEntryDraft {
        existingEntry(
            id: alternative.id,
            sourceId: alternative.sourceId,
            originalIndex: alternative.originalIndex,
            text: alternative.texto,
            imageURL: alternative.imagenUrl ?? "",
            imageStoragePath: alternative.imagenStoragePath ?? "",
            linkedId: "",
            correct: alternative.esCorrecta,
            score: 0
        )
    }

    private static func entry(from value: PruebaPareadoA) -> PruebaItemEntryDraft {
        existingEntry(
            id: value.id,
            sourceId: value.sourceId,
            originalIndex: value.originalIndex,
            text: value.texto,
            imageURL: value.imagenUrl ?? "",
            imageStoragePath: "",
            linkedId: "",
            correct: false,
            score: 0
        )
    }

    private static func entry(from value: PruebaPareadoB) -> PruebaItemEntryDraft {
        existingEntry(
            id: value.id,
            sourceId: value.sourceId,
            originalIndex: value.originalIndex,
            text: value.texto,
            imageURL: "",
            imageStoragePath: "",
            linkedId: value.correctaParaAId ?? "",
            correct: false,
            score: 0
        )
    }

    private static func entry(from step: PruebaPaso) -> PruebaItemEntryDraft {
        existingEntry(
            id: step.id,
            sourceId: step.sourceId,
            originalIndex: step.originalIndex,
            text: step.texto,
            imageURL: "",
            imageStoragePath: "",
            linkedId: "",
            correct: false,
            score: 0
        )
    }

    private static func entry(from criterion: PruebaCriterioDesarrollo) -> PruebaItemEntryDraft {
        existingEntry(
            id: criterion.id,
            sourceId: criterion.sourceId,
            originalIndex: criterion.originalIndex,
            text: criterion.texto,
            imageURL: "",
            imageStoragePath: "",
            linkedId: "",
            correct: false,
            score: criterion.puntaje
        )
    }

    private static func existingEntry(
        id: String,
        sourceId: String?,
        originalIndex: Int,
        text: String,
        imageURL: String,
        imageStoragePath: String,
        linkedId: String,
        correct: Bool,
        score: Double
    ) -> PruebaItemEntryDraft {
        var draft = PruebaItemEntryDraft(
            id: id,
            documentId: sourceId ?? "entry_\(UUID().uuidString.lowercased())",
            sourceId: sourceId,
            text: text,
            imageURL: imageURL,
            imageStoragePath: imageStoragePath,
            linkedId: linkedId,
            correct: correct,
            score: score,
            isNew: false,
            originalIndex: originalIndex,
            isDeleted: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }
}

// MARK: - Cat\u{00E1}logo de tipos

enum PruebaEditorItemType: String, CaseIterable, Identifiable {
    case seleccionMultiple = "seleccion_multiple"
    case verdaderoFalso = "verdadero_falso"
    case pareados
    case ordenar
    case completar
    case respuestaCorta = "respuesta_corta"
    case desarrollo

    var id: String { rawValue }

    static func resolve(_ value: String) -> Self? {
        switch PruebaItemKind.resolve(value) {
        case .seleccionMultiple: return .seleccionMultiple
        case .verdaderoFalso: return .verdaderoFalso
        case .pareados: return .pareados
        case .ordenar: return .ordenar
        case .completar: return .completar
        case .respuestaCorta: return .respuestaCorta
        case .desarrollo: return .desarrollo
        case .unknown: return nil
        }
    }

    var label: String {
        switch self {
        case .seleccionMultiple: return "Selecci\u{00F3}n m\u{00FA}ltiple"
        case .verdaderoFalso: return "Verdadero o falso"
        case .pareados: return "T\u{00E9}rminos pareados"
        case .ordenar: return "Ordenar secuencia"
        case .completar: return "Completar"
        case .respuestaCorta: return "Respuesta corta"
        case .desarrollo: return "Desarrollo"
        }
    }

    var icon: String {
        switch self {
        case .seleccionMultiple: return "checkmark.circle"
        case .verdaderoFalso: return "checkmark.square"
        case .pareados: return "arrow.left.arrow.right"
        case .ordenar: return "list.number"
        case .completar: return "text.insert"
        case .respuestaCorta: return "text.cursor"
        case .desarrollo: return "text.alignleft"
        }
    }

    var defaultInstructions: String {
        switch self {
        case .seleccionMultiple:
            return "Lee atentamente cada enunciado y marca con una X la alternativa correcta."
        case .verdaderoFalso:
            return "Lee atentamente cada enunciado y marca con una V cuando sea verdadero o una F cuando sea falso. Justifica las falsas."
        case .pareados:
            return "Asocia cada elemento de la columna A con su correspondiente en la columna B, escribiendo la letra en la l\u{00ED}nea."
        case .ordenar:
            return "Ordena los hechos enumer\u{00E1}ndolos del 1 al N, seg\u{00FA}n corresponda."
        case .completar:
            return "Completa los espacios en blanco con la palabra o expresi\u{00F3}n correcta."
        case .respuestaCorta:
            return "Responde brevemente cada pregunta."
        case .desarrollo:
            return "Lee cada pregunta y responde de manera completa y argumentada."
        }
    }
}

// MARK: - Fingerprints e identidad de origen

private func pruebaFingerprint(_ values: [String]) -> String {
    values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
}

private func pruebaDoubleFingerprint(_ value: Double) -> String {
    String(value.bitPattern, radix: 16)
}

private func pruebaOAsFingerprint(_ value: [OAEditado]?) -> String {
    guard let value else { return "<nil>" }
    return pruebaFingerprint(value.map { oa in
        pruebaFingerprint([
            oa.id,
            oa.numero.map { String($0) } ?? "<nil>",
            oa.tipo ?? "<nil>",
            oa.descripcion,
            oa.seleccionado.description,
            oa.esPropio.map { $0.description } ?? "<nil>",
            oa.tags.map { pruebaFingerprint($0) } ?? "<nil>",
            pruebaFingerprint(oa.indicadores.map { indicator in
                pruebaFingerprint([
                    indicator.id,
                    indicator.texto,
                    indicator.seleccionado.description,
                    indicator.esPropio.map { $0.description } ?? "<nil>"
                ])
            })
        ])
    })
}

private func pruebaSourceIndex(from path: String, marker: String) -> Int? {
    let parts = path.split(separator: "/").map(String.init)
    guard let markerIndex = parts.firstIndex(of: marker),
          parts.indices.contains(markerIndex + 1) else { return nil }
    return Int(parts[markerIndex + 1])
}

private func pruebaRoman(_ value: Int) -> String {
    guard value > 0, value < 40 else { return String(value) }
    let symbols: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
    var pending = value
    var result = ""
    for (amount, symbol) in symbols {
        while pending >= amount {
            result += symbol
            pending -= amount
        }
    }
    return result
}
