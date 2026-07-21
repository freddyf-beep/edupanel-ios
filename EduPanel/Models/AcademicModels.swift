import Foundation
import FirebaseFirestore

enum AcademicCourseKind: String, Codable, Hashable, CaseIterable {
    case oficial
    case taller

    var label: String {
        switch self {
        case .oficial: return "Curso oficial"
        case .taller: return "Taller"
        }
    }
}

enum AcademicCourseStatus: String, Codable, Hashable {
    case active
    case archived
}

enum CurriculumAvailability: String, Codable, Hashable {
    case available
    case unavailable
}

struct CourseSubjectSelection: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    var availability: CurriculumAvailability?

    static func from(dictionary: [String: Any]) -> Self? {
        let id = dictionary["id"] as? String ?? ""
        let label = dictionary["label"] as? String ?? ""
        guard !id.isEmpty, !label.isEmpty else { return nil }
        return Self(
            id: id,
            label: label,
            availability: (dictionary["availability"] as? String).flatMap(CurriculumAvailability.init(rawValue:))
        )
    }

    var firestoreDictionary: [String: Any] {
        var value: [String: Any] = ["id": id, "label": label]
        if let availability { value["availability"] = availability.rawValue }
        return value
    }
}

struct CurriculumSubjectOption: Identifiable, Hashable {
    let id: String
    let label: String
    let level: String
    let availability: CurriculumAvailability
}

struct AcademicCourse: Identifiable, Hashable {
    var id: String { courseID }

    let courseID: String
    let dataKey: String
    var kind: AcademicCourseKind
    var name: String
    var level: String?
    var section: String?
    var workshopName: String?
    var subjects: [CourseSubjectSelection]
    var colorHex: String
    var status: AcademicCourseStatus
    var archivedAt: Date?
    var deleteEligibleAt: Date?

