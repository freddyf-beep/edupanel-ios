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

// MARK: - Generación de clases

struct ClassAIGeneratedContent: Decodable {
    let objetivo: String?
    let inicio: String?
    let desarrollo: String?
    let cierre: String?
    let materiales: [String]?
    let tics: [String]?
    let adecuacion: String?
    let analisisBloom: [AnalisisBloom]?
    let objetivoMultinivel: ObjetivoMultinivel?
    let indicadoresEvaluacion: [IndicadorEvaluacion]?
    let actividadEvaluacion: ActividadEvaluacion?
}

enum ClassAIError: LocalizedError {
    case configuration(String)
    case invalidResponse
    case malformedGeneration(String?)
    case unusableResponse
    case timeout
    case offline

    var errorDescription: String? {
        switch self {
        case .configuration(let message):
            return message
        case .invalidResponse:
            return "La IA respondió con un formato que no pudimos leer. Inténtalo nuevamente."
        case .malformedGeneration(let message):
            let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return detail.isEmpty
                ? "La IA no pudo ordenar la propuesta. Inténtalo nuevamente o agrega una indicación más concreta."
                : "La IA no pudo ordenar la propuesta: \(detail)"
        case .unusableResponse:
            return "La IA no devolvió una planificación utilizable. Agrega una indicación más concreta y reintenta."
        case .timeout:
            return "La propuesta tardó demasiado. Revisa tu conexión e inténtalo nuevamente."
        case .offline:
            return "Necesitas conexión a internet para crear una propuesta con IA."
        }
    }
}

struct ClassAIService {
    func generateDraft(
        from activity: ActividadClase,
        unit: VerUnidadGuardada?,
        previousActivity: ActividadClase?,
        totalClasses: Int,
        instructions: String
    ) async throws -> ActividadClase {
        let response: [String: Any]
        do {
            response = try await client().postJSONObject(
                "/api/generar-clase",
                body: Self.requestBody(
                    activity: activity,
                    unit: unit,
                    previousActivity: previousActivity,
                    totalClasses: totalClasses,
                    instructions: instructions
                )
            )
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw ClassAIError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                throw ClassAIError.offline
            default:
                throw error
            }
        }

