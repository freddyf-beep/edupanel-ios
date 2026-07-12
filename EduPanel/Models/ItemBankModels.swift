import Foundation

enum ItemBankOrigin: String, CaseIterable, Identifiable {
    case prueba
    case guia

    var id: String { rawValue }
    var label: String { self == .prueba ? "Prueba" : "Guía" }
}

struct ItemBankMetadata {
    let asignatura: String
    let curso: String
    let oas: [String]
    let origen: ItemBankOrigin
    let autor: String
    let timestamp: Date?
}

struct ItemBankEntry: Identifiable {
    let id: String
    let payload: [String: Any]
    let metadata: ItemBankMetadata
    let createdAt: Date?

    var type: String {
        (payload["tipo"] as? String) ?? ""
    }

    var prompt: String {
        (payload["enunciado"] as? String) ?? ""
    }

    func pruebaDraft() -> PruebaItemDraft? {
        if metadata.origen == .prueba {
            let test = PruebaDocumentParser.prueba(
                id: "bank_\(id)",
                scope: .principal,
                isFromCache: false,
                dictionary: [
                    "nombre": "Banco",
                    "asignatura": metadata.asignatura,
                    "curso": metadata.curso,
                    "secciones": [["id": "sec_bank", "orden": 1, "items": [payload]]]
                ]
            )
            guard let item = test.secciones.first?.items.first else { return nil }
            return PruebaItemDraft.from(item).copyForItemBankInsertion()
        }

        guard let activity = guiaActivityDraft() else { return nil }
        return activity.convertedToPruebaDraft()
    }

    func guiaActivityDraft(number: Int = 1) -> GuiaActivityDraft? {
        if metadata.origen == .guia {
            let guide = GuiaDocumentParser.guia(
                id: "bank_\(id)",
                dictionary: [
                    "nombre": "Banco",
                    "asignatura": metadata.asignatura,
                    "curso": metadata.curso,
                    "secciones": [[
                        "id": "sec_bank",
                        "orden": 1,
                        "actividades": [payload]
                    ]]
                ],
                scope: .principal,
                isFromCache: false
            )
            guard let activity = guide.secciones.first?.actividades.first else { return nil }
            var draft = GuiaActivityDraft.from(activity).copyForItemBankInsertion(number: number)
            draft.number = number
            return draft
        }

        guard let item = pruebaDraft() else { return nil }
        return item.convertedToGuiaActivityDraft(number: number)
    }
}

extension PruebaItemDraft {
    func copyForItemBankInsertion() -> Self {
        var copy = Self.nueva(type: type)
        copy.enunciado = enunciado
        copy.linkedOA = linkedOA
        copy.habilidad = habilidad
        copy.score = score
        copy.resources = resources.filter { !$0.isDeleted && !$0.isUnknown }.map { $0.copyForItemBankInsertion() }
        copy.entriesA = entriesA.filter { !$0.isDeleted }.map { $0.copyForItemBankInsertion(prefix: "entry") }
        copy.entriesB = entriesB.filter { !$0.isDeleted }.map { $0.copyForItemBankInsertion(prefix: "entry") }
        copy.respuestaCorrecta = respuestaCorrecta
        copy.pideJustificacion = pideJustificacion
        copy.textoConBlancos = textoConBlancos
        copy.respuestas = respuestas
        copy.wordBank = wordBank
        copy.respuestaEsperada = respuestaEsperada
        copy.lineasRespuesta = lineasRespuesta
        copy.pautaCorreccion = pautaCorreccion
        copy.isUnknown = false
        copy.isNew = true
        copy.originalIndex = nil
        copy.isDeleted = false
        copy.baselineFingerprint = copy.contentFingerprint
        return copy
    }

