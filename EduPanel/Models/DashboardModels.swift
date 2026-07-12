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

enum ExportFontPreset: String, Equatable {
    case sans, serif, verdana, calibri, georgia

    var cssStack: String {
        switch self {
        case .sans: return "Arial, Helvetica, sans-serif"
        case .serif: return "'Times New Roman', Georgia, serif"
        case .verdana: return "Verdana, Geneva, sans-serif"
        case .calibri: return "Calibri, 'Segoe UI', sans-serif"
        case .georgia: return "Georgia, 'Times New Roman', serif"
        }
    }
}

enum ExportHeaderMode: String, Equatable {
    case completo, compacto, oculto
}

struct ExportDocumentStructure: Equatable {
    var headerShading: String?
    var usesBorders: Bool?
    var signatureCount: Int?
    var signatureLabels: [String]

    static func from(_ value: Any?) -> Self? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let table = dictionary["tablaPrincipal"] as? [String: Any]
        let signatures = dictionary["firmas"] as? [String: Any]
        let rawCount = ExportFormatRead.int(signatures?["cantidad"])
        let labels = (signatures?["etiquetas"] as? [Any] ?? [])
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(50)) }
        let structure = Self(
            headerShading: ExportFormatRead.hex(table?["sombreadoCabecera"]),
            usesBorders: table?["usarBordes"] as? Bool,
            signatureCount: rawCount.map { min(4, max(1, $0)) },
            signatureLabels: Array(labels.prefix(4))
        )
        guard structure.headerShading != nil || structure.usesBorders != nil ||
              structure.signatureCount != nil || !structure.signatureLabels.isEmpty else { return nil }
        return structure
    }
}

struct ExportFormat: Equatable {
    var font: ExportFontPreset?
    var baseFontSize: Double?
    var primaryColor: String?
    var marginMM: Double?
    var titleAlignment: String?
    var headerMode: ExportHeaderMode?
    var showsCurricularData: Bool?
    var showsInstructions: Bool?
    var footerText: String?
    var showsPageNumber: Bool?
    var structure: ExportDocumentStructure?

    static func from(_ value: Any?) -> Self? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let titleAlignment = dictionary["alineacionTitulo"] as? String
        let footerText = (dictionary["pieTexto"] as? String).flatMap { value -> String? in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : String(clean.prefix(180))
        }
        let format = Self(
            font: (dictionary["fuente"] as? String).flatMap(ExportFontPreset.init(rawValue:)),
            baseFontSize: ExportFormatRead.double(dictionary["tamanoBasePt"]).map { min(13, max(9, $0)) },
            primaryColor: ExportFormatRead.hex(dictionary["colorPrimario"]),
            marginMM: ExportFormatRead.double(dictionary["margenMm"]).map { min(22, max(8, $0)) },
            titleAlignment: ["izquierda", "centro"].contains(titleAlignment ?? "") ? titleAlignment : nil,
            headerMode: (dictionary["encabezadoModo"] as? String).flatMap(ExportHeaderMode.init(rawValue:)),
            showsCurricularData: dictionary["mostrarDatosCurriculares"] as? Bool,
            showsInstructions: dictionary["mostrarInstrucciones"] as? Bool,
            footerText: footerText,
            showsPageNumber: dictionary["mostrarNumeroPagina"] as? Bool,
            structure: ExportDocumentStructure.from(dictionary["estructura"])
        )
        guard format != .empty else { return nil }
        return format
    }

    static let empty = Self(
        font: nil, baseFontSize: nil, primaryColor: nil, marginMM: nil,
        titleAlignment: nil, headerMode: nil, showsCurricularData: nil,
        showsInstructions: nil, footerText: nil, showsPageNumber: nil, structure: nil
    )
}

