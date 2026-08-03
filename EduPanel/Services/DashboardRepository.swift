import Foundation
import FirebaseAuth
import FirebaseFirestore

enum ActiveSchoolScope {
    private static let prefix = "edupanel.active-school."

    static func schoolID(for uid: String) -> String {
        UserDefaults.standard.string(forKey: prefix + uid) ?? "principal"
    }

    static func storedSchoolID(for uid: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + uid)
    }

    static func setSchoolID(_ schoolID: String, for uid: String) {
        UserDefaults.standard.set(schoolID, forKey: prefix + uid)
    }
}

enum DashboardRepositoryError: LocalizedError {
    case missingUser

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "No hay una sesión activa."
        }
    }
}

/// Caché en memoria del snapshot del dashboard. Cada pantalla llama
/// fetchDashboard al aparecer; sin caché eso repite las mismas lecturas
/// de Firestore en cada navegación. Cualquier escritura la invalida.
private actor DashboardCacheStore {
    private var snapshot: DashboardSnapshot?
    private var uid: String?
    private var dateKey: String?
    private var fetchedAt = Date.distantPast

    func get(uid: String, dateKey: String, maxAge: TimeInterval) -> DashboardSnapshot? {
        guard self.uid == uid,
              self.dateKey == dateKey,
              let snapshot,
              Date().timeIntervalSince(fetchedAt) < maxAge else { return nil }
        return snapshot
    }

    func set(_ nuevo: DashboardSnapshot, uid: String, dateKey: String) {
        snapshot = nuevo
        self.uid = uid
        self.dateKey = dateKey
        fetchedAt = Date()
    }

    func clear() {
        snapshot = nil
    }
}

