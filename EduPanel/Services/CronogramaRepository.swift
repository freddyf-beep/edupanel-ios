import Foundation
import FirebaseAuth
import FirebaseFirestore

struct ActividadCronograma: Identifiable, Hashable {
    var id: String
    var nombre: String
    var tipo: String
    var dia: String
    var semana: Int
    var hora: String
    var duracion: String
    var unidad: String
    var color: String
    var cursoOrigen: String?

    var duracionMinutos: Int {
        let limpio = duracion.lowercased()
        let scanner = Scanner(string: limpio)
        _ = scanner.scanUpToCharacters(from: .decimalDigits)
        guard let numero = scanner.scanDouble() else { return 45 }
        return limpio.contains("h") ? Int((numero * 60).rounded()) : Int(numero.rounded())
    }

    static func from(dictionary: [String: Any]) -> ActividadCronograma? {
        guard let nombre = dictionary["nombre"] as? String else { return nil }
        let rawSemana = dictionary["semana"]
        let semana = rawSemana as? Int ?? Int(rawSemana as? Double ?? 0)
        return ActividadCronograma(
            id: dictionary["id"] as? String ?? UUID().uuidString,
            nombre: nombre,
            tipo: dictionary["tipo"] as? String ?? "actividad",
            dia: dictionary["dia"] as? String ?? "Lunes",
            semana: max(1, semana),
            hora: dictionary["hora"] as? String ?? "08:30",
            duracion: dictionary["duracion"] as? String ?? "45 min",
            unidad: dictionary["unidad"] as? String ?? "",
            color: dictionary["color"] as? String ?? "#F03E6E",
            cursoOrigen: dictionary["cursoOrigen"] as? String
        )
    }

    var firestoreDictionary: [String: Any] {
        [
            "id": id,
            "nombre": nombre,
            "tipo": tipo,
            "dia": dia,
            "semana": semana,
            "hora": hora,
            "duracion": duracion,
            "unidad": unidad,
            "color": color
        ]
    }
}

struct CronogramaRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func cargarActividades(asignatura: String, curso: String) async throws -> [ActividadCronograma] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let docId = "crono_" + PlanificacionRepository.buildDocId(asignatura: asignatura, nivel: curso)
        let snapshot = try await getDocument(db.collection("users").document(uid).collection("cronogramas").document(docId))
        guard let raw = snapshot.data()?["actividades"] as? [[String: Any]] else { return [] }
        return raw.compactMap(ActividadCronograma.from(dictionary:))
    }

    func guardarActividades(asignatura: String, curso: String, actividades: [ActividadCronograma]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let docId = "crono_" + PlanificacionRepository.buildDocId(asignatura: asignatura, nivel: curso)
        let ref = db.collection("users").document(uid).collection("cronogramas").document(docId)
        try await setData(
            [
                "asignatura": asignatura,
                "nivel": curso,
                "actividades": actividades.map(\.firestoreDictionary),
                "updatedAt": FieldValue.serverTimestamp()
            ],
            at: ref
        )
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

    private func setData(_ data: [String: Any], at ref: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.setData(data, merge: false) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
