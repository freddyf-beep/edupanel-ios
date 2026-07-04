import Foundation
import FirebaseAuth
import FirebaseFirestore

enum DashboardRepositoryError: LocalizedError {
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "No hay una sesión activa."
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
            merge: true
        )
    }

    func saveHorario(_ horario: [ClaseHorario]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        try await setData(
            [
                "clases": horario.map(\.firestoreDictionary),
                "updatedAt": FieldValue.serverTimestamp()
            ],
            at: db.collection("users").document(uid).collection("configuracion").document("horario"),
            merge: true
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

    func saveConnections(googleCalendarConnected: Bool, googleDriveConnected: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let ref = db.collection("users").document(uid).collection("perfil_info").document("preferencias")
        try await setData([
            "googleCalendarConnected": googleCalendarConnected,
            "googleDriveConnected": googleDriveConnected,
            "updatedAt": FieldValue.serverTimestamp()
        ], at: ref, merge: true)
    }

    func saveStudents(_ students: [EstudiantePerfil], for course: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let rawAlumnos = students.map { student -> [String: Any] in
            [
                "id": student.id,
                "nombre": student.nombre,
                "orden": student.orden,
                "pie": student.pie,
                "pieDiagnostico": student.pieDiagnostico,
                "pieEspecialista": student.pieEspecialista,
                "pieNotas": student.pieNotas
            ]
        }

        let cursoId = Self.buildCursoId(course)
        let ref = db.collection("users").document(uid).collection("estudiantes").document(cursoId)
        try await setData([
            "alumnos": rawAlumnos,
            "updatedAt": FieldValue.serverTimestamp()
        ], at: ref, merge: true)
    }

    func updateCourseDetails(oldName: String, newName: String, newColorHex: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let scheduleRef = db.collection("users").document(uid).collection("configuracion").document("horario")
        let snapshot = try await getDocument(scheduleRef)
        guard let data = snapshot.data(),
              let rawClasses = data["clases"] as? [[String: Any]] else {
            return
        }

        var updatedClasses = rawClasses
        for i in 0..<updatedClasses.count {
            if updatedClasses[i]["resumen"] as? String == oldName {
                updatedClasses[i]["resumen"] = newName
                updatedClasses[i]["color"] = newColorHex
            }
        }

        try await setData([
            "clases": updatedClasses,
            "updatedAt": FieldValue.serverTimestamp()
        ], at: scheduleRef, merge: true)

        let oldCursoId = Self.buildCursoId(oldName)
        let newCursoId = Self.buildCursoId(newName)
        if oldCursoId != newCursoId {
            let studentsCollection = db.collection("users").document(uid).collection("estudiantes")
            let oldDoc = try await getDocument(studentsCollection.document(oldCursoId))
            if oldDoc.exists, let oldData = oldDoc.data() {
                try await setData(oldData, at: studentsCollection.document(newCursoId), merge: false)
                try await studentsCollection.document(oldCursoId).delete()
            }

            let levelsRef = db.collection("users").document(uid).collection("configuracion").document("nivel_mapping")
            let levelsDoc = try await getDocument(levelsRef)
            if levelsDoc.exists, var levelsData = levelsDoc.data() {
                if var mapping = levelsData["mapping"] as? [String: String] {
                    if let val = mapping[oldName] {
                        mapping[newName] = val
                        mapping.removeValue(forKey: oldName)
                        levelsData["mapping"] = mapping
                    }
                }
                if var cursoTipos = levelsData["cursoTipos"] as? [String: String] {
                    if let val = cursoTipos[oldName] {
                        cursoTipos[newName] = val
                        cursoTipos.removeValue(forKey: oldName)
                        levelsData["cursoTipos"] = cursoTipos
                    }
                }
                try await setData(levelsData, at: levelsRef, merge: false)
            }
        }
    }

    func saveLevelMapping(_ mapping: [String: String], cursoTipos: [String: TipoCurricular]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let rawTypes = cursoTipos
            .filter { $0.value != .oficial }
            .mapValues(\.rawValue)

        try await setData(
            [
                "mapping": mapping,
                "cursoTipos": rawTypes,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            at: db.collection("users").document(uid).collection("configuracion").document("nivel_mapping"),
            merge: false
        )
    }

    private func loadStudentsByCourse(for horario: [ClaseHorario], uid: String) async -> [String: [EstudiantePerfil]] {
        let cursos = Array(Set(horario.filter(\.isAcademic).map(\.resumen))).sorted()
        let studentsRef = db
            .collection("users")
            .document(uid)
            .collection("estudiantes")

        // Cargar todos los cursos en paralelo: un viaje a Firestore por curso,
        // pero simultáneos en vez de en serie.
        return await withTaskGroup(of: (String, [EstudiantePerfil]).self) { group in
            for curso in cursos {
                group.addTask {
                    if let data = try? await getStudentDocument(for: curso, in: studentsRef).data(),
                       let alumnos = data["alumnos"] as? [[String: Any]] {
                        let estudiantes = alumnos
                            .enumerated()
                            .compactMap { index, value in EstudiantePerfil.from(dictionary: value, index: index) }
                            .sorted { lhs, rhs in
                                if lhs.orden != rhs.orden {
                                    return lhs.orden < rhs.orden
                                }
                                return lhs.nombre.localizedCaseInsensitiveCompare(rhs.nombre) == .orderedAscending
                            }
                        return (curso, estudiantes)
                    }
                    return (curso, [])
                }
            }

            var result: [String: [EstudiantePerfil]] = [:]
            for await (curso, estudiantes) in group {
                result[curso] = estudiantes
            }
            return result
        }
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

extension ClaseHorario {
    var firestoreDictionary: [String: Any] {
        var data: [String: Any] = [
            "uid": id,
            "resumen": resumen,
            "dia": dia,
            "horaInicio": horaInicio,
            "horaFin": horaFin,
            "color": colorHex,
            "tipo": tipo == .desconocido ? "clase" : tipo.rawValue
        ]
        if let asignatura, !asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["asignatura"] = asignatura
        }
        return data
    }
}
