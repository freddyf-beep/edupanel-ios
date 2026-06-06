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
        case .orientacion: return "Orientación"
        case .trabajoColaborativo: return "Trabajo colaborativo"
        case .noLectivo: return "No lectivo"
        case .almuerzo: return "Almuerzo"
        case .planificacion: return "Planificación"
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
    var tipoProfesor: String
    var especialidad: String
    var estudios: String
    var biografia: String

    static let empty = PerfilUsuario(tipoProfesor: "Profesor", especialidad: "", estudios: "", biografia: "")

    static func from(dictionary: [String: Any]?) -> PerfilUsuario {
        guard let dictionary else { return .empty }
        return PerfilUsuario(
            tipoProfesor: dictionary["tipoProfesor"] as? String ?? "Profesor",
            especialidad: dictionary["especialidad"] as? String ?? "",
            estudios: dictionary["estudios"] as? String ?? "",
            biografia: dictionary["biografia"] as? String ?? ""
        )
    }

    var dictionary: [String: Any] {
        [
            "tipoProfesor": tipoProfesor,
            "especialidad": especialidad,
            "estudios": estudios,
            "biografia": biografia
        ]
    }
}

struct InfoColegio: Equatable {
    var nombre: String
    var logoBase64: String?
    var encabezadoHabilitado: Bool
    var encabezadoTextoIzq: String
    var encabezadoTextoDer: String
    var logoDerBase64: String?

    static let empty = InfoColegio(
        nombre: "",
        logoBase64: nil,
        encabezadoHabilitado: false,
        encabezadoTextoIzq: "",
        encabezadoTextoDer: "",
        logoDerBase64: nil
    )

    static func from(dictionary: [String: Any]?) -> InfoColegio {
        guard let dictionary else { return .empty }
        return InfoColegio(
            nombre: dictionary["nombre"] as? String ?? "",
            logoBase64: dictionary["logoBase64"] as? String,
            encabezadoHabilitado: dictionary["encabezadoHabilitado"] as? Bool ?? false,
            encabezadoTextoIzq: dictionary["encabezadoTextoIzq"] as? String ?? "",
            encabezadoTextoDer: dictionary["encabezadoTextoDer"] as? String ?? "",
            logoDerBase64: dictionary["logoDerBase64"] as? String
        )
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "nombre": nombre,
            "encabezadoHabilitado": encabezadoHabilitado,
            "encabezadoTextoIzq": encabezadoTextoIzq,
            "encabezadoTextoDer": encabezadoTextoDer
        ]
        if let logoBase64 {
            result["logoBase64"] = logoBase64
        }
        if let logoDerBase64 {
            result["logoDerBase64"] = logoDerBase64
        }
        return result
    }
}

struct PreferenciasUsuario: Equatable {
    var asignaturasHabilitadas: [String]
    var bannerStyle: String
    var onboardingCompletado: Bool

    static let empty = PreferenciasUsuario(asignaturasHabilitadas: [], bannerStyle: "rosa", onboardingCompletado: false)

    static func from(dictionary: [String: Any]?) -> PreferenciasUsuario {
        guard let dictionary else { return .empty }
        return PreferenciasUsuario(
            asignaturasHabilitadas: dictionary["asignaturasHabilitadas"] as? [String] ?? [],
            bannerStyle: dictionary["bannerStyle"] as? String ?? "rosa",
            onboardingCompletado: dictionary["onboardingCompletado"] as? Bool ?? false
        )
    }

    var dictionary: [String: Any] {
        [
            "asignaturasHabilitadas": asignaturasHabilitadas,
            "bannerStyle": bannerStyle,
            "onboardingCompletado": onboardingCompletado
        ]
    }
}

enum TipoCurricular: String, Codable, Hashable {
    case oficial
    case taller
    case libre

    static func from(_ rawValue: String?) -> TipoCurricular {
        switch rawValue {
        case "taller": return .taller
        case "libre": return .libre
        default: return .oficial
        }
    }

    var label: String {
        switch self {
        case .oficial: return "Oficial Mineduc"
        case .taller: return "Taller"
        case .libre: return "Libre"
        }
    }
}

enum CurriculumLevels {
    static let all = [
        "P\u{00E1}rvulos",
        "1ro B\u{00E1}sico",
        "2do B\u{00E1}sico",
        "3ro B\u{00E1}sico",
        "4to B\u{00E1}sico",
        "5to B\u{00E1}sico",
        "6to B\u{00E1}sico",
        "7mo B\u{00E1}sico",
        "8vo B\u{00E1}sico",
        "1ro Medio",
        "2do Medio",
        "3ro Medio",
        "4to Medio"
    ]
}