        let generated = try Self.decode(response)
        return try Self.applying(generated, to: activity)
    }

    static func requestBody(
        activity: ActividadClase,
        unit: VerUnidadGuardada?,
        previousActivity: ActividadClase?,
        totalClasses: Int,
        instructions: String
    ) -> [String: Any] {
        let selectedObjectives = (unit?.oas ?? []).filter { objective in
            activity.oaIds.contains { pedagogicalID($0) == pedagogicalID(objective.id) }
                || objective.numero.map { number in
                    activity.oaIds.contains { pedagogicalID($0) == pedagogicalID("OA\(number)") }
                } == true
        }
        let objectivePayload: [[String: Any]] = selectedObjectives.map { objective in
            var value: [String: Any] = [
                "descripcion": objective.descripcion,
                "indicadores": selectedIndicators(for: objective, activity: activity).map { ["texto": $0.texto] }
            ]
            if let number = objective.numero { value["numero"] = number }
            return value
        }

        let unitSkills = (unit?.habilidades ?? []).filter(\.seleccionado).map(\.texto)
        let unitAttitudes = (unit?.actitudes ?? []).filter(\.seleccionado).map(\.texto)
        let skills = activity.habilidades.isEmpty ? unitSkills : activity.habilidades
        let attitudes = activity.actitudes.isEmpty ? unitAttitudes : activity.actitudes
        let cleanInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacherContext = RichTextHTML.plainText(from: activity.contextoProfesor ?? "")

        var body: [String: Any] = [
            "modo": "crear_inicial",
            "curso": activity.curso,
            "asignatura": activity.asignatura,
            "numeroClase": activity.numeroClase,
            "totalClasesUnidad": max(totalClasses, 1),
            "nivelCurricular": activity.curso,
            "duracionMinutos": 90,
            "contextoProfesor": teacherContext.isEmpty ? cleanInstructions : teacherContext,
            "instruccionesAdicionales": cleanInstructions,
            "oas": objectivePayload,
            "habilidades": skills,
            "actitudes": attitudes,
            "objetivoClase": RichTextHTML.plainText(from: activity.objetivo),
            "claseActual": [
                "objetivo": activity.objetivo,
                "inicio": activity.inicio,
                "desarrollo": activity.desarrollo,
                "cierre": activity.cierre,
                "adecuacion": activity.adecuacion,
                "materiales": activity.materiales,
                "tics": activity.tics
            ],
            "aiModelTier": "luna",
            "aiExperience": "standard",
            "allowExternalSearch": false
        ]

        if let previousActivity {
            let continuity = [
                RichTextHTML.plainText(from: previousActivity.objetivo),
                RichTextHTML.plainText(from: previousActivity.desarrollo)
            ].filter { !$0.isEmpty }.joined(separator: " · ")
            if !continuity.isEmpty { body["contextoAnterior"] = continuity }
        }

        if let unit {
            var unitPayload: [String: Any] = [
                "proposito": unit.descripcion,
                "conocimientos": unit.conocimientos.filter(\.seleccionado).map(\.texto),
                "habilidades": unitSkills,
                "actitudes": unitAttitudes,
                "contexto_docente": unit.contextoDocente,
                "objetivo_docente": unit.objetivoDocente
            ]
            let previousKnowledge = unit.conocimientosPrevios?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !previousKnowledge.isEmpty {
                unitPayload["conocimientos_previos"] = [previousKnowledge]
            }
            body["unidad"] = unitPayload
        }

        return body
    }

    static func decode(_ response: [String: Any]) throws -> ClassAIGeneratedContent {
        if response["error"] as? String == "json_parse_failed" {
            throw ClassAIError.malformedGeneration(response["message"] as? String)
        }
        if response["error"] != nil { throw ClassAIError.invalidResponse }
        guard JSONSerialization.isValidJSONObject(response),
              let data = try? JSONSerialization.data(withJSONObject: response),
              let value = try? JSONDecoder().decode(ClassAIGeneratedContent.self, from: data) else {
            throw ClassAIError.invalidResponse
        }
        return value
    }

    static func applying(_ generated: ClassAIGeneratedContent, to activity: ActividadClase) throws -> ActividadClase {
        let objective = clean(generated.objetivo)
        let start = clean(generated.inicio)
        let development = clean(generated.desarrollo)
        let close = clean(generated.cierre)
        guard !objective.isEmpty, ![start, development, close].allSatisfy(\.isEmpty) else {
            throw ClassAIError.unusableResponse
        }

        var result = activity
        result.objetivo = objective
        if !start.isEmpty { result.inicio = start }
        if !development.isEmpty { result.desarrollo = development }
        if !close.isEmpty { result.cierre = close }
        if let materials = generated.materiales, !materials.isEmpty { result.materiales = materials }
        if let technologies = generated.tics, !technologies.isEmpty { result.tics = technologies }
        let adaptation = clean(generated.adecuacion)
        if !adaptation.isEmpty { result.adecuacion = adaptation }
        result.analisisBloom = generated.analisisBloom ?? result.analisisBloom
        result.objetivoMultinivel = generated.objetivoMultinivel ?? result.objetivoMultinivel
        result.indicadoresEvaluacion = generated.indicadoresEvaluacion ?? result.indicadoresEvaluacion
        result.actividadEvaluacion = generated.actividadEvaluacion ?? result.actividadEvaluacion
        result.desarrolloFormal = DesarrolloFormal(
            inicio: result.inicio,
            desarrollo: result.desarrollo,
            cierre: result.cierre
        )
        result.estado = "planificada"
        result.sincronizada = false
        return result
    }

    private func client() throws -> APIClient {
        let config: AppConfig
        switch AppConfig.load() {
        case .success(let value): config = value
        case .failure(let issue): throw ClassAIError.configuration(issue.message)
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 75
        sessionConfiguration.timeoutIntervalForResource = 120
        sessionConfiguration.waitsForConnectivity = false
        return APIClient(config: config, session: URLSession(configuration: sessionConfiguration))
    }

    private static func selectedIndicators(
        for objective: OAEditado,
        activity: ActividadClase
    ) -> [IndicadorEditado] {
        guard let selected = activity.indicadoresPorOa?[objective.id] else {
            return objective.indicadores.filter(\.seleccionado)
        }
        let normalized = Set(selected.map(pedagogicalID))
        return objective.indicadores.filter(\.seleccionado).filter {
            normalized.contains(pedagogicalID($0.id)) || normalized.contains(pedagogicalID($0.texto))
        }
    }

    private static func pedagogicalID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func clean(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
