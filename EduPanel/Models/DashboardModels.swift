import Foundation

enum TipoHorario: String, Codable, Hashable {
    case clase
    case taller
    case consejo
    case orientacion
    case trabajoColaborativo = "trabajo_colaborativo"
    case noLectivo = "no_lectivo"
    case almuerzo
    case planificacion
    case recreo
    case libre
    case desconocido

    static func from(_ rawValue: String) -> TipoHorario {
        switch rawValue {
        case "clase": return .clase
        case "taller": return .taller
        case "consejo": return .consejo
        case "orientacion": return .orientacion
        case "trabajo_colaborativo": return .trabajoColaborativo
        case "no_lectivo": return .noLectivo
        case "almuerzo": return .almuerzo
        case "planificacion": return .planificacion
        case "recreo": return .recreo
        case "libre": return .libre
        default: return .desconocido
        }
    }

    var isFreeBlock: Bool {
        switch self {
        case .consejo, .trabajoColaborativo, .noLectivo, .almuerzo, .planificacion, .recreo, .libre:
            return true
        case .clase, .taller, .orientacion, .desconocido:
            return false
        }
    }

    var label: String {
        switch self {
        case .clase: return "Clase"
        case .taller: return "Taller"
        case .consejo: return "Consejo"
        case .orientacion: return "Orientacion"
        case .trabajoColaborativo: return "Trabajo colaborativo"
        case .noLectivo: return "No lectivo"
        case .almuerzo: return "Almuerzo"
        case .planificacion: return "Planificacion"
        case .recreo: return "Recreo"
        case .libre: return "Libre"
        case .desconocido: return "Bloque"
        }
    }
}

struct ClaseHorario: Identifiable, Hashable {
    let id: String
    let resumen: String
    let dia: String
    let horaInicio: String
    let horaFin: String
    let colorHex: String
    let tipo: TipoHorario
    let asignatura: String?

    var isAcademic: Bool {
        !tipo.isFreeBlock && !resumen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var timeRange: String {
        "\(horaInicio) - \(horaFin)"
    }

    static func from(dictionary: [String: Any]) -> ClaseHorario? {
        let resumen = dictionary["resumen"] as? String ?? ""
        let dia = dictionary["dia"] as? String ?? ""
        let horaInicio = dictionary["horaInicio"] as? String ?? ""
        let horaFin = dictionary["horaFin"] as? String ?? ""
        guard !dia.isEmpty, !horaInicio.isEmpty, !horaFin.isEmpty else { return nil }

        return ClaseHorario(
            id: dictionary["uid"] as? String ?? UUID().uuidString,
            resumen: resumen,
            dia: dia,
            horaInicio: horaInicio,
            horaFin: horaFin,
            colorHex: dictionary["color"] as? String ?? "#F43F5E",
            tipo: TipoHorario.from(dictionary["tipo"] as? String ?? "clase"),
            asignatura: dictionary["asignatura"] as? String
        )
    }
}

struct PerfilUsuario: Equatable {
    let tipoProfesor: String
    let especialidad: String
    let biografia: String

    static let empty = PerfilUsuario(tipoProfesor: "Profesor", especialidad: "", biografia: "")

    static func from(dictionary: [String: Any]?) -> PerfilUsuario {
        guard let dictionary else { return .empty }
        return PerfilUsuario(
            tipoProfesor: dictionary["tipoProfesor"] as? String ?? "Profesor",
            especialidad: dictionary["especialidad"] as? String ?? "",
            biografia: dictionary["biografia"] as? String ?? ""
        )
    }
}

struct DashboardSnapshot: Equatable {
    let date: Date
    let profile: PerfilUsuario
    var horario: [ClaseHorario]
    var classState: [String: Bool]
    let studentCounts: [String: Int]

    var todayName: String? {
        DateHelpers.weekdayName(for: date)
    }

    var todayClasses: [ClaseHorario] {
        guard let todayName else { return [] }
        return horario
            .filter { $0.dia == todayName }
            .sorted { $0.horaInicio < $1.horaInicio }
    }

    var academicTodayClasses: [ClaseHorario] {
        todayClasses.filter(\.isAcademic)
    }

    var completedAcademicCount: Int {
        academicTodayClasses.filter { classState[$0.id] == true }.count
    }

    var totalAcademicCount: Int {
        academicTodayClasses.count
    }

    var progress: Double {
        guard totalAcademicCount > 0 else { return 0 }
        return Double(completedAcademicCount) / Double(totalAcademicCount)
    }

    var pendingClasses: [ClaseHorario] {
        academicTodayClasses.filter { classState[$0.id] != true }
    }

    func currentOrNextClass(now: Date = Date()) -> ClaseHorario? {
        let currentMinutes = DateHelpers.minutesSinceMidnight(for: now)
        var next: ClaseHorario?

        for item in todayClasses {
            let start = DateHelpers.minutes(from: item.horaInicio)
            let end = DateHelpers.minutes(from: item.horaFin)
            if currentMinutes >= start && currentMinutes < end {
                return item
            }
            if currentMinutes < start && next == nil {
                next = item
            }
        }
        return next
    }
}

enum DateHelpers {
    static let weekdayMap: [Int: String] = [
        1: "Domingo",
        2: "Lunes",
        3: "Martes",
        4: "Mi\u{00E9}rcoles",
        5: "Jueves",
        6: "Viernes",
        7: "S\u{00E1}bado"
    ]

    static func weekdayName(for date: Date) -> String? {
        let weekday = Calendar.current.component(.weekday, from: date)
        let name = weekdayMap[weekday]
        guard let name, ["Lunes", "Martes", "Mi\u{00E9}rcoles", "Jueves", "Viernes"].contains(name) else {
            return nil
        }
        return name
    }

    static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func minutes(from time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    static func minutesSinceMidnight(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
