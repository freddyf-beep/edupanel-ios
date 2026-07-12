import Foundation
import FirebaseAuth
import FirebaseFirestore

struct ItemBankRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func load(
        asignatura: String? = nil,
        curso: String? = nil,
        type: String? = nil,
        oa: String? = nil,
        search: String = ""
    ) async throws -> [ItemBankEntry] {
        let uid = try userId()
        let snapshot = try await getDocuments(
            db.collection("users").document(uid).collection("itemBank")
                .order(by: "createdAt", descending: true)
                .limit(to: 200)
        )
        let subjectKey = normalized(asignatura ?? "")
        let courseKey = normalized(curso ?? "")
        let typeKey = type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let oaKey = oa?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let searchKey = normalized(search)

        return snapshot.documents.compactMap(parse).filter { entry in
            if !subjectKey.isEmpty, normalized(entry.metadata.asignatura) != subjectKey { return false }
            if !courseKey.isEmpty, normalized(entry.metadata.curso) != courseKey { return false }
            if !typeKey.isEmpty, entry.type != typeKey { return false }
            if !oaKey.isEmpty {
                let linked = (entry.payload["oaVinculado"] as? String) ?? ""
                if !entry.metadata.oas.contains(oaKey), linked != oaKey { return false }
            }
            return searchKey.isEmpty || normalized(entry.prompt).contains(searchKey)
        }
    }

    @discardableResult
    func save(
        item: PruebaItemDraft,
        asignatura: String,
        curso: String,
        author: String? = nil
    ) async throws -> String {
        guard !item.isUnknown else { throw ItemBankError.unsupportedContent }
        return try await add(
            payload: encode(item: item),
            metadata: metadata(
                asignatura: asignatura,
                curso: curso,
                oa: item.linkedOA,
                origin: .prueba,
                author: author
            )
        )
    }

    @discardableResult
    func save(
        activity: GuiaActivityDraft,
        asignatura: String,
        curso: String,
        author: String? = nil
    ) async throws -> String {
        guard !activity.isUnknown else { throw ItemBankError.unsupportedContent }
        return try await add(
            payload: encode(activity: activity),
            metadata: metadata(
                asignatura: asignatura,
                curso: curso,
                oa: activity.linkedOA,
                origin: .guia,
                author: author
            )
        )
    }

    func delete(id: String) async throws {
        let uid = try userId()
        try await deleteDocument(
            db.collection("users").document(uid).collection("itemBank").document(id)
        )
    }

    private func metadata(
        asignatura: String,
        curso: String,
        oa: String,
        origin: ItemBankOrigin,
        author: String?
    ) -> [String: Any] {
        let cleanOA = oa.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = author ?? Auth.auth().currentUser?.displayName ?? ""
        return [
            "asignatura": asignatura,
            "curso": curso,
            "oas": cleanOA.isEmpty ? [String]() : [cleanOA],
            "origen": origin.rawValue,
            "autor": displayName,
            "timestamp": FieldValue.serverTimestamp()
        ]
    }

    private func add(payload: [String: Any], metadata: [String: Any]) async throws -> String {
        let uid = try userId()
        let reference = db.collection("users").document(uid).collection("itemBank").document()
        try await setData([
            "payload": payload,
            "metadata": metadata,
            "createdAt": FieldValue.serverTimestamp()
        ], at: reference)
        return reference.documentID
    }

    private func parse(_ document: QueryDocumentSnapshot) -> ItemBankEntry? {
        let data = document.data()
        guard let payload = data["payload"] as? [String: Any] else { return nil }
        let metadata = (data["metadata"] as? [String: Any]) ?? [:]
        let origin = ItemBankOrigin(rawValue: (metadata["origen"] as? String) ?? "") ?? .prueba
        return ItemBankEntry(
            id: document.documentID,
            payload: payload,
            metadata: ItemBankMetadata(
                asignatura: (metadata["asignatura"] as? String) ?? "",
                curso: (metadata["curso"] as? String) ?? "",
                oas: stringArray(metadata["oas"]),
                origen: origin,
                autor: (metadata["autor"] as? String) ?? "",
                timestamp: date(metadata["timestamp"])
            ),
            createdAt: date(data["createdAt"])
        )
    }

    private func encode(item: PruebaItemDraft) -> [String: Any] {
        var payload: [String: Any] = [
            "id": item.documentId,
            "tipo": item.type,
            "enunciado": item.enunciado,
            "puntaje": max(0, item.score)
        ]
        set(item.linkedOA, key: "oaVinculado", in: &payload)
        set(item.habilidad, key: "habilidad", in: &payload)
        let resources = item.resources.filter { !$0.isDeleted && !$0.isUnknown }.map { encode(block: $0) }
        if !resources.isEmpty { payload["recursos"] = resources }

        switch PruebaEditorItemType.resolve(item.type) {
        case .seleccionMultiple:
            payload["alternativas"] = item.entriesA.filter { !$0.isDeleted }.map { entry in
                var value: [String: Any] = [
                    "id": entry.documentId,
                    "texto": entry.text,
                    "esCorrecta": entry.correct
                ]
                set(entry.imageURL, key: "imagenUrl", in: &value)
                set(entry.imageStoragePath, key: "imagenStoragePath", in: &value)
                return value
            }
        case .verdaderoFalso:
            payload["respuestaCorrecta"] = item.respuestaCorrecta
            payload["pideJustificacion"] = item.pideJustificacion
        case .pareados:
            payload["columnaA"] = item.entriesA.filter { !$0.isDeleted }.map { entry in
                var value: [String: Any] = ["id": entry.documentId, "texto": entry.text]
                set(entry.imageURL, key: "imagenUrl", in: &value)
                return value
            }
            payload["columnaB"] = item.entriesB.filter { !$0.isDeleted }.map {
                ["id": $0.documentId, "texto": $0.text, "correctaParaAId": $0.linkedId]
            }
        case .ordenar:
            payload["pasos"] = item.entriesA.filter { !$0.isDeleted }.map {
                ["id": $0.documentId, "texto": $0.text]
            }
        case .completar:
            payload["textoConBlancos"] = item.textoConBlancos
            payload["respuestas"] = item.respuestas
            if !item.wordBank.isEmpty { payload["bancoPalabras"] = item.wordBank }
        case .respuestaCorta:
            payload["lineasRespuesta"] = max(1, item.lineasRespuesta)
            set(item.respuestaEsperada, key: "respuestaEsperada", in: &payload)
        case .desarrollo:
            payload["lineasRespuesta"] = max(1, item.lineasRespuesta)
            set(item.pautaCorreccion, key: "pautaCorreccion", in: &payload)
            let criteria = item.entriesA.filter { !$0.isDeleted }.map {
                ["id": $0.documentId, "texto": $0.text, "puntaje": max(0, $0.score)] as [String: Any]
            }
            if !criteria.isEmpty { payload["criterios"] = criteria }
        case nil:
            break
        }
        return payload
    }

    private func encode(activity: GuiaActivityDraft) -> [String: Any] {
        var payload: [String: Any] = [
            "id": activity.documentId,
            "tipo": activity.type,
            "numero": max(1, activity.number),
            "enunciado": activity.prompt
        ]
        if let score = activity.score { payload["puntaje"] = max(0, score) }
        set(activity.linkedOA, key: "oaVinculado", in: &payload)
        let resources = activity.resources.filter { !$0.isDeleted && !$0.isUnknown }.map { encode(block: $0) }
        if !resources.isEmpty { payload["recursos"] = resources }
        var data: [String: Any] = ["tipo": activity.type]

        switch GuiaActividadKind.resolve(activity.type) {
        case .seleccionMultiple:
            data["alternativas"] = activityEntries(activity.entriesA, style: .option)
        case .encerrar, .marcar:
            data["opciones"] = activityEntries(activity.entriesA, style: .option)
        case .verdaderoFalso:
            data["afirmaciones"] = activityEntries(activity.entriesA, style: .affirmation)
        case .completar:
            data["texto"] = activity.text
            data["respuestas"] = activity.answers
            data["banco"] = activity.wordBank
        case .respuestaCorta:
            data["lineas"] = max(1, activity.lines)
            set(activity.suggestedAnswer, key: "respuestaSugerida", in: &data)
        case .ordenar:
            data["pasos"] = activityEntries(activity.entriesA, style: .step)
        case .pareados:
            data["columnaA"] = activityEntries(activity.entriesA, style: .pairA)
            data["columnaB"] = activityEntries(activity.entriesB, style: .pairB)
        case .colorear:
            data["instruccion"] = activity.instruction
            set(activity.imageUrl, key: "imagenUrl", in: &data)
        case .dibujar:
            data["instruccion"] = activity.instruction
            data["alturaCm"] = max(1, activity.heightCm)
        case .investigar:
            data["instruccion"] = activity.instruction
            data["lineasRespuesta"] = max(1, activity.lines)
        case .sopaLetras:
            data["palabras"] = activity.words
            data["tamañoCuadro"] = min(20, max(4, activity.gridSize))
        case .abierta:
            data["lineasRespuesta"] = max(1, activity.lines)
        case .desconocida:
            break
        }
        payload["datos"] = data
        return payload
    }

    private enum ActivityEntryStyle { case option, affirmation, step, pairA, pairB }

    private func activityEntries(
        _ values: [GuiaActivityEntryDraft],
        style: ActivityEntryStyle
    ) -> [[String: Any]] {
        values.filter { !$0.isDeleted }.enumerated().map { index, entry in
            var value: [String: Any] = ["id": entry.documentId, "texto": entry.text]
            switch style {
            case .option:
                value["correcta"] = entry.correct
                set(entry.imageUrl, key: "imagenUrl", in: &value)
            case .affirmation:
                value["correcta"] = entry.correct
            case .step:
                value["numeroCorrecto"] = max(1, entry.correctOrder == 0 ? index + 1 : entry.correctOrder)
            case .pairB:
                set(entry.linkedId, key: "pareCon", in: &value)
            case .pairA:
                break
            }
            return value
        }
    }

    private func encode(block: GuiaBlockDraft) -> [String: Any] {
        var data: [String: Any] = [:]
        switch block.type {
        case "texto":
            data["html"] = block.html
            data["estilo"] = block.style
        case "imagen":
            data["url"] = block.url
            set(block.storagePath, key: "storagePath", in: &data)
            set(block.alt, key: "alt", in: &data)
            set(block.caption, key: "caption", in: &data)
            data["ancho"] = block.width
            data["alineacion"] = block.alignment
        case "tabla":
            data["cabeceras"] = block.headers
            data["filas"] = block.rows
            data["primeraColumnaCabecera"] = block.firstColumnHeader
        case "separador":
            data["estilo"] = block.separatorStyle
        default:
            break
        }
        return ["id": block.documentId, "tipo": block.type, "data": data]
    }

    private func set(_ value: String, key: String, in dictionary: inout [String: Any]) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { dictionary[key] = clean }
    }

    private func userId() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw DashboardRepositoryError.missingUser }
        return uid
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringArray(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }

    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error { continuation.resume(throwing: error) }
                else if let snapshot { continuation.resume(returning: snapshot) }
                else { continuation.resume(throwing: ItemBankError.invalidResponse) }
            }
        }
    }

    private func setData(_ data: [String: Any], at reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func deleteDocument(_ reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.delete { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}

enum ItemBankError: LocalizedError {
    case unsupportedContent
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedContent: return "Este contenido futuro no se puede copiar al banco sin riesgo."
        case .invalidResponse: return "El banco de ítems no devolvió una respuesta válida."
        }
    }
}
