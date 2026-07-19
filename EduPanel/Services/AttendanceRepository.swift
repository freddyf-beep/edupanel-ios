import FirebaseAuth
import FirebaseFirestore
import Foundation

enum AttendanceRepositoryError: LocalizedError {
    case missingUser
    case invalidPathComponent(String)
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "No hay una sesión docente activa."
        case .invalidPathComponent:
            return "El contexto del colegio no es válido."
        case .invalidDocument:
            return "El registro de asistencia existe, pero no se pudo leer de forma segura."
        }
    }
}

enum AttendanceDocumentPath {
    static func documentID(subject: String, course: String, dateKey: String) -> String {
        "libro_\(slug("\(subject)_\(course)"))_\(dateKey)"
    }

    static func path(
        uid: String,
        scope: AttendanceDataScope,
        subject: String,
        course: String,
        dateKey: String
    ) throws -> String {
        let cleanUID = try validComponent(uid)
        let schoolID = try validComponent(scope.schoolID)
        let documentID = try validComponent(documentID(subject: subject, course: course, dateKey: dateKey))
        if scope.isPrincipal {
            return "users/\(cleanUID)/libro_clases/\(documentID)"
        }
        return "users/\(cleanUID)/colegios/\(schoolID)/libro_clases/\(documentID)"
    }

    static func slug(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
        var result = ""
        var lastWasUnderscore = false

        for scalar in folded.unicodeScalars {
            let code = scalar.value
            let isASCIIAlphanumeric = (48...57).contains(code) || (97...122).contains(code)
            if isASCIIAlphanumeric {
                result.unicodeScalars.append(scalar)
                lastWasUnderscore = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "_" {
                if !lastWasUnderscore {
                    result.append("_")
                    lastWasUnderscore = true
                }
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func validComponent(_ value: String) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != ".", clean != "..", !clean.contains("/") else {
            throw AttendanceRepositoryError.invalidPathComponent(value)
        }
        return clean
    }
}

protocol AttendanceRepositoryProtocol {
    func load(
        scope: AttendanceDataScope,
        subject: String,
        course: String,
        dateKey: String
    ) async throws -> AttendanceBook?

    func save(_ book: AttendanceBook, scope: AttendanceDataScope) async throws
}

struct AttendanceScopedContext: Sendable {
    /// `nil` indica que el colegio principal debe usar su ruta global legacy.
    let schedule: [AttendanceScheduleBlock]?
    /// `nil` indica que el colegio principal debe usar su ruta global legacy.
    let students: [AttendanceRosterStudent]?
}

protocol AttendanceContextRepositoryProtocol {
    func load(scope: AttendanceDataScope, course: String) async throws -> AttendanceScopedContext
}

/// Lee horario y nómina en el mismo contexto capturado para el libro. Para el
/// colegio principal, una ruta anidada ausente conserva el fallback global que
/// usa la web; un colegio secundario nunca cae al espacio de otro colegio.
struct AttendanceContextRepository: AttendanceContextRepositoryProtocol {
    private let db: Firestore
    private let uidProvider: () -> String?

    init(
        db: Firestore = Firestore.firestore(),
        uidProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.db = db
        self.uidProvider = uidProvider
    }

    func load(scope: AttendanceDataScope, course: String) async throws -> AttendanceScopedContext {
        guard let uid = uidProvider() else { throw AttendanceRepositoryError.missingUser }
        let user = db.collection("users").document(uid)
        let school = user.collection("colegios").document(scope.schoolID)

        async let scheduleSnapshot = getDocument(
            school.collection("configuracion").document("horario")
        )
        async let studentsSnapshot = getStudentDocument(
            course: course,
            in: school.collection("estudiantes")
        )

        let scheduleDocument = try await scheduleSnapshot
        let studentDocument = try await studentsSnapshot

        let schedule: [AttendanceScheduleBlock]?
        let rawClasses = scheduleDocument.data()?["clases"] as? [[String: Any]] ?? []
        if rawClasses.isEmpty {
            schedule = scope.isPrincipal ? nil : []
        } else {
            schedule = rawClasses.compactMap(ClaseHorario.from(dictionary:)).map(Self.scheduleBlock)
        }

        let students: [AttendanceRosterStudent]?
        if studentDocument.exists {
            let rawStudents = studentDocument.data()?["alumnos"] as? [[String: Any]] ?? []
            students = rawStudents
                .enumerated()
                .compactMap { index, value in EstudiantePerfil.from(dictionary: value, index: index) }
                .sorted {
                    $0.orden == $1.orden
                        ? $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending
                        : $0.orden < $1.orden
                }
                .map { AttendanceRosterStudent(id: $0.id, name: $0.nombre) }
        } else {
            students = scope.isPrincipal ? nil : []
        }

        return AttendanceScopedContext(schedule: schedule, students: students)
    }

    private static func scheduleBlock(_ item: ClaseHorario) -> AttendanceScheduleBlock {
        AttendanceScheduleBlock(
            id: item.id,
            course: item.resumen,
            weekday: item.dia,
            startTime: item.horaInicio,
            endTime: item.horaFin,
            isFree: item.tipo == .libre
        )
    }

    private func getStudentDocument(
        course: String,
        in collection: CollectionReference
    ) async throws -> DocumentSnapshot {
        let current = try await getDocument(collection.document(DashboardRepository.buildCursoId(course)))
        guard !current.exists else { return current }

        let legacyID = DashboardRepository.buildLegacyCursoId(course)
        guard legacyID != DashboardRepository.buildCursoId(course) else { return current }
        return try await getDocument(collection.document(legacyID))
    }

    private func getDocument(_ reference: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            reference.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: AttendanceRepositoryError.invalidDocument)
                }
            }
        }
    }
}