    func convertedToGuiaActivityDraft(number: Int) -> GuiaActivityDraft? {
        guard let type = PruebaEditorItemType.resolve(type) else { return nil }
        let guideType: String
        switch type {
        case .seleccionMultiple: guideType = "seleccion_multiple"
        case .verdaderoFalso: guideType = "verdadero_falso"
        case .pareados: guideType = "pareados"
        case .ordenar: guideType = "ordenar"
        case .completar: guideType = "completar"
        case .respuestaCorta: guideType = "respuesta_corta"
        case .desarrollo: guideType = "abierta"
        }

        var activity = GuiaActivityDraft.nueva(type: guideType, number: number)
        activity.prompt = enunciado
        activity.score = score
        activity.resources = resources.filter { !$0.isDeleted && !$0.isUnknown }.map { $0.copyForItemBankInsertion() }
        activity.linkedOA = linkedOA

        switch type {
        case .seleccionMultiple:
            activity.entriesA = entriesA.filter { !$0.isDeleted }.map { entry in
                var target = GuiaActivityEntryDraft.nueva(prefix: "op", order: 1)
                target.text = entry.text
                target.correct = entry.correct
                target.imageUrl = entry.imageURL
                target.baselineFingerprint = target.contentFingerprint
                return target
            }
        case .verdaderoFalso:
            var affirmation = GuiaActivityEntryDraft.nueva(prefix: "af", order: 1)
            affirmation.text = enunciado
            affirmation.correct = respuestaCorrecta
            affirmation.baselineFingerprint = affirmation.contentFingerprint
            activity.entriesA = [affirmation]
        case .pareados:
            let sourceA = entriesA.filter { !$0.isDeleted }
            var idMap: [String: String] = [:]
            activity.entriesA = sourceA.enumerated().map { index, entry in
                var target = GuiaActivityEntryDraft.nueva(prefix: "a", order: index + 1)
                target.text = entry.text
                target.imageUrl = entry.imageURL
                idMap[entry.documentId] = target.documentId
                target.baselineFingerprint = target.contentFingerprint
                return target
            }
            activity.entriesB = entriesB.filter { !$0.isDeleted }.enumerated().map { index, entry in
                var target = GuiaActivityEntryDraft.nueva(prefix: "b", order: index + 1)
                target.text = entry.text
                target.linkedId = idMap[entry.linkedId] ?? ""
                target.baselineFingerprint = target.contentFingerprint
                return target
            }
        case .ordenar:
            activity.entriesA = entriesA.filter { !$0.isDeleted }.enumerated().map { index, entry in
                var target = GuiaActivityEntryDraft.nueva(prefix: "paso", order: index + 1)
                target.text = entry.text
                target.correctOrder = index + 1
                target.baselineFingerprint = target.contentFingerprint
                return target
            }
        case .completar:
            activity.text = textoConBlancos
            activity.answers = respuestas
            activity.wordBank = wordBank
        case .respuestaCorta:
            activity.lines = lineasRespuesta
            activity.suggestedAnswer = respuestaEsperada
        case .desarrollo:
            activity.lines = lineasRespuesta
        }
        activity.baselineFingerprint = activity.contentFingerprint
        return activity
    }
}

extension GuiaActivityDraft {
    func copyForItemBankInsertion(number: Int) -> Self {
        var copy = Self.nueva(type: type, number: number)
        copy.prompt = prompt
        copy.score = score
        copy.resources = resources.filter { !$0.isDeleted && !$0.isUnknown }.map { $0.copyForItemBankInsertion() }
        copy.linkedOA = linkedOA
        copy.entriesA = entriesA.filter { !$0.isDeleted }.enumerated().map {
            $0.element.copyForItemBankInsertion(prefix: "a", order: $0.offset + 1)
        }
        copy.entriesB = entriesB.filter { !$0.isDeleted }.enumerated().map {
            $0.element.copyForItemBankInsertion(prefix: "b", order: $0.offset + 1)
        }
        if type == "pareados" {
            let oldA = entriesA.filter { !$0.isDeleted }
            let newA = copy.entriesA
            let map = Dictionary(uniqueKeysWithValues: zip(oldA, newA).map { ($0.documentId, $1.documentId) })
            for index in copy.entriesB.indices {
                let source = entriesB.filter { !$0.isDeleted }[index]
                copy.entriesB[index].linkedId = map[source.linkedId] ?? ""
            }
        }
        copy.text = text
        copy.answers = answers
        copy.wordBank = wordBank
        copy.lines = lines
        copy.suggestedAnswer = suggestedAnswer
        copy.instruction = instruction
        copy.imageUrl = imageUrl
        copy.heightCm = heightCm
        copy.words = words
        copy.gridSize = gridSize
        copy.isUnknown = false
        copy.isNew = true
        copy.originalIndex = nil
        copy.isDeleted = false
        copy.baselineFingerprint = copy.contentFingerprint
        return copy
    }

