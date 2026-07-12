import Foundation

// MARK: - Borrador lossless de aplicación

struct PruebaApplicationDraft: Equatable {
    var id: String
    var pruebaId: String
    var pruebaNombre: String
    var asignatura: String
    var curso: String
    var fechaAplicacion: String
    var resultados: [PruebaStudentResultDraft]
    var bloqueada: Bool
    var isNew: Bool
    var baselineFingerprint: String

    static func build(
        prueba: PruebaTemplate,
        application: PruebaAplicacion?,
        roster: [EstudiantePerfil]
    ) -> Self {
        let applicationId = "apl_\(prueba.id)"
        guard let application else {
            var draft = Self(
                id: applicationId,
                pruebaId: prueba.id,
                pruebaNombre: prueba.nombre,
                asignatura: prueba.asignatura,
                curso: prueba.curso,
                fechaAplicacion: "",
                resultados: roster.map(PruebaStudentResultDraft.new),
                bloqueada: false,
                isNew: true,
                baselineFingerprint: "<missing:\(applicationId)>"
            )
            draft.recalculate(with: prueba)
            return draft
        }

        var draft = Self(
            id: application.id,
            pruebaId: application.pruebaId,
            pruebaNombre: application.pruebaNombre,
            asignatura: application.asignatura,
            curso: application.curso,
            fechaAplicacion: application.fechaAplicacion ?? "",
            resultados: application.resultados.enumerated().map { index, result in
                PruebaStudentResultDraft.from(result, originalIndex: index)
            },
            bloqueada: application.bloqueada,
            isNew: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.editableFingerprint

        // La web agrega alumnos nuevos, pero conserva resultados huérfanos y sus datos históricos.
        let currentIds = Set(draft.resultados.compactMap(\.sourceId))
        draft.resultados.append(contentsOf: roster
            .filter { !currentIds.contains($0.id) }
            .map(PruebaStudentResultDraft.new))
        draft.recalculate(with: prueba)
        return draft
    }

    var editableFingerprint: String {
        pruebaApplicationFingerprint([
            pruebaId,
            pruebaNombre,
            asignatura,
            curso,
            fechaAplicacion,
            bloqueada.description,
            pruebaApplicationFingerprint(resultados.map(\.contentFingerprint))
        ])
    }

    var hasUnsavedChanges: Bool {
        isNew || editableFingerprint != baselineFingerprint
    }

    mutating func recalculate(with prueba: PruebaTemplate) {
        for index in resultados.indices {
            resultados[index].recalculate(with: prueba)
        }
    }

    mutating func markSaved() {
        for index in resultados.indices {
            resultados[index].markSaved()
        }
        isNew = false
        baselineFingerprint = editableFingerprint
    }

    var stats: PruebaApplicationStats {
        let completed = resultados.filter { $0.completado && !$0.ausente }
        let notes = completed.compactMap(\.nota)
        let average = notes.isEmpty ? 0 : notes.reduce(0, +) / Double(notes.count)
        return PruebaApplicationStats(
            promedio: pruebaApplicationRoundOneDecimal(average),
            aprobados: notes.filter { $0 >= 4 }.count,
            reprobados: notes.filter { $0 < 4 }.count,
            completados: completed.count,
            sinResolver: resultados.filter { !$0.completado && !$0.ausente }.count,
            ausentes: resultados.filter(\.ausente).count,
            mayor: notes.max() ?? 0,
            menor: notes.min() ?? 0
        )
    }
}

struct PruebaApplicationStats: Equatable {
    let promedio: Double
    let aprobados: Int
    let reprobados: Int
    let completados: Int
    let sinResolver: Int
    let ausentes: Int
    let mayor: Double
    let menor: Double
}

// MARK: - Resultado por estudiante

struct PruebaStudentResultDraft: Identifiable, Equatable {
    var id: String
    var documentId: String
    var sourceId: String?
    var originalIndex: Int?
    var nombre: String
    var hasPie: Bool
    var respuestas: [String: PruebaResponseDraft]
    var preservedResponseKeys: Set<String>
    var puntajePorItem: [String: Double]
    var puntajeTotal: Double
    var nota: Double?
    var observaciones: String
    var completado: Bool
    var ausente: Bool
    var isNew: Bool
    var baselineFingerprint: String

