import Foundation

enum AttendanceStatus: Equatable, Hashable, Sendable {
    case present
    case absent
    case late
    case withdrawn
    case invalid(String)

    static let validCases: [AttendanceStatus] = [.present, .absent, .late, .withdrawn]

    init(rawValue: String) {
        switch rawValue {
        case "presente": self = .present
        case "ausente": self = .absent
        case "atraso": self = .late
        case "retirado": self = .withdrawn
        default: self = .invalid(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .present: return "presente"
        case .absent: return "ausente"
        case .late: return "atraso"
        case .withdrawn: return "retirado"
        case .invalid(let value): return value
        }
    }

    var title: String {
        switch self {
        case .present: return "Presente"
        case .absent: return "Ausente"
        case .late: return "Atraso"
        case .withdrawn: return "Retirado"
        case .invalid: return "Estado inválido"
        }
    }

    var shortTitle: String {
        switch self {
        case .present: return "P"
        case .absent: return "A"
        case .late: return "T"
        case .withdrawn: return "R"
        case .invalid: return "!"
        }
    }

    var systemImage: String {
        switch self {
        case .present: return "checkmark.circle.fill"
        case .absent: return "xmark.circle.fill"
        case .late: return "clock.badge.exclamationmark.fill"
        case .withdrawn: return "rectangle.portrait.and.arrow.forward.fill"
        case .invalid: return "exclamationmark.triangle.fill"
        }
    }

    var isValid: Bool {
        if case .invalid = self { return false }
        return true
    }
}

enum AttendanceMethod: String, Codable, CaseIterable, Sendable {
    case manual
    case bulk = "masivo"
    case keyboard = "teclado"
    case voice = "voz"
    case copied = "copiado"
    case qr
}

struct AttendanceQRResolveRequest: Encodable, Sendable {
    let payload: String
    let schoolId: String
    let yearId: String
    let course: String
}

struct AttendanceQRResolveResponse: Decodable, Equatable, Sendable {
    let studentId: String
    let studentName: String
    let credentialId: String
}

enum AttendanceQRFailure: LocalizedError, Equatable, Sendable {
    case signedBlock
    case invalidQRCode
    case sessionExpired
    case forbidden
    case revoked
    case stale
    case scopeMismatch
    case studentNotInRoster
    case studentNotInActiveBlock
    case rateLimited(seconds: Int?)
    case configuration
    case temporarilyUnavailable
    case offline
    case timeout
    case server

    var errorDescription: String? {
        switch self {
        case .signedBlock:
            return "Este bloque está firmado. Reábrelo con un motivo antes de cambiar la asistencia."
        case .invalidQRCode:
            return "Este código QR no es válido. Usa una tarjeta vigente de EduPanel."
        case .sessionExpired:
            return "Tu sesión venció. Vuelve a iniciar sesión antes de escanear."
        case .forbidden:
            return "Esta tarjeta pertenece a otro docente o colegio."
        case .revoked:
            return "Esta tarjeta fue revocada. Solicita una tarjeta nueva."
        case .stale:
            return "Esta tarjeta es anterior a una rotación. Usa la versión más reciente."
        case .scopeMismatch:
            return "Esta tarjeta corresponde a otro curso o año escolar."
        case .studentNotInRoster:
            return "El estudiante ya no pertenece a la nómina de este curso."
        case .studentNotInActiveBlock:
            return "El estudiante no está en la lista del bloque activo. No se hizo ningún cambio."
        case .rateLimited(let seconds):
            if let seconds {
                return "Se hicieron demasiadas lecturas. Espera \(seconds) segundos para continuar."
            }
            return "Se hicieron demasiadas lecturas. Espera un momento para continuar."
        case .configuration:
            return "El servicio QR necesita configuración del servidor. Inténtalo más tarde."
        case .temporarilyUnavailable:
            return "El servicio QR no está disponible temporalmente. Puedes usar el modo rápido."
        case .offline:
            return "El escaneo QR necesita internet. Puedes continuar con la lista o el modo rápido."
        case .timeout:
            return "La validación tardó demasiado. Revisa la conexión e inténtalo nuevamente."
        case .server:
            return "No pudimos validar la tarjeta. Inténtalo nuevamente sin cambiar la asistencia."
        }
    }
}

enum AttendanceQRApplicationResult: Equatable, Sendable {
    case applied(block: AttendanceBlock, studentName: String)
    case duplicate(studentName: String)
    case requiresConfirmation(studentID: String, studentName: String, previousStatus: AttendanceStatus)
    case signedBlock
    case studentNotFound
}

struct AttendanceQRRecentScan: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case applied
        case duplicate
    }

    let id: String
    let studentName: String
    let outcome: Outcome
    let scannedAt: Date
}

