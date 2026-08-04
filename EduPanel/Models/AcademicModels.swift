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
    /// Claves históricas usadas por nóminas, horarios y planificaciones
    /// anteriores a `courseID`. El contrato web las conserva para resolver
    /// cambios de nombre sin volver a depender de la etiqueta visible.
    var aliasKeys: [String] = []
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
        let name = ((dictionary["nombre"] as? String) ?? (dictionary["name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !courseID.isEmpty, !name.isEmpty else { return nil }
        let storedDataKey = (dictionary["dataKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dataKey = storedDataKey.isEmpty ? AcademicContract.normalizedKey(name) : storedDataKey
        var seenAliasKeys = Set<String>()
        let aliasKeys = (dictionary["aliasKeys"] as? [String] ?? []).compactMap { rawValue -> String? in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != dataKey, seenAliasKeys.insert(value).inserted else { return nil }
            return value
        }
        let rawSubjects = dictionary["asignaturas"] as? [[String: Any]] ?? []
        var subjects = rawSubjects.compactMap(CourseSubjectSelection.from(dictionary:))
        if subjects.isEmpty, let legacySubjects = dictionary["asignaturas"] as? [String] {
            subjects = legacySubjects.compactMap { rawValue in
                let label = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { return nil }
                return CourseSubjectSelection(
                    id: AcademicContract.normalizedKey(label),
                    label: label,
                    availability: nil
                )
            }
        }
        let rawStatus = dictionary["estado"] as? String ?? ""
        let rawKind = (dictionary["tipo"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let kind: AcademicCourseKind = rawKind == "libre"
            ? .taller
            : (AcademicCourseKind(rawValue: rawKind) ?? .oficial)
        let storedWorkshopName = (dictionary["nombreTaller"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(
            courseID: courseID,
            dataKey: dataKey,
            aliasKeys: aliasKeys,
            // Algunas cuentas anteriores guardaban talleres como `libre`.
            // Se leen como taller, pero al volver a guardar se escribe el
            // contrato canónico `taller`.
            kind: kind,
            name: name,
            level: dictionary["nivel"] as? String,
            section: dictionary["seccion"] as? String,
            workshopName: kind == .taller && (storedWorkshopName ?? "").isEmpty ? name : storedWorkshopName,
            subjects: subjects,
            colorHex: dictionary["color"] as? String ?? "#EC4899",
            status: rawStatus == "archived" || rawStatus == "archivado" ? .archived : .active,
            archivedAt: Self.date(dictionary["archivedAt"]),
            deleteEligibleAt: Self.date(dictionary["deleteEligibleAt"])
        )
    }

    var firestoreDictionary: [String: Any] {
        var value: [String: Any] = [
            "courseId": courseID,
            "dataKey": dataKey,
            // Se escribe incluso vacío porque `saveCourse` usa merge. Omitirlo
            // impediría retirar aliases agregados por una mutación revertida.
            "aliasKeys": aliasKeys,
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

enum AcademicCourseResolution: Equatable {
    case resolved(AcademicCourse)
    case notFound
    case ambiguous(courseIDs: [String])

    var course: AcademicCourse? {
        guard case .resolved(let course) = self else { return nil }
        return course
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

/// Tipos de hitos civiles que conviven con el horario semanal. Mantenerlos
/// separados evita convertir una recurrencia en clases persistidas para todo
/// el año académico.
enum AcademicCalendarEventKind: String, Hashable, CaseIterable {
    case vacation = "vacaciones"
    case holiday = "feriado"
    case suspension = "suspension"
    case scheduleException = "excepcion_horario"
    case evaluation = "evaluacion"
    case activity = "actividad"
    case deadline = "fecha_limite"
    case schoolEvent = "evento_colegio"
    case academicSpaceEvent = "evento_espacio_academico"
    case reminder = "recordatorio"

    var suppressesRecurringSchedule: Bool {
        switch self {
        case .vacation, .holiday, .suspension:
            return true
        default:
            return false
        }
    }
}

/// Evento del calendario académico independiente del horario recurrente.
///
/// `courseID` puede identificar tanto un curso oficial como un taller. Si es
/// `nil`, el evento se aplica a todo el colegio. Una excepción solo reemplaza
/// el horario cuando declara `replacementBlocks`; de lo contrario es un hito
/// informativo y no inventa clases.
struct AcademicCalendarEvent: Identifiable, Hashable {
    let id: String
    var title: String
    var kind: AcademicCalendarEventKind
    var startDateKey: String
    var endDateKey: String
    var courseID: String? = nil
    var unitID: String? = nil
    var classID: String? = nil
    var replacementBlocks: [ClaseHorario]? = nil

    func contains(_ date: Date) -> Bool {
        let key = AcademicContract.dateKey(for: date)
        return startDateKey <= key && endDateKey >= key
    }
}

enum AcademicCalendarResolver {
    /// Proyecta el horario efectivo para una fecha sin crear ni persistir
    /// instancias de clase. Feriados, vacaciones y suspensiones eliminan la
    /// recurrencia del ámbito afectado; las excepciones pueden sustituirla.
    static func effectiveSchedule(
        periods: [SchedulePeriod],
        legacy: [ClaseHorario],
        events: [AcademicCalendarEvent],
        for date: Date
    ) -> [ClaseHorario] {
        var result = AcademicContract.resolveSchedule(periods, legacy: legacy, for: date)
        let eventsForDate = events.filter { $0.contains(date) }

        for event in eventsForDate where event.kind == .scheduleException {
            guard let replacement = event.replacementBlocks else { continue }
            if let courseID = event.courseID {
                result.removeAll { $0.courseID == courseID }
                result.append(contentsOf: replacement)
            } else {
                result = replacement
            }
        }

        for event in eventsForDate where event.kind.suppressesRecurringSchedule {
            if let courseID = event.courseID {
                result.removeAll { $0.courseID == courseID }
            } else {
                return []
            }
        }

        return result.sorted {
            if $0.dia != $1.dia { return $0.dia < $1.dia }
            if $0.horaInicio != $1.horaInicio { return $0.horaInicio < $1.horaInicio }
            return $0.id < $1.id
        }
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

    /// Resuelve una referencia solamente dentro del catálogo ya cargado.
    ///
    /// Una identidad estable o un nombre vigente siempre gana frente a un
    /// alias histórico. Si dos cursos comparten el mismo alias, se rechaza la
    /// resolución para no leer o escribir datos en un curso arbitrario según
    /// el orden de Firestore.
    static func resolveCourse(
        in catalog: [AcademicCourse],
        id: String? = nil,
        named reference: String? = nil
    ) -> AcademicCourseResolution {
        let cleanID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanID.isEmpty {
            let matches = catalog.filter { $0.courseID == cleanID }
            if let resolution = uniqueCourseResolution(matches) { return resolution }
        }

        let cleanReference = reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanReference.isEmpty else { return .notFound }

        let idMatches = catalog.filter { $0.courseID == cleanReference }
        if let resolution = uniqueCourseResolution(idMatches) { return resolution }

        let exactNameMatches = catalog.filter {
            $0.name.localizedCaseInsensitiveCompare(cleanReference) == .orderedSame
        }
        if let resolution = uniqueCourseResolution(exactNameMatches) { return resolution }

        let requestedKey = normalizedKey(cleanReference)
        let dataKeyMatches = catalog.filter {
            $0.dataKey == cleanReference || (!requestedKey.isEmpty && $0.dataKey == requestedKey)
        }
        if let resolution = uniqueCourseResolution(dataKeyMatches) { return resolution }

        guard !requestedKey.isEmpty else { return .notFound }
        let aliasMatches = catalog.filter { course in
            course.aliasKeys.contains { alias in
                alias == cleanReference || normalizedKey(alias) == requestedKey
            }
        }
        return uniqueCourseResolution(aliasMatches) ?? .notFound
    }

    private static func uniqueCourseResolution(_ matches: [AcademicCourse]) -> AcademicCourseResolution? {
        guard !matches.isEmpty else { return nil }
        let unique = Dictionary(grouping: matches, by: \.courseID)
            .compactMap { $0.value.first }
        guard unique.count == 1, let course = unique.first else {
            return .ambiguous(courseIDs: unique.map(\.courseID).sorted())
        }
        return .resolved(course)
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
        let publishedPeriods = periods.filter { $0.status == .published }
        guard !publishedPeriods.isEmpty else { return legacy }
        return resolvePublishedPeriod(publishedPeriods, for: date)?.blocks ?? []
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
            let canonicalName: String
            if canBeOfficial, let level, let section {
                canonicalName = try officialCourseName(level: level, section: section)
            } else {
                canonicalName = name
            }
            result.append(AcademicCourse(
                courseID: UUID().uuidString.lowercased(),
                dataKey: dataKey,
                kind: canBeOfficial ? .oficial : .taller,
                name: canonicalName,
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
