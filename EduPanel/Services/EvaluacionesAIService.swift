import Foundation

struct EvaluacionesAIService {
    func generateTest(from draft: PruebaEditorDraft, instructions: String) async throws -> [PruebaSectionDraft] {
        let response = try await client().postJSONObject("/api/generar-evaluacion", body: [
            "modo": "prueba_generar",
            "tipoDoc": "prueba",
            "contexto": context(
                subject: draft.asignatura, course: draft.curso,
                unitId: draft.unidadId, unitName: draft.unidadNombre, oas: draft.oas
            ),
            "documentoActual": compact([
                "tipoEvaluacion": draft.tipoEvaluacion,
                "asignatura": draft.asignatura,
                "curso": draft.curso,
                "unidadId": draft.unidadId,
                "unidadNombre": draft.unidadNombre
            ]),
            "instrucciones": instructions
        ])
        let payload = resultPayload(response)
        guard let sections = payload["secciones"] as? [[String: Any]], !sections.isEmpty else {
            throw EvaluacionesAIError.missingSections
        }
        let test = PruebaDocumentParser.prueba(
            id: "ai-preview", scope: .principal, isFromCache: false,
            dictionary: [
                "nombre": draft.nombre,
                "asignatura": draft.asignatura,
                "curso": draft.curso,
                "secciones": sections
            ]
        )
        return test.secciones.map(PruebaSectionDraft.from).enumerated().map { index, value in
            var copy = value
            copy.id = "ui_\(UUID().uuidString.lowercased())"
            copy.documentId = "sec_\(UUID().uuidString.lowercased())"
            copy.sourceId = copy.documentId
            copy.orden = index + 1
            copy.estimulo = value.estimulo.filter { !$0.isDeleted && !$0.isUnknown }
                .map { $0.copyForItemBankInsertion() }
            copy.items = value.items.filter { !$0.isDeleted && !$0.isUnknown }
                .map { $0.copyForItemBankInsertion() }
            copy.isNew = true
            copy.originalIndex = nil
            copy.baselineFingerprint = copy.contentFingerprint
            return copy
        }
    }

    func generateGuide(from draft: GuiaEditorDraft, instructions: String) async throws -> [GuiaSectionDraft] {
        var guideContext = context(
            subject: draft.asignatura, course: draft.curso,
            unitId: draft.unidadId, unitName: draft.unidadNombre, oas: draft.oas
        )
        guideContext["objetivoDocente"] = draft.objetivo
        let response = try await client().postJSONObject("/api/generar-evaluacion", body: [
            "modo": "guia_generar",
            "tipoDoc": "guia",
            "contexto": guideContext,
            "documentoActual": compact([
                "tipoGuia": draft.tipoGuia,
                "objetivo": draft.objetivo,
                "tiempoMinutos": draft.tiempoMinutos,
                "asignatura": draft.asignatura,
                "curso": draft.curso,
                "unidadId": draft.unidadId,
                "unidadNombre": draft.unidadNombre
            ]),
            "instrucciones": instructions
        ])
        let payload = resultPayload(response)
        let raw = (payload["seccionesGuia"] as? [[String: Any]]) ?? (payload["secciones"] as? [[String: Any]])
        guard let sections = raw, !sections.isEmpty else { throw EvaluacionesAIError.missingSections }
        let guide = GuiaDocumentParser.guia(
            id: "ai-preview",
            dictionary: [
                "nombre": draft.nombre,
                "asignatura": draft.asignatura,
                "curso": draft.curso,
                "secciones": sections
            ],
            scope: .principal,
            isFromCache: false
        )
        return guide.secciones.map(GuiaSectionDraft.from).enumerated().map { index, value in
            var copy = value
            let id = "sec_\(UUID().uuidString.lowercased())"
            copy.id = id
            copy.documentId = id
            copy.orden = index + 1
            copy.bloques = value.bloques.filter { !$0.isDeleted && !$0.isUnknown }
                .map { $0.copyForItemBankInsertion() }
            copy.actividades = value.actividades.filter { !$0.isDeleted && !$0.isUnknown }
                .enumerated().map { activityIndex, activity in
                    activity.copyForItemBankInsertion(number: activityIndex + 1)
                }
            copy.isNew = true
            copy.originalIndex = nil
            return copy
        }
    }

    private func client() throws -> APIClient {
        switch AppConfig.load() {
        case .success(let config): return APIClient(config: config)
        case .failure(let issue): throw EvaluacionesAIError.configuration(issue.message)
        }
    }

    private func context(
        subject: String, course: String, unitId: String, unitName: String, oas: [OAEditado]?
    ) -> [String: Any] {
        compact([
            "asignatura": subject,
            "curso": course,
            "unidadId": unitId,
            "unidadNombre": unitName,
            "oas": (oas ?? []).filter(\.seleccionado).map { $0.descripcion },
            "habilidades": [String](),
            "conocimientos": [String](),
            "actitudes": [String]()
        ])
    }

    private func resultPayload(_ response: [String: Any]) -> [String: Any] {
        if let value = response["resultado"] as? [String: Any] { return value }
        if let value = response["documento"] as? [String: Any] { return value }
        if let value = response["data"] as? [String: Any] { return value }
        return response
    }

    private func compact(_ dictionary: [String: Any]) -> [String: Any] {
        dictionary.filter { _, value in
            if let string = value as? String { return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }
    }
}

enum EvaluacionesAIError: LocalizedError {
    case configuration(String)
    case missingSections

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .missingSections: return "La IA no devolvió secciones utilizables. Intenta con instrucciones más específicas."
        }
    }
}