    static func new(_ student: EstudiantePerfil) -> Self {
        var result = Self(
            id: "ui_result_\(student.id)",
            documentId: student.id,
            sourceId: student.id,
            originalIndex: nil,
            nombre: student.nombre,
            hasPie: student.pie,
            respuestas: [:],
            preservedResponseKeys: [],
            puntajePorItem: [:],
            puntajeTotal: 0,
            nota: nil,
            observaciones: "",
            completado: false,
            ausente: false,
            isNew: true,
            baselineFingerprint: ""
        )
        result.baselineFingerprint = result.contentFingerprint
        return result
    }

    static func from(_ result: PruebaResultadoEstudiante, originalIndex: Int) -> Self {
        let responses = result.respuestas.reduce(into: [String: PruebaResponseDraft]()) { partial, entry in
            if let parsed = PruebaResponseDraft.from(itemId: entry.key, raw: entry.value) {
                partial[entry.key] = parsed
            }
        }
        let fallbackId = result.sourceId ?? "resultado_heredado_\(originalIndex)"
        var draft = Self(
            id: result.id,
            documentId: fallbackId,
            sourceId: result.sourceId,
            originalIndex: originalIndex,
            nombre: result.nombre,
            hasPie: result.hasPie,
            respuestas: responses,
            preservedResponseKeys: Set(result.respuestas.keys),
            puntajePorItem: result.puntajePorItem,
            puntajeTotal: result.puntajeTotal,
            nota: result.nota,
            observaciones: result.observaciones ?? "",
            completado: result.completado,
            ausente: result.ausente,
            isNew: false,
            baselineFingerprint: ""
        )
        draft.baselineFingerprint = draft.contentFingerprint
        return draft
    }

    var contentFingerprint: String {
        let responseFingerprint = respuestas.keys.sorted().map { key in
            pruebaApplicationFingerprint([key, respuestas[key]?.contentFingerprint ?? "<missing>"])
        }
        let scoresFingerprint = puntajePorItem.keys.sorted().map { key in
            pruebaApplicationFingerprint([key, pruebaApplicationDoubleFingerprint(puntajePorItem[key] ?? 0)])
        }
        return pruebaApplicationFingerprint([
            sourceId ?? "<missing>",
            nombre,
            hasPie.description,
            pruebaApplicationFingerprint(preservedResponseKeys.sorted()),
            pruebaApplicationFingerprint(responseFingerprint),
            pruebaApplicationFingerprint(scoresFingerprint),
            pruebaApplicationDoubleFingerprint(puntajeTotal),
            nota.map { pruebaApplicationDoubleFingerprint($0) } ?? "<nil>",
            observaciones,
            completado.description,
            ausente.description
        ])
    }

    mutating func recalculate(with prueba: PruebaTemplate) {
        var itemScores: [String: Double] = [:]
        var total = 0.0
        for section in prueba.secciones {
            for item in section.items {
                guard let itemId = item.sourceId, !itemId.isEmpty else { continue }
                let score = PruebaScoring.score(item: item, response: respuestas[itemId])
                itemScores[itemId] = score
                total += score
            }
        }
        puntajePorItem = itemScores
        puntajeTotal = pruebaApplicationRoundOneDecimal(total)
        let baseRequirement = prueba.exigencia
        let requirement = hasPie ? max(0.05, min(baseRequirement - 0.1, 0.5)) : baseRequirement
        nota = PruebaScoring.note(score: puntajeTotal, maximum: prueba.puntajeMaximo, requirement: requirement)
    }

    mutating func markSaved() {
        for key in respuestas.keys {
            respuestas[key]?.markSaved()
        }
        preservedResponseKeys.formUnion(respuestas.keys)
        isNew = false
        baselineFingerprint = contentFingerprint
    }

    var hasAnyResponse: Bool {
        !preservedResponseKeys.isEmpty || !respuestas.isEmpty
    }
}

// MARK: - Respuestas tipadas

struct PruebaResponseDraft: Identifiable, Equatable {
    let id: String
    var type: String
    var alternativaId: String
    var valor: Bool?
    var justificacion: String
    var emparejamientos: [String: String]
    var orden: [String]
    var respuestas: [String]
    var texto: String
    var puntajeManual: Double?
    var puntajePorCriterio: [String: Double]
    var isUnknown: Bool
    var isNew: Bool
    var baselineFingerprint: String