struct AttendanceRepository: AttendanceRepositoryProtocol {
    private let db: Firestore
    private let uidProvider: () -> String?

    init(
        db: Firestore = Firestore.firestore(),
        uidProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.db = db
        self.uidProvider = uidProvider
    }

    func load(
        scope: AttendanceDataScope,
        subject: String,
        course: String,
        dateKey: String
    ) async throws -> AttendanceBook? {
        let reference = try documentReference(
            scope: scope,
            subject: subject,
            course: course,
            dateKey: dateKey
        )
        let snapshot = try await getDocument(reference)
        guard snapshot.exists else { return nil }
        guard let data = snapshot.data(), let book = Self.parseBook(data),
              book.subject == subject, book.course == course, book.dateKey == dateKey else {
            throw AttendanceRepositoryError.invalidDocument
        }
        return book
    }

    func save(_ book: AttendanceBook, scope: AttendanceDataScope) async throws {
        let reference = try documentReference(
            scope: scope,
            subject: book.subject,
            course: book.course,
            dateKey: book.dateKey
        )
        let payload: [String: Any] = [
            "asignatura": book.subject,
            "curso": book.course,
            "fecha": book.dateKey,
            "bloques": book.blocks.map(Self.blockDictionary),
            "schemaVersion": 2,
            "schoolId": scope.schoolID,
            "yearId": scope.yearID,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await setData(payload, at: reference)
    }

    private func documentReference(
        scope: AttendanceDataScope,
        subject: String,
        course: String,
        dateKey: String
    ) throws -> DocumentReference {
        guard let uid = uidProvider() else { throw AttendanceRepositoryError.missingUser }
        let path = try AttendanceDocumentPath.path(
            uid: uid,
            scope: scope,
            subject: subject,
            course: course,
            dateKey: dateKey
        )
        return db.document(path)
    }

    private func getDocument(_ reference: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            reference.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: AttendanceRepositoryError.invalidDocument)
                }
            }
        }
    }

    private func setData(_ data: [String: Any], at reference: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(data, merge: false) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func parseBook(_ data: [String: Any]) -> AttendanceBook? {
        guard let subject = data["asignatura"] as? String,
              let course = data["curso"] as? String,
              let dateKey = data["fecha"] as? String,
              let rawBlocks = data["bloques"] as? [[String: Any]] else { return nil }
        let blocks = rawBlocks.compactMap(parseBlock)
        guard blocks.count == rawBlocks.count else { return nil }
        return AttendanceBook(subject: subject, course: course, dateKey: dateKey, blocks: blocks)
    }

    private static func parseBlock(_ data: [String: Any]) -> AttendanceBlock? {
        guard let id = data["id"] as? String,
              let startTime = data["horaInicio"] as? String,
              let endTime = data["horaFin"] as? String,
              let rawAttendance = data["asistencia"] as? [[String: Any]] else { return nil }
        let attendance = rawAttendance.compactMap(parseAttendance)
        guard attendance.count == rawAttendance.count else { return nil }

        return AttendanceBlock(
            id: id,
            label: data["bloque"] as? String ?? "Bloque",
            startTime: startTime,
            endTime: endTime,
            objective: data["objetivo"] as? String ?? "",
            activity: data["actividad"] as? String ?? "",
            isSigned: Read.bool(data["firmado"]) ?? false,
            attendance: attendance,
            attendanceSchemaVersion: Read.int(data["asistenciaSchemaVersion"]),
            signedAt: data["firmadoAt"] as? String,
            signedByUID: data["firmadoPorUid"] as? String,
            reopenedAt: data["reabiertoAt"] as? String,
            reopenedByUID: data["reabiertoPorUid"] as? String,
            reopeningReason: data["motivoReapertura"] as? String
        )
    }

    static func parseAttendance(_ data: [String: Any]) -> StudentAttendance? {
        guard let id = data["id"] as? String,
              let name = data["nombre"] as? String,
              let rawStatus = data["estado"] as? String else { return nil }
        let confirmed = data.keys.contains("confirmado") ? Read.bool(data["confirmado"]) : nil
        let method = (data["metodo"] as? String).flatMap(AttendanceMethod.init(rawValue:))
        return StudentAttendance(
            id: id,
            name: name,
            status: AttendanceStatus(rawValue: rawStatus),
            confirmed: confirmed,
            method: method,
            markedAt: data["marcadoAt"] as? String
        )
    }

    private static func blockDictionary(_ block: AttendanceBlock) -> [String: Any] {
        var data: [String: Any] = [
            "id": block.id,
            "bloque": block.label,
            "horaInicio": block.startTime,
            "horaFin": block.endTime,
            "objetivo": block.objective,
            "actividad": block.activity,
            "firmado": block.isSigned,
            "asistencia": block.attendance.map(attendanceDictionary),
            "asistenciaSchemaVersion": 2
        ]
        data.setOptional(block.signedAt, for: "firmadoAt")
        data.setOptional(block.signedByUID, for: "firmadoPorUid")
        data.setOptional(block.reopenedAt, for: "reabiertoAt")
        data.setOptional(block.reopenedByUID, for: "reabiertoPorUid")
        data.setOptional(block.reopeningReason, for: "motivoReapertura")
        return data
    }

    static func attendanceDictionary(_ attendance: StudentAttendance) -> [String: Any] {
        var data: [String: Any] = [
            "id": attendance.id,
            "nombre": attendance.name,
            "estado": attendance.status.rawValue
        ]
        if let confirmed = attendance.confirmed { data["confirmado"] = confirmed }
        data.setOptional(attendance.method?.rawValue, for: "metodo")
        data.setOptional(attendance.markedAt, for: "marcadoAt")
        return data
    }
}

private enum Read {
    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

private extension Dictionary where Key == String, Value == Any {
    mutating func setOptional(_ value: String?, for key: String) {
        if let value { self[key] = value }
    }
}