struct DashboardRepository {
    private static let cache = DashboardCacheStore()
    private static let cacheMaxAge: TimeInterval = 25

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchDashboard(for date: Date = Date(), forceRefresh: Bool = false) async throws -> DashboardSnapshot {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let dateKey = DateHelpers.dateKey(for: date)
        if !forceRefresh,
           let cached = await Self.cache.get(uid: uid, dateKey: dateKey, maxAge: Self.cacheMaxAge) {
            return cached
        }

        let userRef = db.collection("users").document(uid)

        async let profileTask = getDocument(userRef.collection("perfil_info").document("main"))
        async let legacySchoolTask = getDocument(userRef.collection("perfil_info").document("colegio"))
        async let preferencesTask = getDocument(userRef.collection("perfil_info").document("preferencias"))
        let profileSnapshot = try await profileTask
        let legacySchoolSnapshot = try await legacySchoolTask
        let preferencesSnapshot = try await preferencesTask
        var preferences = PreferenciasUsuario.from(dictionary: preferencesSnapshot.data())
        let requestedSchoolID = Self.validSchoolID(preferences.colegioActivoId)
        let localSchoolID = Self.validSchoolID(ActiveSchoolScope.storedSchoolID(for: uid))
        let schoolID = try await resolveActiveSchoolID(
            userRef: userRef,
            requestedID: requestedSchoolID,
            fallbackID: localSchoolID
        )
        ActiveSchoolScope.setSchoolID(schoolID, for: uid)
        if requestedSchoolID != schoolID {
            try? await setData(
                [
                    "colegioActivoId": schoolID,
                    "updatedAt": FieldValue.serverTimestamp()
                ],
                at: userRef.collection("perfil_info").document("preferencias"),
                merge: true
            )
        }
        preferences.colegioActivoId = schoolID
        let schoolRef = userRef.collection("colegios").document(schoolID)

        async let scopedSchoolTask = getDocument(schoolRef)
        async let coursesTask = getDocuments(schoolRef.collection("cursos"))
        async let journeyTask = getDocument(schoolRef.collection("configuracion").document("jornada"))
        async let periodsTask = getDocuments(schoolRef.collection("horarios"))
        async let scopedScheduleTask = getDocument(schoolRef.collection("configuracion").document("horario"))
        async let legacyScheduleTask = getDocument(userRef.collection("configuracion").document("horario"))
        async let scopedLevelsTask = getDocument(schoolRef.collection("configuracion").document("nivel_mapping"))
        async let legacyLevelsTask = getDocument(userRef.collection("configuracion").document("nivel_mapping"))
        async let scopedStateTask = getDocument(schoolRef.collection("horario_estado").document(dateKey))
        async let legacyStateTask = getDocument(userRef.collection("horario_estado").document(dateKey))

        let scopedSchoolSnapshot = try await scopedSchoolTask
        let coursesSnapshot = try await coursesTask
        let journeySnapshot = try await journeyTask
        let periodsSnapshot = try await periodsTask
        let scopedScheduleSnapshot = try await scopedScheduleTask
        let legacyScheduleSnapshot = try await legacyScheduleTask
        let scopedLevelsSnapshot = try await scopedLevelsTask
        let legacyLevelsSnapshot = try await legacyLevelsTask
        let scopedStateSnapshot = try await scopedStateTask
        let legacyStateSnapshot = try await legacyStateTask

        let catalog = coursesSnapshot.documents.compactMap { AcademicCourse.from(id: $0.documentID, dictionary: $0.data()) }
        let periods = periodsSnapshot.documents.compactMap { SchedulePeriod.from(id: $0.documentID, dictionary: $0.data()) }
        let activePeriod = AcademicContract.resolvePublishedPeriod(periods, for: date)
        let scopedLegacyClasses = scopedScheduleSnapshot.data()?["clases"] as? [[String: Any]]
        let globalLegacyClasses = legacyScheduleSnapshot.data()?["clases"] as? [[String: Any]]
        let legacySchedule = (
            scopedLegacyClasses ??
            (schoolID == "principal" ? globalLegacyClasses : nil) ??
            []
        ).compactMap(ClaseHorario.from(dictionary:))
        let horario = AcademicContract.resolveSchedule(periods, legacy: legacySchedule, for: date)
        let levelsData = scopedLevelsSnapshot.exists
            ? scopedLevelsSnapshot.data()
            : (schoolID == "principal" ? legacyLevelsSnapshot.data() : nil)
        let stateData = scopedStateSnapshot.exists
            ? scopedStateSnapshot.data()
            : (schoolID == "principal" ? legacyStateSnapshot.data() : nil)
        let classState = stateData?["estado"] as? [String: Bool] ?? [:]
        let studentsByCourse = await loadStudentsByCourse(
            catalog: catalog,
            legacySchedule: horario,
            uid: uid,
            schoolID: schoolID
        )
        var studentCounts = studentsByCourse.mapValues(\.count)
        for course in catalog {
            if let count = studentCounts[course.courseID] {
                studentCounts[course.name] = count
                studentCounts[course.dataKey] = count
            }
        }
        let rawCursoTipos = levelsData?["cursoTipos"] as? [String: String] ?? [:]
        let cursoTipos = rawCursoTipos.mapValues { TipoCurricular.from($0) }

        let snapshot = DashboardSnapshot(
            date: date,
            profile: PerfilUsuario.from(dictionary: profileSnapshot.data()),
            school: InfoColegio.from(dictionary: scopedSchoolSnapshot.exists ? scopedSchoolSnapshot.data() : legacySchoolSnapshot.data()),
            preferences: preferences,
            horario: horario,
            classState: classState,
            studentCounts: studentCounts,
            studentsByCourse: studentsByCourse,
            nivelMapping: levelsData?["mapping"] as? [String: String] ?? [:],
            subjectLevelMapping: levelsData?["asignaturaMapping"] as? [String: [String: String]] ?? [:],
            cursoTipos: cursoTipos,
            schoolID: schoolID,
            courseCatalog: catalog,
            journey: JourneyConfig.from(dictionary: journeySnapshot.data()),
            schedulePeriods: periods,
            activeSchedulePeriodID: activePeriod?.periodID
        )
        await Self.cache.set(snapshot, uid: uid, dateKey: dateKey)
        return snapshot
    }

    /// Carga el colegio del mismo ámbito que usa Evaluaciones y sus plantillas
    /// `formatos_export`. El documento legado queda como fallback para cuentas
    /// todavía no migradas a `users/{uid}/colegios/{id}`.
    func fetchExportSchool(scope: EvaluacionScope) async throws -> InfoColegio {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }
        let schoolId: String
        switch scope {
        case .principal:
            schoolId = "principal"
        case .colegio(let id):
            let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !clean.contains("/") else {
                return .empty
            }
            schoolId = clean
        }