    static func from(itemId: String, raw: Any) -> Self? {
        guard let dictionary = raw as? [String: Any] else { return nil }
        let type = pruebaApplicationString(dictionary["tipo"])
        var response = Self(
            id: itemId,
            type: type,
            alternativaId: pruebaApplicationString(dictionary["alternativaId"]),
            valor: pruebaApplicationBool(dictionary["valor"]),
            justificacion: pruebaApplicationString(dictionary["justificacion"]),
            emparejamientos: pruebaApplicationStringMap(dictionary["emparejamientos"]),
            orden: pruebaApplicationStringArray(dictionary["orden"]),
            respuestas: pruebaApplicationStringArray(dictionary["respuestas"]),
            texto: pruebaApplicationString(dictionary["texto"]),
            puntajeManual: pruebaApplicationDouble(dictionary["puntajeManual"]),
            puntajePorCriterio: pruebaApplicationDoubleMap(dictionary["puntajePorCriterio"]),
            isUnknown: PruebaEditorItemType.resolve(type) == nil,
            isNew: false,
            baselineFingerprint: ""
        )
        response.baselineFingerprint = response.contentFingerprint
        return response
    }

    static func empty(for item: PruebaItem) -> Self? {
        guard let itemId = item.sourceId,
              let type = PruebaEditorItemType.resolve(item.rawType) else { return nil }
        var response = Self(
            id: itemId,
            type: type.rawValue,
            alternativaId: "",
            valor: nil,
            justificacion: "",
            emparejamientos: [:],
            orden: [],
            respuestas: type == .completar ? item.respuestasCorrectas.map { _ in "" } : [],
            texto: "",
            puntajeManual: nil,
            puntajePorCriterio: [:],
            isUnknown: false,
            isNew: true,
            baselineFingerprint: "<missing>"
        )
        if type == .ordenar {
            response.orden = []
        }
        return response
    }

    var kind: PruebaItemKind {
        PruebaItemKind.resolve(type)
    }

    var contentFingerprint: String {
        let pairings = emparejamientos.keys.sorted().map { key in
            pruebaApplicationFingerprint([key, emparejamientos[key] ?? ""])
        }
        let criteria = puntajePorCriterio.keys.sorted().map { key in
            pruebaApplicationFingerprint([key, pruebaApplicationDoubleFingerprint(puntajePorCriterio[key] ?? 0)])
        }
        return pruebaApplicationFingerprint([
            type,
            alternativaId,
            valor.map { $0.description } ?? "<nil>",
            justificacion,
            pruebaApplicationFingerprint(pairings),
            pruebaApplicationFingerprint(orden),
            pruebaApplicationFingerprint(respuestas),
            texto,
            puntajeManual.map { pruebaApplicationDoubleFingerprint($0) } ?? "<nil>",
            pruebaApplicationFingerprint(criteria),
            isUnknown.description
        ])
    }

