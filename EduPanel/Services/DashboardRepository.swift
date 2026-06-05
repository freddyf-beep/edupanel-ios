import Foundation
import FirebaseAuth
import FirebaseFirestore

enum DashboardRepositoryError: LocalizedError {
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "No hay una sesion activa."
        }
    }
}

struct DashboardRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchDashboard(for date: Date = Date()) async throws -> DashboardSnapshot {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let userRef = db.collection("users").document(uid)

        async let profileDoc = getDocument(userRef.collection("perfil_info").document("main"))
        async let scheduleDoc = getDocument(userRef.collection("configuracion").document("horario"))
        async let stateDoc = getDocument(userRef.collection("horario_estado").document(DateHelpers.dateKey(for: date)))

        let profileSnapshot = try await profileDoc
        let scheduleSnapshot = try await scheduleDoc
        let stateSnapshot = try await stateDoc

        let profileData = profileSnapshot.data()
        let scheduleData = scheduleSnapshot.data()
        let stateData = stateSnapshot.data()

        let rawClasses = scheduleData?["clases"] as? [[String: Any]] ?? []
        let horario = rawClasses.compactMap(ClaseHorario.from(dictionary:))
        let classState = stateData?["estado"] as? [String: Bool] ?? [:]
        let studentCounts = await loadStudentCounts(for: horario, uid: uid)

        return DashboardSnapshot(
            date: date,
            profile: PerfilUsuario.from(dictionary: profileData),
            horario: horario,
            classState: classState,
            studentCounts: studentCounts
        )
    }

    func saveClassState(_ state: [String: Bool], for date: Date = Date()) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let ref = db
            .collection("users")
            .document(uid)
            .collection("horario_estado")
            .document(DateHelpers.dateKey(for: date))

        try await setData([
            "estado": state,
            "updatedAt": FieldValue.serverTimestamp()
        ], at: ref, merge: true)
    }

    private func loadStudentCounts(for horario: [ClaseHorario], uid: String) async -> [String: Int] {
        let cursos = Array(Set(horario.filter(\.isAcademic).map(\.resumen))).sorted()
        var result: [String: Int] = [:]

        for curso in cursos {
            let studentsRef = db
                .collection("users")
                .document(uid)
                .collection("estudiantes")

            if let data = try? await getStudentDocument(for: curso, in: studentsRef).data(),
               let alumnos = data["alumnos"] as? [[String: Any]] {
                result[curso] = alumnos.count
            } else {
                result[curso] = 0
            }
        }

        return result
    }

    private func getStudentDocument(for curso: String, in collection: CollectionReference) async throws -> DocumentSnapshot {
        let cursoId = Self.buildCursoId(curso)
        let snapshot = try await getDocument(collection.document(cursoId))
        if snapshot.exists {
            return snapshot
        }

        let legacyId = Self.buildLegacyCursoId(curso)
        guard legacyId != cursoId else {
            return snapshot
        }

        return try await getDocument(collection.document(legacyId))
    }

    static func buildCursoId(_ curso: String) -> String {
        let folded = curso.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
        var scalars: [UnicodeScalar] = []
        var lastWasUnderscore = false

        for scalar in folded.unicodeScalars {
            let value = scalar.value
            let isAlphanumeric = (48...57).contains(value) || (97...122).contains(value)
            if isAlphanumeric {
                scalars.append(scalar)
                lastWasUnderscore = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "_" {
                if !lastWasUnderscore {
                    scalars.append("_")
                    lastWasUnderscore = true
                }
            }
        }

        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func buildLegacyCursoId(_ curso: String) -> String {
        var scalars: [UnicodeScalar] = []

        for scalar in curso.lowercased().unicodeScalars {
            let value = scalar.value
            let isAlphanumeric = (48...57).contains(value) || (97...122).contains(value)
            scalars.append(isAlphanumeric ? scalar : "_")
        }

        return String(String.UnicodeScalarView(scalars))
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

    private func setData(_ data: [String: Any], at ref: DocumentReference, merge: Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ref.setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