enum AttendanceQRScanState: Equatable, Sendable {
    case ready
    case validating
    case success(studentName: String)
    case duplicate(studentName: String)
    case requiresConfirmation(studentID: String, studentName: String, previousStatus: AttendanceStatus)
    case failure(AttendanceQRFailure)
}

enum AttendanceQRScannerAvailability: Equatable, Sendable {
    case notDetermined
    case ready
    case denied
    case restricted
    case unavailable
    case unsupported
}

enum AttendanceQRScannerCapability {
    static func resolve(
        isSupported: Bool,
        isAvailable: Bool,
        authorization: AttendanceQRScannerAvailability
    ) -> AttendanceQRScannerAvailability {
        guard isSupported else { return .unsupported }
        switch authorization {
        case .notDetermined, .denied, .restricted:
            return authorization
        case .ready, .unavailable, .unsupported:
            return isAvailable ? .ready : .unavailable
        }
    }
}

struct StudentAttendance: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var status: AttendanceStatus
    var confirmed: Bool?
    var method: AttendanceMethod?
    var markedAt: String?
}

struct AttendanceBlock: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var label: String
    var startTime: String
    var endTime: String
    var objective: String
    var activity: String
    var isSigned: Bool
    var attendance: [StudentAttendance]
    var attendanceSchemaVersion: Int?
    var signedAt: String?
    var signedByUID: String?
    var reopenedAt: String?
    var reopenedByUID: String?
    var reopeningReason: String?

    var timeRange: String {
        "\(String(startTime.prefix(5)))–\(String(endTime.prefix(5)))"
    }
}

struct AttendanceBook: Equatable, Sendable {
    var subject: String
    var course: String
    var dateKey: String
    var blocks: [AttendanceBlock]
}

struct AttendanceDataScope: Equatable, Hashable, Sendable {
    static let principalSchoolID = "principal"

    let schoolID: String
    let yearID: String

    static func resolve(activeSchoolID: String?, date: Date, calendar: Calendar = .current) -> Self {
        let clean = activeSchoolID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let schoolID = clean.isEmpty ? principalSchoolID : clean
        return Self(
            schoolID: schoolID.lowercased() == principalSchoolID ? principalSchoolID : schoolID,
            yearID: String(calendar.component(.year, from: date))
        )
    }

    var isPrincipal: Bool { schoolID == Self.principalSchoolID }
}

enum AttendanceDate {
    static func parse(_ dateKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Santiago")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(dateKey) 12:00")
    }
}

struct AttendanceScheduleBlock: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let course: String
    let weekday: String
    let startTime: String
    let endTime: String
    let isFree: Bool
    let courseID: String?
    let subjectID: String?

    init(
        id: String,
        course: String,
        weekday: String,
        startTime: String,
        endTime: String,
        isFree: Bool,
        courseID: String? = nil,
        subjectID: String? = nil
    ) {
        self.id = id
        self.course = course
        self.weekday = weekday
        self.startTime = startTime
        self.endTime = endTime
        self.isFree = isFree
        self.courseID = courseID
        self.subjectID = subjectID
    }
}

struct AttendanceRosterStudent: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
}

struct AttendanceSummary: Equatable, Sendable {
    var present = 0
    var absent = 0
    var late = 0
    var withdrawn = 0
    var confirmedTotal = 0
    var pending = 0
    var invalid = 0

    var allConfirmed: Bool { pending == 0 && invalid == 0 }
}

struct StudentAttendanceAggregate: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var present = 0
    var absent = 0
    var late = 0
    var withdrawn = 0

    var total: Int { present + absent + late + withdrawn }

    var percentage: Double {
        guard total > 0 else { return 0 }
        return (Double(total - absent) / Double(total) * 1_000).rounded() / 10
    }
}

enum AttendanceSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
    case pendingSync
    case failed(String)
}

enum AttendanceLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}