    static func from(id: String, dictionary: [String: Any]) -> Self? {
        let courseID = (dictionary["courseId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? id
        let dataKey = (dictionary["dataKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = (dictionary["nombre"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !courseID.isEmpty, !dataKey.isEmpty, !name.isEmpty else { return nil }
        let rawSubjects = dictionary["asignaturas"] as? [[String: Any]] ?? []
        return Self(
            courseID: courseID,
            dataKey: dataKey,
            kind: AcademicCourseKind(rawValue: dictionary["tipo"] as? String ?? "") ?? .taller,
            name: name,
            level: dictionary["nivel"] as? String,
            section: dictionary["seccion"] as? String,
            workshopName: dictionary["nombreTaller"] as? String,
            subjects: rawSubjects.compactMap(CourseSubjectSelection.from(dictionary:)),
            colorHex: dictionary["color"] as? String ?? "#EC4899",
            status: AcademicCourseStatus(rawValue: dictionary["estado"] as? String ?? "") ?? .active,
            archivedAt: Self.date(dictionary["archivedAt"]),
            deleteEligibleAt: Self.date(dictionary["deleteEligibleAt"])
        )
    }

    var firestoreDictionary: [String: Any] {
        var value: [String: Any] = [
            "courseId": courseID,
            "dataKey": dataKey,
            "tipo": kind.rawValue,
            "nombre": name,
            "asignaturas": subjects.map(\.firestoreDictionary),
            "color": colorHex,
            "estado": status.rawValue
        ]
        if let level { value["nivel"] = level }
        if let section { value["seccion"] = section }
        if let workshopName { value["nombreTaller"] = workshopName }
        if let archivedAt { value["archivedAt"] = Timestamp(date: archivedAt) }
        if let deleteEligibleAt { value["deleteEligibleAt"] = Timestamp(date: deleteEligibleAt) }
        return value
    }

    var isDeleteEligible: Bool {
        status == .archived && (deleteEligibleAt.map { $0 <= Date() } ?? false)
    }

    private static func date(_ raw: Any?) -> Date? {
        if let timestamp = raw as? Timestamp { return timestamp.dateValue() }
        if let date = raw as? Date { return date }
        if let text = raw as? String { return ISO8601DateFormatter().date(from: text) }
        return nil
    }
}

enum AcademicScheduleDay: String, Codable, Hashable, CaseIterable, Identifiable {
    case monday = "Lunes"
    case tuesday = "Martes"
    case wednesday = "Miércoles"
    case thursday = "Jueves"
    case friday = "Viernes"
    case saturday = "Sábado"

    var id: String { rawValue }
    var shortLabel: String { String(rawValue.prefix(3)) }
}

enum JourneyModuleKind: String, Codable, Hashable {
    case lectivo
    case recreo
    case almuerzo
    case noLectivo = "no_lectivo"
}

struct JourneyModule: Identifiable, Hashable {
    var id: String { moduleID }
    let moduleID: String
    var name: String
    var startTime: String
    var endTime: String
    var kind: JourneyModuleKind

    static func from(dictionary: [String: Any]) -> Self? {
        let moduleID = dictionary["moduleId"] as? String ?? ""
        let start = dictionary["horaInicio"] as? String ?? ""
        let end = dictionary["horaFin"] as? String ?? ""
        guard !moduleID.isEmpty, AcademicContract.isValidTimeRange(start: start, end: end) else { return nil }
        return Self(
            moduleID: moduleID,
            name: dictionary["nombre"] as? String ?? "Módulo",
            startTime: start,
            endTime: end,
            kind: JourneyModuleKind(rawValue: dictionary["tipo"] as? String ?? "") ?? .lectivo
        )
    }

    var firestoreDictionary: [String: Any] {
        [
            "moduleId": moduleID,
            "nombre": name,
            "horaInicio": startTime,
            "horaFin": endTime,
            "tipo": kind.rawValue
        ]
    }
}

struct JourneyConfig: Hashable {
    let version: Int
    var region: String
    var year: Int
    var activeDays: [AcademicScheduleDay]
    var modulesByDay: [AcademicScheduleDay: [JourneyModule]]

    static func from(dictionary: [String: Any]?) -> Self? {
        guard let dictionary, (dictionary["version"] as? Int ?? 0) == 2 else { return nil }
        let days = (dictionary["diasActivos"] as? [String] ?? []).compactMap(AcademicScheduleDay.init(rawValue:))
        let rawModules = dictionary["modulosPorDia"] as? [String: Any] ?? [:]
        var modules: [AcademicScheduleDay: [JourneyModule]] = [:]
        for day in AcademicScheduleDay.allCases {
            let values = rawModules[day.rawValue] as? [[String: Any]] ?? []
            modules[day] = values.compactMap(JourneyModule.from(dictionary:))
        }
        return Self(
            version: 2,
            region: dictionary["region"] as? String ?? "CL",
            year: dictionary["anio"] as? Int ?? Calendar.current.component(.year, from: Date()),
            activeDays: days,
            modulesByDay: modules
        )
    }

    var firestoreDictionary: [String: Any] {
        let modules = Dictionary(uniqueKeysWithValues: AcademicScheduleDay.allCases.map { day in
            (day.rawValue, (modulesByDay[day] ?? []).map(\.firestoreDictionary))
        })
        return [
            "version": 2,
            "region": region,
            "anio": year,
            "diasActivos": activeDays.map(\.rawValue),
            "modulosPorDia": modules
        ]
    }
}

enum SchedulePeriodStatus: String, Codable, Hashable {
    case draft
    case published
    case archived
}

struct SchedulePeriod: Identifiable, Hashable {
    var id: String { periodID }
    let periodID: String
    var name: String
    var startDateKey: String
    var endDateKey: String
    var status: SchedulePeriodStatus
    var timeZone: String
    var blocks: [ClaseHorario]

    static func from(id: String, dictionary: [String: Any]) -> Self? {
        let periodID = dictionary["periodId"] as? String ?? id
        let start = dictionary["inicio"] as? String ?? ""
        let end = dictionary["termino"] as? String ?? ""
        guard !periodID.isEmpty, !start.isEmpty, start <= end else { return nil }
        let rawBlocks = dictionary["bloques"] as? [[String: Any]] ?? []
        return Self(
            periodID: periodID,
            name: dictionary["nombre"] as? String ?? "Horario",
            startDateKey: start,
            endDateKey: end,
            status: SchedulePeriodStatus(rawValue: dictionary["estado"] as? String ?? "") ?? .draft,
            timeZone: dictionary["zonaHoraria"] as? String ?? AcademicContract.timeZoneIdentifier,
            blocks: rawBlocks.compactMap(ClaseHorario.from(dictionary:))
        )
    }

    var firestoreDictionary: [String: Any] {
        [
            "periodId": periodID,
            "nombre": name,
            "inicio": startDateKey,
            "termino": endDateKey,
            "estado": status.rawValue,
            "zonaHoraria": AcademicContract.timeZoneIdentifier,
            "bloques": blocks.map(\.firestoreDictionary)
        ]
    }
}

struct AcademicSelection: Hashable {
    let courseID: String
    let courseName: String
    let subjectID: String?
    let subjectName: String?
}

struct ScheduleMinutesSummary: Equatable {
    let instructional: Int
    let nonInstructional: Int
    var pedagogicalHours45: Double { Double(instructional) / 45 }
}

enum AcademicContractError: LocalizedError, Equatable {
    case invalidOfficialCourse
    case invalidWorkshop
    case immutableDataKey
    case invalidTimeRange
    case inactiveDay(String)
    case invalidJourneyOccurrence(String)
    case scheduleCollision(String)
    case overlappingPublishedPeriod

    var errorDescription: String? {
        switch self {
        case .invalidOfficialCourse: return "Selecciona un nivel y una sección válidos para el curso oficial."
        case .invalidWorkshop: return "Ingresa un nombre para el taller."
        case .immutableDataKey: return "La identidad estable del curso no se puede cambiar."
        case .invalidTimeRange: return "La hora de término debe ser posterior a la hora de inicio."
        case .inactiveDay(let day): return "\(day) no está activo en la jornada del colegio."
        case .invalidJourneyOccurrence(let day): return "El bloque de \(day) debe coincidir con un módulo lectivo o marcarse como excepcional."
        case .scheduleCollision(let detail): return "Choque de horario: \(detail)."
        case .overlappingPublishedPeriod: return "Ya existe un horario publicado para parte de ese periodo."
        }
    }
}

enum AcademicContract {
    static let timeZoneIdentifier = "America/Santiago"
    static let archiveGraceDays = 30
    static let sections = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
    static let officialLevels = [
        "Párvulos", "Sala Cuna", "Nivel Medio", "Nivel Transición",
        "1ro Básico", "2do Básico", "3ro Básico", "4to Básico",
        "5to Básico", "6to Básico", "7mo Básico", "8vo Básico",
        "1ro Medio", "2do Medio", "3ro Medio", "4to Medio"
    ]

    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func normalizedKey(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
        let pieces = folded.lowercased().split { !$0.isLetter && !$0.isNumber }
        return pieces.joined(separator: "_")
    }

    static func displayLevel(_ level: String) -> String {
        var result = level
        let replacements = ["1ro": "1°", "2do": "2°", "3ro": "3°", "4to": "4°", "5to": "5°", "6to": "6°", "7mo": "7°", "8vo": "8°"]
        for (source, target) in replacements where result.hasPrefix(source) {
            result.replaceSubrange(result.startIndex..<result.index(result.startIndex, offsetBy: source.count), with: target)
            break
        }
        return result
    }

    static func officialCourseName(level: String, section: String) throws -> String {
        let cleanSection = section.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard officialLevels.contains(level), sections.contains(cleanSection) else {
            throw AcademicContractError.invalidOfficialCourse
        }
        return "\(displayLevel(level)) \(cleanSection)"
    }

    static func subjects(for level: String) -> [CurriculumSubjectOption] {
        let labels: [String]
        if ["Párvulos", "Sala Cuna", "Nivel Medio", "Nivel Transición"].contains(level) {
            labels = ["Comunicación Integral", "Interacción y Comprensión del Entorno", "Desarrollo Personal y Social"]
        } else if level.hasSuffix("Básico") {
            let grade = Int(level.prefix { $0.isNumber }) ?? 1
            labels = grade <= 6 ? basicPrimarySubjects : basicSecondarySubjects
        } else if level.hasSuffix("Medio") {
            labels = secondarySubjects
        } else {
            labels = []
        }
        return labels.map { label in
            CurriculumSubjectOption(id: normalizedKey(label), label: label, level: level, availability: .unavailable)
        }
    }

    static func resolvePublishedPeriod(_ periods: [SchedulePeriod], for date: Date) -> SchedulePeriod? {
        let key = dateKey(for: date)
        return periods.first { $0.status == .published && $0.startDateKey <= key && $0.endDateKey >= key }
    }

    static func resolveSchedule(_ periods: [SchedulePeriod], legacy: [ClaseHorario], for date: Date) -> [ClaseHorario] {
        resolvePublishedPeriod(periods, for: date)?.blocks ?? legacy
    }

    /// Convierte el horario anterior en candidatos v2 sin mutar ni eliminar
    /// documentos legados. Excluir por `dataKey` vuelve la reparación idempotente.
    static func legacyCourseCandidates(
        schedule: [ClaseHorario],
        levelMapping: [String: String],
        courseKinds: [String: TipoCurricular],
        excludingDataKeys: Set<String>
    ) throws -> [AcademicCourse] {
        let grouped = Dictionary(grouping: schedule.filter(\.isAcademic), by: \.resumen)
        var knownKeys = excludingDataKeys
        var result: [AcademicCourse] = []

        for name in grouped.keys.sorted() {
            guard let blocks = grouped[name] else { continue }
            let dataKey = normalizedKey(name)
            guard !dataKey.isEmpty, knownKeys.insert(dataKey).inserted else { continue }
            let level = levelMapping[name]
            let section = name.split(separator: " ").last.map(String.init)?.uppercased()
            let canBeOfficial = courseKinds[name] != .taller && courseKinds[name] != .libre &&
                level.map(officialLevels.contains) == true && section.map(sections.contains) == true
            let subjects = Array(Set(blocks.compactMap(\.asignatura))).sorted().map {
                CourseSubjectSelection(id: normalizedKey($0), label: $0, availability: nil)
            }
            result.append(AcademicCourse(
                courseID: UUID().uuidString.lowercased(),
                dataKey: dataKey,
                kind: canBeOfficial ? .oficial : .taller,
                name: canBeOfficial ? try officialCourseName(level: level!, section: section!) : name,
                level: canBeOfficial ? level : nil,
                section: canBeOfficial ? section : nil,
                workshopName: canBeOfficial ? nil : name,
                subjects: canBeOfficial ? subjects : [],
                colorHex: blocks.first?.colorHex ?? (canBeOfficial ? "#EC4899" : "#8B5CF6"),
                status: .active,
                archivedAt: nil,
                deleteEligibleAt: nil
            ))
        }
        return result
    }

    static func periodsOverlap(_ lhs: SchedulePeriod, _ rhs: SchedulePeriod) -> Bool {
        lhs.startDateKey <= rhs.endDateKey && lhs.endDateKey >= rhs.startDateKey
    }

    static func validatePublishedPeriod(_ candidate: SchedulePeriod, among existing: [SchedulePeriod]) throws {
        guard candidate.status == .published else { return }
        if existing.contains(where: { $0.periodID != candidate.periodID && $0.status == .published && periodsOverlap($0, candidate) }) {
            throw AcademicContractError.overlappingPublishedPeriod
        }
    }

    static func isValidTimeRange(start: String, end: String) -> Bool {
        minutes(start) < minutes(end)
    }

    static func validateBatch(existing: [ClaseHorario], candidates: [ClaseHorario], journey: JourneyConfig?) throws {
        var accepted = existing
        for candidate in candidates {
            guard isValidTimeRange(start: candidate.horaInicio, end: candidate.horaFin) else {
                throw AcademicContractError.invalidTimeRange
            }
            if let day = AcademicScheduleDay(rawValue: candidate.dia), let journey {
                guard journey.activeDays.contains(day) else {
                    throw AcademicContractError.inactiveDay(candidate.dia)
                }
                let modules = journey.modulesByDay[day] ?? []
                if candidate.exceptional != true {
                    let match = modules.first {
                        $0.moduleID == candidate.moduleID && $0.kind == .lectivo &&
                        $0.startTime == candidate.horaInicio && $0.endTime == candidate.horaFin
                    }
                    guard match != nil else {
                        throw AcademicContractError.invalidJourneyOccurrence(candidate.dia)
                    }
                }
            }
            if let conflicting = accepted.first(where: { block in
                block.id != candidate.id && block.dia == candidate.dia &&
                minutes(candidate.horaInicio) < minutes(block.horaFin) &&
                minutes(candidate.horaFin) > minutes(block.horaInicio)
            }) {
                throw AcademicContractError.scheduleCollision(
                    "\(candidate.dia), \(conflicting.resumen) de \(conflicting.horaInicio) a \(conflicting.horaFin)"
                )
            }
            accepted.append(candidate)
        }
    }

    static func minutesSummary(_ blocks: [ClaseHorario]) -> ScheduleMinutesSummary {
        blocks.reduce(into: ScheduleMinutesSummaryAccumulator()) { result, block in
            let duration = max(0, minutes(block.horaFin) - minutes(block.horaInicio))
            if block.tipo.isFreeBlock { result.nonInstructional += duration }
            else { result.instructional += duration }
        }.summary
    }

    static func minutes(_ time: String) -> Int {
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return 0 }
        return components[0] * 60 + components[1]
    }

    private static let basicPrimarySubjects = [
        "Lenguaje", "Matemática", "Historia, Geografía y Ciencias Sociales", "Ciencias Naturales",
        "Artes Visuales", "Música", "Educación Física", "Orientación", "Tecnología", "Religión"
    ]
    private static let basicSecondarySubjects = Array(basicPrimarySubjects.prefix(4)) + ["Inglés"] + Array(basicPrimarySubjects.dropFirst(4))
    private static let secondarySubjects = [
        "Lenguaje", "Matemática", "Historia, Geografía y Ciencias Sociales", "Ciencias Naturales",
        "Inglés", "Artes", "Música", "Educación Física", "Orientación", "Tecnología", "Religión"
    ]
}

private struct ScheduleMinutesSummaryAccumulator {
    var instructional = 0
    var nonInstructional = 0
    var summary: ScheduleMinutesSummary {
        ScheduleMinutesSummary(instructional: instructional, nonInstructional: nonInstructional)
    }
}
