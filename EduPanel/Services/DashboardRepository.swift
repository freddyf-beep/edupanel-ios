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
        async let schoolDoc = getDocument(userRef.collection("perfil_info").document("colegio"))
        async let preferencesDoc = getDocument(userRef.collection("perfil_info").document("preferencias"))
        async let scheduleDoc = getDocument(userRef.collection("configuracion").document("horario"))
        async let levelsDoc = getDocument(userRef.collection("configuracion").document("nivel_mapping"))
        async let stateDoc = getDocument(userRef.collection("horario_estado").document(DateHelpers.dateKey(for: date)))

        let profileSnapshot = try await profileDoc
        let schoolSnapshot = try await schoolDoc
        let preferencesSnapshot = try await preferencesDoc
        let scheduleSnapshot = try await scheduleDoc
        let levelsSnapshot = try await levelsDoc
        let stateSnapshot = try await stateDoc

        let profileData = profileSnapshot.data()
        let schoolData = schoolSnapshot.data()
        let preferencesData = preferencesSnapshot.data()
        let scheduleData = scheduleSnapshot.data()
        let levelsData = levelsSnapshot.data()
        let stateData = stateSnapshot.data()

        let rawClasses = scheduleData?["clases"] as? [[String: Any]] ?? []
        let horario = rawClasses.compactMap(ClaseHorario.from(dictionary:))
        let classState = stateData?["estado"] as? [String: Bool] ?? [:]
        let studentsByCourse = await loadStudentsByCourse(for: horario, uid: uid)
        let studentCounts = studentsByCourse.mapValues(\.count)
        let rawCursoTipos = levelsData?["cursoTipos"] as? [String: String] ?? [:]
        let cursoTipos = rawCursoTipos.mapValues { TipoCurricular.from($0) }

        return DashboardSnapshot(
            date: date,
            profile: PerfilUsuario.from(dictionary: profileData),
            school: InfoColegio.from(dictionary: schoolData),
            preferences: PreferenciasUsuario.from(dictionary: preferencesData),
            horario: horario,
            classState: classState,
            studentCounts: studentCounts,
            studentsByCourse: studentsByCourse,
            nivelMapping: levelsData?["mapping"] as? [String: String] ?? [:],
            cursoTipos: cursoTipos
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

    func saveProfile(_ profile: PerfilUsuario) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        var data = profile.dictionary
        data["updatedAt"] = FieldValue.serverTimestamp()

        try await setData(
            data,
            at: db.collection("users").document(uid).collection("perfil_info").document("main"),
            merge: false
        )
    }

    func saveSchool(_ school: InfoColegio) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        var data = school.dictionary
        data["updatedAt"] = FieldValue.serverTimestamp()

        try await setData(
            data,
            at: db.collection("users").document(uid).collection("perfil_info").document("colegio"),
            merge: true
        )
    }

    func savePreferences(_ preferences: PreferenciasUsuario) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        var data = preferences.dictionary
        data["updatedAt"] = FieldValue.serverTimestamp()

        try await setData(
            data,
            at: db.collection("users").document(uid).collection("perfil_info").document("preferencias"),
            merge: true
        )
    }

    private func loadStudentsByCourse(for horario: [ClaseHorario], uid: String) async -> [String: [EstudiantePerfil]] {
        let cursos = Array(Set(horario.filter(\.isAcademic).map(\.resumen))).sorted()
        var result: [String: [EstudiantePerfil]] = [:]

        for curso in cursos {
            let studentsRef = db
                .collection("users")
                .document(uid)
                .collection("estudiantes")

            if let data = try? await getStudentDocument(for: curso, in: studentsRef).data(),
               let alumnos = data["alumnos"] as? [[String: Any]] {
                result[curso] = alumnos
                    .enumerated()
                    .compactMap { index, value in EstudiantePerfil.from(dictionary: value, index: index) }
                    .sorted { lhs, rhs in
                        if lhs.orden != rhs.orden {
                            return lhs.orden < rhs.orden
                        }
                        return lhs.nombre.localizedCaseInsensitiveCompare(rhs.nombre) == .orderedAscending
                    }
            } else {
                result[curso] = []
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
}
