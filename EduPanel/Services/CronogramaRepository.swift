import Foundation
import CoreFoundation
import FirebaseAuth
import FirebaseFirestore

struct ActividadCronograma: Identifiable, Hashable {
    var id: String
    var nombre: String
    var tipo: String
    var dia: String
    var semana: Int
    /// Año ISO 8601 al que pertenece `semana`.
    ///
    /// Sin este dato, una actividad de la semana 1 se repetiría visualmente cada
    /// vez que la persona navegara a otro año.
    var anioISO: Int
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
        let minutes = limpio.contains("h") ? (numero * 60).rounded() : numero.rounded()
        guard let exact = Int(exactly: minutes), exact > 0 else { return 45 }
        return min(exact, 24 * 60)
    }

    static func from(
        dictionary: [String: Any],
        legacyFallbackYear: Int = CronoDateHelpers.anioISO(Date())
    ) -> ActividadCronograma? {
        guard let nombre = dictionary["nombre"] as? String else { return nil }
        let decodedWeek = integerValue(dictionary["semana"]) ?? 1
        // Los documentos creados por versiones anteriores no tenían año. Se
        // anclan una sola vez al año ISO de la última actualización del documento
        // (o al año actual si tampoco existe esa metadata) y se migran al guardar.
        let decodedYear = integerValue(dictionary["anioISO"])
            ?? integerValue(dictionary["anio"])
        let anioISO = validISOYear(decodedYear) ?? legacyFallbackYear
        let semana = max(
            1,
            min(CronoDateHelpers.numeroSemanasISO(en: anioISO), decodedWeek)
        )
        let driveFilesData = (dictionary["driveFiles"] as? [[String: Any]]).flatMap {
            try? JSONSerialization.data(withJSONObject: $0)
        }
        return ActividadCronograma(
            id: dictionary["id"] as? String ?? UUID().uuidString,
            nombre: nombre,
            tipo: dictionary["tipo"] as? String ?? "actividad",
            dia: dictionary["dia"] as? String ?? "Lunes",
            semana: semana,
            anioISO: anioISO,
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

    private static func integerValue(_ rawValue: Any?) -> Int? {
        switch rawValue {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(exactly: value)
        case let value as Double where value.isFinite:
            return Int(exactly: value)
        case let value as NSNumber:
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            let number = value.doubleValue
            guard number.isFinite else { return nil }
            return Int(exactly: number)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func validISOYear(_ value: Int?) -> Int? {
        guard let value, (1900...3000).contains(value) else { return nil }
        return value
    }

    var firestoreDictionary: [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "nombre": nombre,
            "tipo": tipo,
            "dia": dia,
            "semana": max(1, min(CronoDateHelpers.numeroSemanasISO(en: anioISO), semana)),
            "anioISO": anioISO,
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
        let data = snapshot.data()
        guard let raw = data?["actividades"] as? [[String: Any]] else { return [] }
        let legacyReferenceDate = (data?["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        let legacyFallbackYear = CronoDateHelpers.anioISO(legacyReferenceDate)
        return raw.compactMap {
            ActividadCronograma.from(
                dictionary: $0,
                legacyFallbackYear: legacyFallbackYear
            )
        }
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

    /// Guarda varios cronogramas como una sola operación de Firestore. Se usa
    /// desde “Todos los cursos” para evitar un estado parcial si una escritura
    /// intermedia falla.
    func guardarActividades(
        asignatura: String,
        actividadesPorCurso: [String: [ActividadCronograma]]
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }
        guard !actividadesPorCurso.isEmpty else { return }

        let batch = db.batch()
        let cronogramas = collection(uid: uid)
        for (curso, actividades) in actividadesPorCurso {
            let docId = "crono_" + PlanificacionRepository.buildDocId(
                asignatura: asignatura,
                nivel: curso
            )
            batch.setData(
                [
                    "asignatura": asignatura,
                    "nivel": curso,
                    "actividades": actividades.map(\.firestoreDictionary),
                    "updatedAt": FieldValue.serverTimestamp()
                ],
                forDocument: cronogramas.document(docId)
            )
        }
        try await commit(batch)
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

    private func commit(_ batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