    func convertedToPruebaDraft() -> PruebaItemDraft? {
        let kind = GuiaActividadKind.resolve(type)
        let testType: String
        switch kind {
        case .seleccionMultiple: testType = "seleccion_multiple"
        case .verdaderoFalso: testType = "verdadero_falso"
        case .completar: testType = "completar"
        case .respuestaCorta: testType = "respuesta_corta"
        case .ordenar: testType = "ordenar"
        case .pareados: testType = "pareados"
        case .abierta: testType = "desarrollo"
        case .encerrar, .marcar, .colorear, .dibujar, .investigar, .sopaLetras, .desconocida:
            return nil
        }

        var item = PruebaItemDraft.nueva(type: testType)
        item.enunciado = prompt
        item.score = score ?? 1
        item.resources = resources.filter { !$0.isDeleted && !$0.isUnknown }.map { $0.copyForItemBankInsertion() }
        item.linkedOA = linkedOA

        switch kind {
        case .seleccionMultiple:
            item.entriesA = entriesA.filter { !$0.isDeleted }.map { entry in
                var target = PruebaItemEntryDraft.nueva(prefix: "alt", order: 1)
                target.text = entry.text
                target.correct = entry.correct
                target.imageURL = entry.imageUrl
                target.baselineFingerprint = target.contentFingerprint
                return target
            }
        case .verdaderoFalso:
            if let first = entriesA.first(where: { !$0.isDeleted }) {
                item.enunciado = first.text.isEmpty ? prompt : first.text
                item.respuestaCorrecta = first.correct
            }
        case .completar:
            item.textoConBlancos = text
            item.respuestas = answers
            item.wordBank = wordBank
        case .respuestaCorta:
            item.lineasRespuesta = lines
            item.respuestaEsperada = suggestedAnswer
        case .ordenar:
            item.entriesA = entriesA.filter { !$0.isDeleted }
                .sorted { $0.correctOrder < $1.correctOrder }
                .enumerated().map { index, entry in
                    var target = PruebaItemEntryDraft.nueva(prefix: "paso", order: index + 1)
                    target.text = entry.text
                    target.baselineFingerprint = target.contentFingerprint
                    return target
                }
        case .pareados:
            let sourceA = entriesA.filter { !$0.isDeleted }
            var idMap: [String: String] = [:]
            item.entriesA = sourceA.enumerated().map { index, entry in
                var target = PruebaItemEntryDraft.nueva(prefix: "a", order: index + 1)
                target.text = entry.text
                idMap[entry.documentId] = target.documentId
                target.baselineFingerprint = target.contentFingerprint
                return target
            }
            item.entriesB = entriesB.filter { !$0.isDeleted }.enumerated().map { index, entry in
                var target = PruebaItemEntryDraft.nueva(prefix: "b", order: index + 1)
                target.text = entry.text
                target.linkedId = idMap[entry.linkedId] ?? ""
                target.baselineFingerprint = target.contentFingerprint
                return target
            }
        case .abierta:
            item.lineasRespuesta = lines
        case .encerrar, .marcar, .colorear, .dibujar, .investigar, .sopaLetras, .desconocida:
            return nil
        }
        item.baselineFingerprint = item.contentFingerprint
        return item
    }
}

private extension PruebaItemEntryDraft {
    func copyForItemBankInsertion(prefix: String, order: Int = 1) -> Self {
        var copy = Self.nueva(prefix: prefix, order: order)
        copy.text = text
        copy.imageURL = imageURL
        copy.imageStoragePath = imageStoragePath
        copy.linkedId = linkedId
        copy.correct = correct
        copy.score = score
        copy.baselineFingerprint = copy.contentFingerprint
        return copy
    }
}

private extension GuiaActivityEntryDraft {
    func copyForItemBankInsertion(prefix: String, order: Int) -> Self {
        var copy = Self.nueva(prefix: prefix, order: order)
        copy.text = text
        copy.correct = correct
        copy.imageUrl = imageUrl
        copy.linkedId = linkedId
        copy.correctOrder = correctOrder
        copy.baselineFingerprint = copy.contentFingerprint
        return copy
    }
}

extension GuiaBlockDraft {
    func copyForItemBankInsertion() -> Self {
        var copy = Self.nueva(type: type)
        copy.html = html
        copy.style = style
        copy.url = url
        copy.storagePath = storagePath
        copy.alt = alt
        copy.caption = caption
        copy.width = width
        copy.alignment = alignment
        copy.headers = headers
        copy.rows = rows
        copy.firstColumnHeader = firstColumnHeader
        copy.separatorStyle = separatorStyle
        copy.baselineFingerprint = copy.contentFingerprint
        return copy
    }
}
