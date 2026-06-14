import Foundation
import FirebaseAuth
import FirebaseFirestore

struct EvaluacionesRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private func getUid() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }
        return uid
    }

    private func userDoc(col: String, id: String) throws -> DocumentReference {
        let uid = try getUid()
        return db.collection("users").document(uid).collection(col).document(id)
    }

    private func userCol(col: String) throws -> CollectionReference {
        let uid = try getUid()
        return db.collection("users").document(uid).collection(col)
    }

    // MARK: - Listas de Cotejo

    func cargarListasCotejo(asignatura: String, curso: String) async throws -> [ListaCotejoTemplate] {
        let snapshot = try await getDocuments(try userCol(col: "listas_cotejo"))
        return snapshot.documents
            .compactMap { decode(ListaCotejoTemplate.self, from: $0) }
            .filter { $0.asignatura == asignatura && $0.curso == curso }
            .sorted { ($0.fechaActualizacion ?? .distantPast) > ($1.fechaActualizacion ?? .distantPast) }
    }

    func cargarListaCotejo(id: String) async throws -> ListaCotejoTemplate? {
        let snapshot = try await getDocument(try userDoc(col: "listas_cotejo", id: id))
        guard snapshot.exists else { return nil }
        return decode(ListaCotejoTemplate.self, from: snapshot)
    }

    func guardarListaCotejo(_ lista: ListaCotejoTemplate) async throws {
        var normalizada = lista
        normalizada.normalizar()
        guard var dict = normalizada.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if lista.fechaActualizacion == nil {
            dict["createdAt"] = FieldValue.serverTimestamp()
        }
        try await setData(dict, at: try userDoc(col: "listas_cotejo", id: normalizada.id), merge: true)
    }

    func eliminarListaCotejo(id: String) async throws {
        try await deleteDocument(try userDoc(col: "listas_cotejo", id: id))
        let evalId = EvaluacionesIDs.buildListaEvaluacionId(listaId: id)
        try? await deleteDocument(try userDoc(col: "listas_cotejo_evaluaciones", id: evalId))
    }

    func cargarEvaluacionLista(listaId: String) async throws -> ListaCotejoEvaluacion? {
        let id = EvaluacionesIDs.buildListaEvaluacionId(listaId: listaId)
        let snapshot = try await getDocument(try userDoc(col: "listas_cotejo_evaluaciones", id: id))
        guard snapshot.exists else { return nil }
        return decode(ListaCotejoEvaluacion.self, from: snapshot)
    }

    func guardarEvaluacionLista(_ evaluacion: ListaCotejoEvaluacion) async throws {
        guard var dict = evaluacion.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if evaluacion.bloqueada == true {
            dict["bloqueadaEn"] = FieldValue.serverTimestamp()
        } else {
            dict["bloqueadaEn"] = FieldValue.delete()
        }
        try await setData(dict, at: try userDoc(col: "listas_cotejo_evaluaciones", id: evaluacion.id), merge: true)
    }

    // MARK: - Rúbricas

    func cargarRubricas(asignatura: String, curso: String) async throws -> [RubricaTemplate] {
        let snapshot = try await getDocuments(try userCol(col: "rubricas"))
        return snapshot.documents
            .compactMap { decode(RubricaTemplate.self, from: $0) }
            .filter { $0.asignatura == asignatura && $0.curso == curso }
            .sorted { ($0.fechaActualizacion ?? .distantPast) > ($1.fechaActualizacion ?? .distantPast) }
    }

    func cargarRubrica(id: String) async throws -> RubricaTemplate? {
        let snapshot = try await getDocument(try userDoc(col: "rubricas", id: id))
        guard snapshot.exists else { return nil }
        return decode(RubricaTemplate.self, from: snapshot)
    }

    func guardarRubrica(_ rubrica: RubricaTemplate) async throws {
        var normalizada = rubrica
        normalizada.normalizar()
        guard var dict = normalizada.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if rubrica.fechaActualizacion == nil {
            dict["createdAt"] = FieldValue.serverTimestamp()
        }
        try await setData(dict, at: try userDoc(col: "rubricas", id: normalizada.id), merge: true)
    }

    func eliminarRubrica(id: String) async throws {
        try await deleteDocument(try userDoc(col: "rubricas", id: id))
        let evalId = EvaluacionesIDs.buildRubricaEvaluacionId(rubricaId: id)
        try? await deleteDocument(try userDoc(col: "rubricas_evaluaciones", id: evalId))
    }

    func cargarEvaluacionRubrica(rubricaId: String) async throws -> EvaluacionRubrica? {
        let id = EvaluacionesIDs.buildRubricaEvaluacionId(rubricaId: rubricaId)
        let snapshot = try await getDocument(try userDoc(col: "rubricas_evaluaciones", id: id))
        guard snapshot.exists else { return nil }
        return decode(EvaluacionRubrica.self, from: snapshot)
    }

    func guardarEvaluacionRubrica(_ evaluacion: EvaluacionRubrica) async throws {
        guard var dict = evaluacion.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if evaluacion.bloqueada == true {
            dict["bloqueadaEn"] = FieldValue.serverTimestamp()
        } else {
            dict["bloqueadaEn"] = FieldValue.delete()
        }
        try await setData(dict, at: try userDoc(col: "rubricas_evaluaciones", id: evaluacion.id), merge: true)
    }

    // MARK: - Decodificación

    private func decode<T: Decodable>(_ type: T.Type, from snapshot: DocumentSnapshot) -> T? {
        guard var dict = snapshot.data() else { return nil }
        dict["id"] = snapshot.documentID
        guard var value = T.from(dictionary: dict) else { return nil }
        if var lista = value as? ListaCotejoTemplate {
            lista.fechaActualizacion = timestampDate(dict)
            value = lista as! T
        } else if var rubrica = value as? RubricaTemplate {
            rubrica.fechaActualizacion = timestampDate(dict)
            value = rubrica as! T
        }
        return value
    }

    private func timestampDate(_ dict: [String: Any]) -> Date? {
        let raw = dict["updatedAt"] ?? dict["createdAt"]
        return (raw as? Timestamp)?.dateValue()
    }

    // MARK: - Firestore helpers

    private func getDocument(_ ref: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            ref.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: DashboardRepositoryError.missingUser)
                }
            }
        }
    }

    private func getDocuments(_ col: CollectionReference) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            col.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: DashboardRepositoryError.missingUser)
                }
            }
        }
    }

    private func setData(_ data: [String: Any], at ref: DocumentReference, merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func deleteDocument(_ ref: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

enum EvaluacionesRepositoryError: LocalizedError {
    case encoding

    var errorDescription: String? {
        switch self {
        case .encoding: return "No se pudo preparar el documento para guardar."
        }
    }
}