struct EstudiantePerfil: Identifiable, Equatable, Hashable {
    let id: String
    let nombre: String
    let orden: Int
    let pie: Bool
    let pieDiagnostico: String
    let pieEspecialista: String
    let pieNotas: String

    static func from(dictionary: [String: Any], index: Int) -> EstudiantePerfil? {
        let nombre = dictionary["nombre"] as? String ?? ""
        guard !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let rawOrden = dictionary["orden"]
        let orden = rawOrden as? Int ?? Int(rawOrden as? Double ?? 0)

        return EstudiantePerfil(
            id: dictionary["id"] as? String ?? "est_\(index)",
            nombre: nombre,
            orden: orden > 0 ? orden : index + 1,
            pie: dictionary["pie"] as? Bool ?? false,
            pieDiagnostico: dictionary["pieDiagnostico"] as? String ?? "",
            pieEspecialista: dictionary["pieEspecialista"] as? String ?? "",
            pieNotas: dictionary["pieNotas"] as? String ?? ""
        )
    }
}

struct DashboardSnapshot: Equatable {
    let date: Date
    var profile: PerfilUsuario
    var school: InfoColegio
    var preferences: PreferenciasUsuario
    var horario: [ClaseHorario]
    var classState: [String: Bool]
    let studentCounts: [String: Int]
    let studentsByCourse: [String: [EstudiantePerfil]]
    var nivelMapping: [String: String]
    var cursoTipos: [String: TipoCurricular]

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

    var academicClasses: [ClaseHorario] {
        horario.filter(\.isAcademic)
    }

    var courses: [String] {
        Array(Set(academicClasses.map(\.resumen))).sorted()
    }

    var nonTeachingBlocks: [ClaseHorario] {
        horario.filter { $0.tipo.isFreeBlock }
    }

    var totalAcademicMinutes: Int {
        academicClasses.reduce(0) { total, item in
            total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
        }
    }

    var totalFreeMinutes: Int {
        nonTeachingBlocks.reduce(0) { total, item in
            total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
        }
    }

    var totalStudents: Int {
        studentsByCourse.values.reduce(0) { $0 + $1.count }
    }

    var totalPIEStudents: Int {
        studentsByCourse.values.reduce(0) { total, students in
            total + students.filter(\.pie).count
        }
    }

    var setupChecklist: [ProfileSetupItem] {
        let coursesWithoutLevel = courses.filter { course in
            (cursoTipos[course] ?? .oficial) == .oficial && (nivelMapping[course] ?? "").isEmpty
        }

        return [
            ProfileSetupItem(
                label: "Define tu rol docente",
                target: .identidad,
                isComplete: !profile.tipoProfesor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hint: "Básica, Media o Diferencial"
            ),
            ProfileSetupItem(
                label: "Agrega el nombre de tu colegio",
                target: .identidad,
                isComplete: !school.nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hint: nil
            ),
            ProfileSetupItem(
                label: "Crea al menos un curso con bloques",
                target: .semana,
                isComplete: !courses.isEmpty,
                hint: nil
            ),
            ProfileSetupItem(
                label: "Asocia cada curso a un nivel curricular",
                target: .asignaturas,
                isComplete: !courses.isEmpty && coursesWithoutLevel.isEmpty,
                hint: coursesWithoutLevel.isEmpty ? nil : "Falta: \(coursesWithoutLevel.joined(separator: ", "))"
            ),
            ProfileSetupItem(
                label: "Carga estudiantes en al menos un curso",
                target: .cursos,
                isComplete: studentsByCourse.values.contains { !$0.isEmpty },
                hint: nil
            )
        ]
    }

    var setupProgress: Int {
        let items = setupChecklist
        guard !items.isEmpty else { return 0 }
        let complete = items.filter(\.isComplete).count
        return Int((Double(complete) / Double(items.count) * 100).rounded())
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

struct ProfileSetupItem: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let target: ProfileTabKey
    let isComplete: Bool
    let hint: String?
}

enum ProfileTabKey: String, CaseIterable, Identifiable, Hashable {
    case resumen
    case semana
    case cursos
    case asignaturas
    case identidad
    case conexiones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resumen: return "Resumen"
        case .semana: return "Mi Semana"
        case .cursos: return "Mis Cursos"
        case .asignaturas: return "Asignaturas"
        case .identidad: return "Identidad"
        case .conexiones: return "Conexiones"
        }
    }

    var systemImage: String {
        switch self {
        case .resumen: return "square.grid.2x2.fill"
        case .semana: return "calendar"
        case .cursos: return "folder.fill"
        case .asignaturas: return "book.closed.fill"
        case .identidad: return "person.text.rectangle.fill"
        case .conexiones: return "link"
        }
    }
}

enum DateHelpers {
    static let workdays = ["Lunes", "Martes", "Mi\u{00E9}rcoles", "Jueves", "Viernes"]

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