struct ExportFormatTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let scope: String
    let isDefault: Bool
    let format: ExportFormat

    static func from(id: String, dictionary: [String: Any]) -> Self? {
        let rawScope = dictionary["alcance"] as? String ?? "todos"
        let validScopes = Set(["todos", "prueba", "guia", "planificacion", "clase", "material_didactico", "rubrica", "lista_cotejo"])
        let scope = validScopes.contains(rawScope) ? rawScope : "todos"
        let format = ExportFormat.from(dictionary["formato"]) ?? .empty
        let rawName = (dictionary["nombre"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(
            id: id,
            name: String((rawName.isEmpty ? defaultName(scope) : rawName).prefix(90)),
            scope: scope,
            isDefault: dictionary["predeterminada"] as? Bool == true,
            format: format
        )
    }

    private static func defaultName(_ scope: String) -> String {
        switch scope {
        case "prueba": return "Pruebas"
        case "guia": return "Guías"
        case "planificacion": return "Planificaciones"
        case "clase": return "Clases"
        case "material_didactico": return "Material didáctico"
        case "rubrica": return "Rúbricas"
        case "lista_cotejo": return "Listas de cotejo"
        default: return "Todos los documentos"
        }
    }
}

private enum ExportFormatRead {
    static func double(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let value = value as? NSNumber, value.doubleValue.isFinite { return value.doubleValue }
        if let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let result = Double(value), result.isFinite { return result }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        guard let value = double(value), value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value.rounded())
    }

    static func hex(_ value: Any?) -> String? {
        guard let value = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.range(of: "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", options: .regularExpression) != nil else {
            return nil
        }
        return value
    }
}

struct InfoColegio: Equatable {
    var nombre: String
    var logoBase64: String?
    var encabezadoHabilitado: Bool
    var encabezadoTextoIzq: String
    var encabezadoTextoDer: String
    var logoDerBase64: String?
    var formato: ExportFormat?
    var formatos: [ExportFormatTemplate]

    static let empty = InfoColegio(
        nombre: "",
        logoBase64: nil,
        encabezadoHabilitado: false,
        encabezadoTextoIzq: "",
        encabezadoTextoDer: "",
        logoDerBase64: nil,
        formato: nil,
        formatos: []
    )

    static func from(dictionary: [String: Any]?) -> InfoColegio {
        guard let dictionary else { return .empty }
        let embeddedTemplates = (dictionary["formatos"] as? [[String: Any]] ?? []).enumerated().compactMap { index, item in
            ExportFormatTemplate.from(id: item["id"] as? String ?? "formato_\(index)", dictionary: item)
        }
        return InfoColegio(
            nombre: dictionary["nombre"] as? String ?? "",
            logoBase64: dictionary["logoBase64"] as? String,
            encabezadoHabilitado: dictionary["encabezadoHabilitado"] as? Bool ?? false,
            encabezadoTextoIzq: dictionary["encabezadoTextoIzq"] as? String ?? "",
            encabezadoTextoDer: dictionary["encabezadoTextoDer"] as? String ?? "",
            logoDerBase64: dictionary["logoDerBase64"] as? String,
            formato: ExportFormat.from(dictionary["formato"]),
            formatos: embeddedTemplates
        )
    }

    var guideExportTemplates: [ExportFormatTemplate] {
        formatos.filter { $0.scope == "guia" || $0.scope == "todos" }
    }

    var guideExportFormat: ExportFormat? {
        let candidates = guideExportTemplates
        return candidates.first { $0.scope == "guia" && $0.isDefault }?.format
            ?? candidates.first { $0.scope == "guia" }?.format
            ?? candidates.first { $0.scope == "todos" && $0.isDefault }?.format
            ?? candidates.first { $0.scope == "todos" }?.format
            ?? formato
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
    var googleCalendarConnected: Bool
    var googleDriveConnected: Bool
    var colegioActivoId: String?

    static let empty = PreferenciasUsuario(
        asignaturasHabilitadas: [],
        bannerStyle: "rosa",
        onboardingCompletado: false,
        googleCalendarConnected: false,
        googleDriveConnected: false,
        colegioActivoId: nil
    )

    static func from(dictionary: [String: Any]?) -> PreferenciasUsuario {
        guard let dictionary else { return .empty }
        return PreferenciasUsuario(
            asignaturasHabilitadas: dictionary["asignaturasHabilitadas"] as? [String] ?? [],
            bannerStyle: dictionary["bannerStyle"] as? String ?? "rosa",
            onboardingCompletado: dictionary["onboardingCompletado"] as? Bool ?? false,
            googleCalendarConnected: dictionary["googleCalendarConnected"] as? Bool ?? false,
            googleDriveConnected: dictionary["googleDriveConnected"] as? Bool ?? false,
            colegioActivoId: (dictionary["colegioActivoId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "asignaturasHabilitadas": asignaturasHabilitadas,
            "bannerStyle": bannerStyle,
            "onboardingCompletado": onboardingCompletado,
            "googleCalendarConnected": googleCalendarConnected,
            "googleDriveConnected": googleDriveConnected
        ]
        if let colegioActivoId, !colegioActivoId.isEmpty {
            result["colegioActivoId"] = colegioActivoId
        }
        return result
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
    var studentCounts: [String: Int]
    var studentsByCourse: [String: [EstudiantePerfil]]
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