        let user = db.collection("users").document(uid)
        let scopedSchool = user.collection("colegios").document(schoolId)
        async let scopedTask = getDocument(scopedSchool)
        async let formatsTask: QuerySnapshot? = try? await getDocuments(
            scopedSchool.collection("formatos_export")
        )
        let modernSchools: QuerySnapshot?
        if schoolId == "principal" {
            modernSchools = try await getDocuments(user.collection("colegios").limit(to: 1))
        } else {
            modernSchools = nil
        }
        let scoped = try await scopedTask
        let formatsSnapshot = await formatsTask
        let canUseLegacy = schoolId == "principal" && modernSchools?.documents.isEmpty == true
        let data: [String: Any]?
        if scoped.exists {
            data = scoped.data()
        } else if canUseLegacy {
            data = try await getDocument(user.collection("perfil_info").document("colegio")).data()
        } else {
            data = nil
        }
        var school = InfoColegio.from(dictionary: data)
        let templates = formatsSnapshot?.documents.compactMap { document in
            ExportFormatTemplate.from(id: document.documentID, dictionary: document.data())
        } ?? []
        if let formatsSnapshot, !formatsSnapshot.documents.isEmpty {
            school.formatos = templates
        }
        return school
    }

    func saveClassState(_ state: [String: Bool], for date: Date = Date()) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let schoolID = try await activeSchoolID(uid: uid)
        let ref = db.collection("users").document(uid)
            .collection("colegios").document(schoolID)
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

        let schoolID = try await activeSchoolID(uid: uid)
        let schoolRef = db.collection("users").document(uid).collection("colegios").document(schoolID)
        let periods = try await getDocuments(schoolRef.collection("horarios")).documents.compactMap {
            SchedulePeriod.from(id: $0.documentID, dictionary: $0.data())
        }
        let now = Date()
        let active = AcademicContract.resolvePublishedPeriod(periods, for: now)
        let period: SchedulePeriod
        if let active {
            period = SchedulePeriod(
                periodID: active.periodID,
                name: active.name,
                startDateKey: active.startDateKey,
                endDateKey: active.endDateKey,
                status: active.status,
                timeZone: AcademicContract.timeZoneIdentifier,
                blocks: horario
            )
        } else {
            let year = Calendar(identifier: .gregorian).component(.year, from: now)
            period = SchedulePeriod(
                periodID: "periodo_\(year)",
                name: "Horario \(year)",
                startDateKey: String(format: "%04d-01-01", year),
                endDateKey: String(format: "%04d-12-31", year),
                status: .published,
                timeZone: AcademicContract.timeZoneIdentifier,
                blocks: horario
            )
            try AcademicContract.validatePublishedPeriod(period, among: periods)
        }
        try await saveSchedule(period, schoolID: schoolID)
    }

    func saveSchedule(_ period: SchedulePeriod, schoolID: String, journey: JourneyConfig? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw DashboardRepositoryError.missingUser }
        try AcademicContract.validateBatch(existing: [], candidates: period.blocks, journey: journey)
        let schoolRef = db.collection("users").document(uid).collection("colegios").document(schoolID)
        let periodRef = schoolRef.collection("horarios").document(period.periodID)
        let existingPeriod = try await getDocument(periodRef)
        let batch = db.batch()
        var periodData = period.firestoreDictionary
        if !existingPeriod.exists { periodData["createdAt"] = FieldValue.serverTimestamp() }
        periodData["updatedAt"] = FieldValue.serverTimestamp()
        batch.setData(periodData, forDocument: periodRef, merge: true)
        batch.setData(
            ["clases": period.blocks.map(\.firestoreDictionary), "updatedAt": FieldValue.serverTimestamp()],
            forDocument: schoolRef.collection("configuracion").document("horario"),
            merge: true
        )
        try await commit(batch)
    }

    func saveSchool(_ school: InfoColegio) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        var data = school.dictionary
        if let logoBase64 = school.logoBase64 { data["logoBase64"] = logoBase64 }
        else { data["logoBase64"] = FieldValue.delete() }
        if let logoDerBase64 = school.logoDerBase64 { data["logoDerBase64"] = logoDerBase64 }
        else { data["logoDerBase64"] = FieldValue.delete() }
        data["updatedAt"] = FieldValue.serverTimestamp()

        let schoolID = try await activeSchoolID(uid: uid)
        try await setData(data, at: db.collection("users").document(uid).collection("colegios").document(schoolID), merge: true)
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
        if let schoolID = Self.validSchoolID(preferences.colegioActivoId) {
            ActiveSchoolScope.setSchoolID(schoolID, for: uid)
        }
        await Self.cache.clear()
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
        await Self.cache.clear()
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

        let schoolID = try await activeSchoolID(uid: uid)
        let courseCatalog = try await getDocuments(
            db.collection("users").document(uid).collection("colegios").document(schoolID).collection("cursos")
        ).documents.compactMap { AcademicCourse.from(id: $0.documentID, dictionary: $0.data()) }
        let dataKey = courseCatalog.first(where: { $0.name == course || $0.courseID == course })?.dataKey ?? Self.buildCursoId(course)
        let ref = db.collection("users").document(uid)
            .collection("colegios").document(schoolID)
            .collection("estudiantes").document(dataKey)
        try await setData([
            "alumnos": rawAlumnos,
            "updatedAt": FieldValue.serverTimestamp()
        ], at: ref, merge: true)
    }

    func saveCourse(_ course: AcademicCourse, previousDataKey: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw DashboardRepositoryError.missingUser }
        if let previousDataKey, previousDataKey != course.dataKey { throw AcademicContractError.immutableDataKey }
        if course.kind == .oficial {
            guard let level = course.level, let section = course.section,
                  try AcademicContract.officialCourseName(level: level, section: section) == course.name else {
                throw AcademicContractError.invalidOfficialCourse
            }
        } else if course.workshopName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw AcademicContractError.invalidWorkshop
        }
        let schoolID = try await activeSchoolID(uid: uid)
        let courseRef = db.collection("users").document(uid).collection("colegios").document(schoolID)
            .collection("cursos").document(course.courseID)
        let existingCourse = try await getDocument(courseRef)
        var data = course.firestoreDictionary
        if !existingCourse.exists { data["createdAt"] = FieldValue.serverTimestamp() }
        data["updatedAt"] = FieldValue.serverTimestamp()
        try await setData(data, at: courseRef, merge: true)
    }

    func archiveCourse(_ course: AcademicCourse, currentSchedule: [ClaseHorario]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw DashboardRepositoryError.missingUser }
        let schoolID = try await activeSchoolID(uid: uid)
        let schoolRef = db.collection("users").document(uid).collection("colegios").document(schoolID)
        let archivedAt = Date()
        let eligibleAt = Calendar(identifier: .gregorian).date(byAdding: .day, value: AcademicContract.archiveGraceDays, to: archivedAt) ?? archivedAt
        let matching = currentSchedule.filter { $0.courseID == course.courseID || $0.resumen == course.name }
        let remaining = currentSchedule.filter { $0.courseID != course.courseID && $0.resumen != course.name }
        let today = AcademicContract.dateKey(for: archivedAt)
        let periods = try await getDocuments(schoolRef.collection("horarios")).documents.compactMap {
            SchedulePeriod.from(id: $0.documentID, dictionary: $0.data())
        }
        let affectedPeriods = periods.compactMap { period -> (SchedulePeriod, [ClaseHorario])? in
            guard period.endDateKey >= today else { return nil }
            let blocks = period.blocks.filter { $0.courseID == course.courseID || $0.resumen == course.name }
            return blocks.isEmpty ? nil : (period, blocks)
        }
        let batch = db.batch()
        batch.setData([
            "estado": AcademicCourseStatus.archived.rawValue,
            "archivedAt": Timestamp(date: archivedAt),
            "deleteEligibleAt": Timestamp(date: eligibleAt),
            "archiveSnapshot": [
                "scheduleBlocks": matching.map(\.firestoreDictionary),
                "periodBlocks": affectedPeriods.map { ["periodId": $0.0.periodID, "blocks": $0.1.map(\.firestoreDictionary)] },
                "createdAt": Timestamp(date: archivedAt)
            ],
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: schoolRef.collection("cursos").document(course.courseID), merge: true)
        batch.setData(
            ["clases": remaining.map(\.firestoreDictionary), "updatedAt": FieldValue.serverTimestamp()],
            forDocument: schoolRef.collection("configuracion").document("horario"),
            merge: true
        )
        for (period, _) in affectedPeriods {
            let next = period.blocks.filter { $0.courseID != course.courseID && $0.resumen != course.name }
            batch.setData(
                ["bloques": next.map(\.firestoreDictionary), "updatedAt": FieldValue.serverTimestamp()],
                forDocument: schoolRef.collection("horarios").document(period.periodID),
                merge: true
            )
        }
        try await commit(batch)
    }

    func restoreCourse(_ course: AcademicCourse) async throws -> (restored: Int, conflicts: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { throw DashboardRepositoryError.missingUser }
        let schoolID = try await activeSchoolID(uid: uid)
        let schoolRef = db.collection("users").document(uid).collection("colegios").document(schoolID)
        let courseRef = schoolRef.collection("cursos").document(course.courseID)
        let snapshot = try await getDocument(courseRef)
        let archive = snapshot.data()?["archiveSnapshot"] as? [String: Any]
        let legacyCandidates = (archive?["scheduleBlocks"] as? [[String: Any]] ?? [])
            .compactMap(ClaseHorario.from(dictionary:))
        let periodArchives = archive?["periodBlocks"] as? [[String: Any]] ?? []
        let batch = db.batch()
        var restored = 0
        var conflicts = 0

        if !legacyCandidates.isEmpty {
            let legacyRef = schoolRef.collection("configuracion").document("horario")
            let legacySnapshot = try await getDocument(legacyRef)
            var accepted = (legacySnapshot.data()?["clases"] as? [[String: Any]] ?? [])
                .compactMap(ClaseHorario.from(dictionary:))
            for candidate in legacyCandidates where !accepted.contains(where: { $0.id == candidate.id }) {
                do {
                    try AcademicContract.validateBatch(existing: accepted, candidates: [candidate], journey: nil)
                    accepted.append(candidate)
                    restored += 1
                } catch {
                    conflicts += 1
                }
            }
            batch.setData(
                ["clases": accepted.map(\.firestoreDictionary), "updatedAt": FieldValue.serverTimestamp()],
                forDocument: legacyRef,
                merge: true
            )
        }

        for archived in periodArchives {
            guard let periodID = archived["periodId"] as? String else { continue }
            let candidates = (archived["blocks"] as? [[String: Any]] ?? []).compactMap(ClaseHorario.from(dictionary:))
            let periodRef = schoolRef.collection("horarios").document(periodID)
            let periodSnapshot = try await getDocument(periodRef)
            guard let period = periodSnapshot.data().flatMap({ SchedulePeriod.from(id: periodID, dictionary: $0) }) else {
                conflicts += candidates.count
                continue
            }
            var accepted = period.blocks
            for candidate in candidates {
                do {
                    try AcademicContract.validateBatch(existing: accepted, candidates: [candidate], journey: nil)
                    accepted.append(candidate)
                    restored += 1
                } catch {
                    conflicts += 1
                }
            }
            batch.setData(
                ["bloques": accepted.map(\.firestoreDictionary), "updatedAt": FieldValue.serverTimestamp()],
                forDocument: periodRef,
                merge: true
            )
        }
        batch.setData([
            "estado": AcademicCourseStatus.active.rawValue,
            "archivedAt": FieldValue.delete(),
            "deleteEligibleAt": FieldValue.delete(),
            "archiveSnapshot": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: courseRef, merge: true)
        try await commit(batch)
        return (restored, conflicts)
    }

    func saveJourney(_ journey: JourneyConfig) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw DashboardRepositoryError.missingUser }
        let schoolID = try await activeSchoolID(uid: uid)
        var data = journey.firestoreDictionary
        data["updatedAt"] = FieldValue.serverTimestamp()
        try await setData(data, at: db.collection("users").document(uid).collection("colegios").document(schoolID)
            .collection("configuracion").document("jornada"), merge: true)
    }

    func getCurriculumSubjectsForLevel(_ level: String) async throws -> [CurriculumSubjectOption] {
        let controlledOptions = AcademicContract.subjects(for: level)
        return try await withThrowingTaskGroup(of: (Int, CurriculumSubjectOption).self) { group in
            for (index, option) in controlledOptions.enumerated() {
                group.addTask {
                    let documentID = AcademicContract.normalizedKey("\(option.label)_\(level)")
                    let snapshot = try await getDocument(db.collection("curriculo").document(documentID))
                    let data = snapshot.data()
                    let isPublished = snapshot.exists && data?["ready"] as? Bool == true &&
                        data?["curso"] == nil &&
                        AcademicContract.normalizedKey(data?["asignatura"] as? String ?? "") == option.id &&
                        (data?["nivel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == level
                    return (index, CurriculumSubjectOption(
                        id: option.id,
                        label: option.label,
                        level: level,
                        availability: isPublished ? .available : .unavailable
                    ))
                }
            }
            var result: [(Int, CurriculumSubjectOption)] = []
            for try await item in group { result.append(item) }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func importLegacyCourses(
        schedule: [ClaseHorario],
        levelMapping: [String: String],
        courseKinds: [String: TipoCurricular]
    ) async throws -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { throw DashboardRepositoryError.missingUser }
        let schoolID = try await activeSchoolID(uid: uid)
        let collection = db.collection("users").document(uid).collection("colegios").document(schoolID).collection("cursos")
        let existing = try await getDocuments(collection).documents.compactMap {
            AcademicCourse.from(id: $0.documentID, dictionary: $0.data())
        }
        let candidates = try AcademicContract.legacyCourseCandidates(
            schedule: schedule,
            levelMapping: levelMapping,
            courseKinds: courseKinds,
            excludingDataKeys: Set(existing.map(\.dataKey))
        )
        let batch = db.batch()
        for course in candidates {
            var value = course.firestoreDictionary
            value["createdAt"] = FieldValue.serverTimestamp()
            value["updatedAt"] = FieldValue.serverTimestamp()
            batch.setData(value, forDocument: collection.document(course.courseID), merge: false)
        }
        if !candidates.isEmpty { try await commit(batch) }
        return candidates.count
    }

    func updateCourseDetails(oldName: String, newName: String, newColorHex: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }

        let cleanOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOldName.isEmpty, !cleanNewName.isEmpty else { return }

        let userRef = db.collection("users").document(uid)
        let schoolID = try await activeSchoolID(uid: uid)
        let schoolRef = userRef.collection("colegios").document(schoolID)
        let catalog = try await getDocuments(schoolRef.collection("cursos")).documents.compactMap {
            AcademicCourse.from(id: $0.documentID, dictionary: $0.data())
        }

        // Los cursos v2 viven bajo el colegio activo. Actualizar solamente el
        // documento legado dejaba la tarjeta del curso y sus estudiantes con
        // un nombre distinto al del horario.
        if var course = catalog.first(where: {
            AcademicContract.normalizedKey($0.name) == AcademicContract.normalizedKey(cleanOldName)
        }) {
            let originalName = course.name
            if course.kind == .oficial {
                guard AcademicContract.normalizedKey(cleanNewName) == AcademicContract.normalizedKey(originalName) else {
                    throw AcademicContractError.invalidOfficialCourse
                }
                // La identidad de un curso oficial es nivel + sección; solo
                // se permite corregir el color desde este editor.
                course.name = originalName
            } else {
                course.name = cleanNewName
                course.workshopName = cleanNewName
            }
            course.colorHex = newColorHex
            try await saveCourse(course, previousDataKey: course.dataKey)
            try await renameCourseInSchedule(
                schoolRef: schoolRef,
                courseID: course.courseID,
                oldName: originalName,
                newName: course.name,
                colorHex: newColorHex
            )
            try await renameCourseMappings(
                userRef: userRef,
                schoolRef: schoolRef,
                schoolID: schoolID,
                oldName: originalName,
                newName: course.name
            )
            await Self.cache.clear()
            return
        }

        // Compatibilidad acotada para cuentas todavía no migradas. Nunca se
        // escribe el horario global de un colegio secundario.
        guard schoolID == "principal" else { return }
        let scheduleRef = userRef.collection("configuracion").document("horario")
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
            let studentsCollection = userRef.collection("estudiantes")
            let oldDoc = try await getDocument(studentsCollection.document(oldCursoId))
            if oldDoc.exists, let oldData = oldDoc.data() {
                try await setData(oldData, at: studentsCollection.document(newCursoId), merge: false)
                try await studentsCollection.document(oldCursoId).delete()
            }

            let levelsRef = userRef.collection("configuracion").document("nivel_mapping")
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

    private func renameCourseInSchedule(
        schoolRef: DocumentReference,
        courseID: String,
        oldName: String,
        newName: String,
        colorHex: String
    ) async throws {
        let matches: ([String: Any]) -> Bool = { value in
            if let storedCourseID = value["courseId"] as? String, storedCourseID == courseID {
                return true
            }
            let storedName = value["resumen"] as? String ?? ""
            return AcademicContract.normalizedKey(storedName) == AcademicContract.normalizedKey(oldName)
        }

        let scheduleRef = schoolRef.collection("configuracion").document("horario")
        let scheduleSnapshot = try await getDocument(scheduleRef)
        if let rawBlocks = scheduleSnapshot.data()?["clases"] as? [[String: Any]] {
            var changed = false
            let updatedBlocks = rawBlocks.map { value -> [String: Any] in
                guard matches(value) else { return value }
                changed = true
                var next = value
                next["resumen"] = newName
                next["color"] = colorHex
                next["courseId"] = courseID
                return next
            }
            if changed {
                try await setData(
                    ["clases": updatedBlocks, "updatedAt": FieldValue.serverTimestamp()],
                    at: scheduleRef,
                    merge: true
                )
            }
        }

        let periods = try await getDocuments(schoolRef.collection("horarios"))
        for period in periods.documents {
            guard let rawBlocks = period.data()["bloques"] as? [[String: Any]] else { continue }
            var changed = false
            let updatedBlocks = rawBlocks.map { value -> [String: Any] in
                guard matches(value) else { return value }
                changed = true
                var next = value
                next["resumen"] = newName
                next["color"] = colorHex
                next["courseId"] = courseID
                return next
            }
            if changed {
                try await setData(
                    ["bloques": updatedBlocks, "updatedAt": FieldValue.serverTimestamp()],
                    at: period.reference,
                    merge: true
                )
            }
        }
    }

    private func renameCourseMappings(
        userRef: DocumentReference,
        schoolRef: DocumentReference,
        schoolID: String,
        oldName: String,
        newName: String
    ) async throws {
        guard AcademicContract.normalizedKey(oldName) != AcademicContract.normalizedKey(newName) else { return }

        var references = [schoolRef.collection("configuracion").document("nivel_mapping")]
        if schoolID == "principal" {
            references.append(userRef.collection("configuracion").document("nivel_mapping"))
        }

        for reference in references {
            let snapshot = try await getDocument(reference)
            guard snapshot.exists, var data = snapshot.data() else { continue }
            var changed = false

            if let mapping = data["mapping"] as? [String: String] {
                var next = mapping
                for key in mapping.keys where AcademicContract.normalizedKey(key) == AcademicContract.normalizedKey(oldName) {
                    if next[newName] == nil { next[newName] = mapping[key] }
                    next.removeValue(forKey: key)
                    changed = true
                }
                data["mapping"] = next
            }

            if let courseTypes = data["cursoTipos"] as? [String: String] {
                var next = courseTypes
                for key in courseTypes.keys where AcademicContract.normalizedKey(key) == AcademicContract.normalizedKey(oldName) {
                    if next[newName] == nil { next[newName] = courseTypes[key] }
                    next.removeValue(forKey: key)
                    changed = true
                }
                data["cursoTipos"] = next
            }

            if let subjectMapping = data["asignaturaMapping"] as? [String: [String: String]] {
                var next = subjectMapping
                for key in subjectMapping.keys where AcademicContract.normalizedKey(key) == AcademicContract.normalizedKey(oldName) {
                    let oldSubjects = next.removeValue(forKey: key) ?? [:]
                    var targetSubjects = next[newName] ?? [:]
                    for (subject, level) in oldSubjects where targetSubjects[subject] == nil {
                        targetSubjects[subject] = level
                    }
                    next[newName] = targetSubjects
                    changed = true
                }
                data["asignaturaMapping"] = next
            }

            if changed {
                data["updatedAt"] = FieldValue.serverTimestamp()
                try await setData(data, at: reference, merge: false)
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

        let schoolID = try await activeSchoolID(uid: uid)
        let scopedRef = db.collection("users").document(uid)
            .collection("colegios").document(schoolID)
            .collection("configuracion").document("nivel_mapping")
        try await setData(
            [
                "mapping": mapping,
                "cursoTipos": rawTypes,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            at: scopedRef,
            merge: true
        )
        if schoolID == "principal" {
            try await setData(
                [
                    "mapping": mapping,
                    "cursoTipos": rawTypes,
                    "updatedAt": FieldValue.serverTimestamp()
                ],
                at: db.collection("users").document(uid).collection("configuracion").document("nivel_mapping"),
                merge: true
            )
        }
        await Self.cache.clear()
    }

    func saveSubjectLevelMapping(course: String, subject: String, level: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }
        let cleanCourse = course.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLevel = level.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCourse.isEmpty, !cleanSubject.isEmpty else { return }

        let schoolID = try await activeSchoolID(uid: uid)
        let scopedRef = db.collection("users").document(uid)
            .collection("colegios").document(schoolID)
            .collection("configuracion").document("nivel_mapping")
        let scopedSnapshot = try await getDocument(scopedRef)
        var subjectMapping = scopedSnapshot.data()?["asignaturaMapping"] as? [String: [String: String]] ?? [:]
        var courseMapping = subjectMapping[cleanCourse] ?? [:]
        if cleanLevel.isEmpty {
            courseMapping.removeValue(forKey: cleanSubject)
        } else {
            courseMapping[cleanSubject] = cleanLevel
        }
        if courseMapping.isEmpty {
            subjectMapping.removeValue(forKey: cleanCourse)
        } else {
            subjectMapping[cleanCourse] = courseMapping
        }
        var payload: [String: Any] = [
            "asignaturaMapping": subjectMapping,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if schoolID == "principal" {
            let legacySnapshot = try await getDocument(
                db.collection("users").document(uid)
                    .collection("configuracion").document("nivel_mapping")
            )
            if scopedSnapshot.data()?["mapping"] == nil,
               let mapping = legacySnapshot.data()?["mapping"] {
                payload["mapping"] = mapping
            }
            if scopedSnapshot.data()?["cursoTipos"] == nil,
               let courseTypes = legacySnapshot.data()?["cursoTipos"] {
                payload["cursoTipos"] = courseTypes
            }
        }
        try await setData(payload, at: scopedRef, merge: true)
        await Self.cache.clear()
    }

    private func loadStudentsByCourse(
        catalog: [AcademicCourse],
        legacySchedule: [ClaseHorario],
        uid: String,
        schoolID: String
    ) async -> [String: [EstudiantePerfil]] {
        guard !catalog.isEmpty else {
            return await loadStudentsByCourse(
                for: legacySchedule,
                uid: uid,
                schoolID: schoolID
            )
        }
        let userRef = db.collection("users").document(uid)
        let scoped = userRef.collection("colegios").document(schoolID).collection("estudiantes")
        let legacy = userRef.collection("estudiantes")
        let catalogKeys = Set(catalog.flatMap {
            [$0.dataKey, $0.courseID, Self.buildCursoId($0.name)]
        })
        let scheduleOnlyCourses = Array(Set(
            legacySchedule
                .filter(\.isAcademic)
                .map(\.resumen)
                .filter { !catalogKeys.contains(Self.buildCursoId($0)) }
        ))

        return await withTaskGroup(of: (String, [EstudiantePerfil]).self) { group in
            for course in catalog {
                group.addTask {
                    let candidates = Array(Set([
                        course.dataKey,
                        course.courseID,
                        Self.buildCursoId(course.name),
                        Self.buildLegacyCursoId(course.name)
                    ])).filter { !$0.isEmpty }
                    for key in candidates {
                        if let snapshot = try? await getDocument(scoped.document(key)),
                           snapshot.exists,
                           let students = Self.students(from: snapshot.data()) {
                            return (course.courseID, students)
                        }
                    }
                    if schoolID == "principal" {
                        for key in candidates {
                            if let snapshot = try? await getDocument(legacy.document(key)),
                               snapshot.exists,
                               let students = Self.students(from: snapshot.data()) {
                                return (course.courseID, students)
                            }
                        }
                    }
                    return (course.courseID, [])
                }
            }
            for courseName in scheduleOnlyCourses {
                group.addTask {
                    let candidates = Array(Set([
                        Self.buildCursoId(courseName),
                        Self.buildLegacyCursoId(courseName)
                    ])).filter { !$0.isEmpty }
                    for key in candidates {
                        if let snapshot = try? await getDocument(scoped.document(key)),
                           snapshot.exists,
                           let students = Self.students(from: snapshot.data()) {
                            return (courseName, students)
                        }
                    }
                    if schoolID == "principal" {
                        for key in candidates {
                            if let snapshot = try? await getDocument(legacy.document(key)),
                               snapshot.exists,
                               let students = Self.students(from: snapshot.data()) {
                                return (courseName, students)
                            }
                        }
                    }
                    return (courseName, [])
                }
            }
            var result: [String: [EstudiantePerfil]] = [:]
            for await (key, students) in group { result[key] = students }
            return result
        }
    }

    private func loadStudentsByCourse(
        for horario: [ClaseHorario],
        uid: String,
        schoolID: String
    ) async -> [String: [EstudiantePerfil]] {
        let cursos = Array(Set(horario.filter(\.isAcademic).map(\.resumen))).sorted()
        let user = db.collection("users").document(uid)
        let scopedStudents = user.collection("colegios").document(schoolID).collection("estudiantes")
        let legacyStudents = user.collection("estudiantes")

        // Cargar todos los cursos en paralelo: un viaje a Firestore por curso,
        // pero simultáneos en vez de en serie.
        return await withTaskGroup(of: (String, [EstudiantePerfil]).self) { group in
            for curso in cursos {
                group.addTask {
                    var data = try? await getStudentDocument(for: curso, in: scopedStudents).data()
                    if data == nil, schoolID == "principal" {
                        data = try? await getStudentDocument(for: curso, in: legacyStudents).data()
                    }
                    if let alumnos = data?["alumnos"] as? [[String: Any]] {
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

    private static func students(from data: [String: Any]?) -> [EstudiantePerfil]? {
        guard let raw = data?["alumnos"] as? [[String: Any]] else { return nil }
        return raw.enumerated().compactMap { index, value in
            EstudiantePerfil.from(dictionary: value, index: index)
        }.sorted { lhs, rhs in
            lhs.orden == rhs.orden
                ? lhs.nombre.localizedCaseInsensitiveCompare(rhs.nombre) == .orderedAscending
                : lhs.orden < rhs.orden
        }
    }

    private static func validSchoolID(_ raw: String?) -> String? {
        guard let clean = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clean.isEmpty, !clean.contains("/") else { return nil }
        return clean
    }

    private func resolveActiveSchoolID(
        userRef: DocumentReference,
        requestedID: String?,
        fallbackID: String? = nil
    ) async throws -> String {
        if requestedID == "principal" {
            return "principal"
        }

        if let requestedID {
            let requested = try await getDocument(userRef.collection("colegios").document(requestedID))
            if requested.exists {
                return requestedID
            }
        }

        if fallbackID == "principal" {
            return "principal"
        }
        if let fallbackID, fallbackID != requestedID {
            let fallback = try await getDocument(userRef.collection("colegios").document(fallbackID))
            if fallback.exists {
                return fallbackID
            }
        }

        let available = try await getDocuments(userRef.collection("colegios").limit(to: 1))
        return available.documents.first?.documentID ?? "principal"
    }

    private func activeSchoolID(uid: String) async throws -> String {
        let snapshot = try await getDocument(
            db.collection("users").document(uid).collection("perfil_info").document("preferencias")
        )
        let requested = Self.validSchoolID(snapshot.data()?["colegioActivoId"] as? String)
        let resolved = try await resolveActiveSchoolID(
            userRef: db.collection("users").document(uid),
            requestedID: requested,
            fallbackID: Self.validSchoolID(ActiveSchoolScope.storedSchoolID(for: uid))
        )
        ActiveSchoolScope.setSchoolID(resolved, for: uid)
        return resolved
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

    private func getDocuments(_ ref: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            ref.getDocuments { snapshot, error in
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
        await Self.cache.clear()
    }

    private func commit(_ batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
        await Self.cache.clear()
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
        if let courseID, !courseID.isEmpty { data["courseId"] = courseID }
        if let subjectID, !subjectID.isEmpty { data["subjectId"] = subjectID }
        if let moduleID, !moduleID.isEmpty { data["moduleId"] = moduleID }
        if exceptional { data["exceptional"] = true }
        return data
    }
}