    mutating func markSaved() {
        isNew = false
        baselineFingerprint = contentFingerprint
    }
}

// MARK: - Corrección compatible con web

enum PruebaScoring {
    static func score(item: PruebaItem, response: PruebaResponseDraft?) -> Double {
        guard let response else { return 0 }
        let maximum = normalized(item.puntaje)

        switch item.kind {
        case .seleccionMultiple:
            guard response.kind == .seleccionMultiple else { return 0 }
            return item.alternativas.first(where: { $0.sourceId == response.alternativaId })?.esCorrecta == true
                ? maximum : 0

        case .verdaderoFalso:
            guard response.kind == .verdaderoFalso,
                  let value = response.valor,
                  let expected = item.respuestaCorrecta else { return 0 }
            return value == expected ? maximum : 0

        case .pareados:
            guard response.kind == .pareados, !item.columnaA.isEmpty else { return 0 }
            let correct = item.columnaA.reduce(into: 0) { total, entryA in
                guard let aId = entryA.sourceId,
                      let expected = item.columnaB.first(where: { $0.correctaParaAId == aId })?.sourceId,
                      response.emparejamientos[aId] == expected else { return }
                total += 1
            }
            return pruebaApplicationRoundOneDecimal(Double(correct) * maximum / Double(item.columnaA.count))

        case .ordenar:
            guard response.kind == .ordenar, !item.pasos.isEmpty else { return 0 }
            let correct = item.pasos.enumerated().reduce(into: 0) { total, pair in
                guard let stepId = pair.element.sourceId,
                      response.orden.indices.contains(pair.offset),
                      response.orden[pair.offset] == stepId else { return }
                total += 1
            }
            return pruebaApplicationRoundOneDecimal(Double(correct) * maximum / Double(item.pasos.count))

        case .completar:
            guard response.kind == .completar, !item.respuestasCorrectas.isEmpty else { return 0 }
            let correct = item.respuestasCorrectas.enumerated().reduce(into: 0) { total, pair in
                let given = response.respuestas.indices.contains(pair.offset)
                    ? normalizedText(response.respuestas[pair.offset]) : ""
                let expected = normalizedText(pair.element)
                if !given.isEmpty, !expected.isEmpty, given == expected { total += 1 }
            }
            return pruebaApplicationRoundOneDecimal(
                Double(correct) * maximum / Double(item.respuestasCorrectas.count)
            )

        case .respuestaCorta:
            guard response.kind == .respuestaCorta else { return 0 }
            return manualScore(response.puntajeManual, maximum: maximum)

        case .desarrollo:
            guard response.kind == .desarrollo else { return 0 }
            if response.puntajeManual != nil {
                return manualScore(response.puntajeManual, maximum: maximum)
            }
            let criteriaTotal = item.criterios.reduce(0.0) { total, criterion in
                guard let criterionId = criterion.sourceId else { return total }
                let value = normalized(response.puntajePorCriterio[criterionId] ?? 0)
                return total + min(normalized(criterion.puntaje), value)
            }
            return max(0, min(maximum, pruebaApplicationRoundOneDecimal(criteriaTotal)))

        case .unknown:
            return 0
        }
    }

    static func note(score: Double, maximum: Double, requirement: Double = 0.6) -> Double {
        guard maximum.isFinite, maximum > 0 else { return 1 }
        let points = score.isFinite ? score : 0
        let percentage = min(1, max(0, points / maximum))
        let base = requirement.isFinite ? requirement : 0.6
        let exigency = min(0.95, max(0.05, base))
        let note: Double
        if percentage < exigency {
            note = 1 + (3 * percentage) / exigency
        } else {
            note = 4 + (3 * (percentage - exigency)) / (1 - exigency)
        }
        return pruebaApplicationRoundOneDecimal(min(7, max(1, note)))
    }

    private static func manualScore(_ value: Double?, maximum: Double) -> Double {
        guard let value else { return 0 }
        return max(0, min(maximum, normalized(value)))
    }

    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Helpers privados

private func pruebaApplicationFingerprint(_ values: [String]) -> String {
    values.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
}

private func pruebaApplicationDoubleFingerprint(_ value: Double) -> String {
    String(value.bitPattern, radix: 16)
}

private func pruebaApplicationRoundOneDecimal(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

private func pruebaApplicationString(_ value: Any?) -> String {
    switch value {
    case let string as String: return string
    case let number as NSNumber: return number.stringValue
    default: return ""
    }
}

private func pruebaApplicationDouble(_ value: Any?) -> Double? {
    switch value {
    case is Bool: return nil
    case let number as NSNumber: return number.doubleValue
    case let value as Double: return value
    case let value as Int: return Double(value)
    default: return nil
    }
}

private func pruebaApplicationBool(_ value: Any?) -> Bool? {
    switch value {
    case let value as Bool: return value
    default: return nil
    }
}

private func pruebaApplicationStringArray(_ value: Any?) -> [String] {
    guard let values = value as? [Any] else { return [] }
    return values.map(pruebaApplicationString)
}

private func pruebaApplicationStringMap(_ value: Any?) -> [String: String] {
    guard let dictionary = value as? [String: Any] else { return [:] }
    return dictionary.reduce(into: [:]) { result, entry in
        result[entry.key] = pruebaApplicationString(entry.value)
    }
}

private func pruebaApplicationDoubleMap(_ value: Any?) -> [String: Double] {
    guard let dictionary = value as? [String: Any] else { return [:] }
    return dictionary.reduce(into: [:]) { result, entry in
        if let number = pruebaApplicationDouble(entry.value) { result[entry.key] = number }
    }
}
