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
    var googleEventId: String? = nil
    var driveFolderId: String? = nil
    var driveFolderUrl: String? = nil
    var driveFileIds: [String] = []
    var driveFilesData: Data? = nil

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
        let driveFilesData = (dictionary["driveFiles"] as? [[String: Any]]).flatMap {
            try? JSONSerialization.data(withJSONObject: $0)
        }
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
            cursoOrigen: dictionary["cursoOrigen"] as? String,
            googleEventId: dictionary["googleEventId"] as? String,
            driveFolderId: dictionary["driveFolderId"] as? String,
            driveFolderUrl: dictionary["driveFolderUrl"] as? String,
            driveFileIds: dictionary["driveFileIds"] as? [String] ?? [],
            driveFilesData: driveFilesData
        )
    }

    var firestoreDictionary: [String: Any] {
        var result: [String: Any] = [
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
        if let googleEventId { result["googleEventId"] = googleEventId }
        if let driveFolderId { result["driveFolderId"] = driveFolderId }
        if let driveFolderUrl { result["driveFolderUrl"] = driveFolderUrl }
        if !driveFileIds.isEmpty { result["driveFileIds"] = driveFileIds }
        if let driveFilesData,
           let driveFiles = try? JSONSerialization.jsonObject(with: driveFilesData) {
            result["driveFiles"] = driveFiles
        }
        return result
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
        let scopedRef = collection(uid: uid).document(docId)
        let snapshot = try await getDocument(scopedRef)
        guard let raw = snapshot.data()?["actividades"] as? [[String: Any]] else { return [] }
        return raw.compactMap(ActividadCronograma.from(dictionary:))
    }

    func guardarActividades(asignatura: String, curso: String, actividades: [ActividadCronograma]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let docId = "crono_" + PlanificacionRepository.buildDocId(asignatura: asignatura, nivel: curso)
        let ref = collection(uid: uid).document(docId)
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

    private func collection(uid: String) -> CollectionReference {
        let user = db.collection("users").document(uid)
        let schoolID = ActiveSchoolScope.schoolID(for: uid)
        if schoolID == "principal" {
            return user.collection("cronogramas")
        }
        return user.collection("colegios").document(schoolID).collection("cronogramas")
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
