import Foundation
import FirebaseAuth
import FirebaseFirestore

struct CalificacionesRepository {
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

    private func doc(uid: String, col: String, id: String) -> DocumentReference {
        db.collection("users").document(uid).collection(col).document(id)
    }

    private func doc(uid: String, scope: EvaluacionScope, col: String, id: String) -> DocumentReference {
        let user = db.collection("users").document(uid)
        switch scope {
        case .principal:
            return user.collection(col).document(id)
        case .colegio(let colegioId):
            return user.collection("colegios").document(colegioId).collection(col).document(id)
        }
    }

    func cargar(
        asignatura: String,
        curso: String,
        scope: EvaluacionScope = .principal
    ) async throws -> CalificacionesDoc? {
        let id = EvaluacionesRepository.buildCalificacionesId(asignatura: asignatura, curso: curso)
        let uid = try getUid()

        let propio = try await getDocument(doc(uid: uid, scope: scope, col: "calificaciones", id: id))
        if propio.exists {
            return decode(from: propio)
        }

        if scope == .principal {
            if let invitado = try? await getDocument(doc(uid: EvaluacionesRepository.invitadoUid, col: "calificaciones", id: id)),
               invitado.exists {
                return decode(from: invitado)
            }
        }

        return nil
    }

    private func decode(from snapshot: DocumentSnapshot) -> CalificacionesDoc? {
        guard var dict = snapshot.data() else { return nil }
        if dict["asignatura"] == nil || (dict["asignatura"] as? String)?.isEmpty == true {
            let partes = snapshot.documentID.replacingOccurrences(of: "calif_", with: "").split(separator: "_")
            dict["asignatura"] = partes.first.map(String.init) ?? ""
        }
        return CalificacionesDoc.from(dictionary: dict)
    }

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
}
