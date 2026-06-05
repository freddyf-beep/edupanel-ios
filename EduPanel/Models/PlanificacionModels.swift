import Foundation

// MARK: - Planificacion por Curso
struct UnidadPlan: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var color: String
    var hours: Int
    var start: String
    var end: String
    var type: String // "tradicional", "invertida", "proyecto", "unidad0"
    var unidadCurricularId: String?

    var hasDates: Bool {
        !start.isEmpty && !end.isEmpty
    }
}

struct PlanificacionCurso: Codable, Hashable {
    var curso: String
    var asignatura: String
    var units: [UnidadPlan]
}

extension UnidadPlan {
    static func fromFirestore(_ dictionary: [String: Any], fallbackId: Int) -> UnidadPlan {
        UnidadPlan(
            id: PlanificacionValue.int(dictionary["id"]) ?? fallbackId,
            name: PlanificacionValue.string(dictionary["name"]) ?? "Unidad \(fallbackId)",
            color: PlanificacionValue.string(dictionary["color"]) ?? "#F03E6E",
            hours: PlanificacionValue.int(dictionary["hours"]) ?? 0,
            start: PlanificacionValue.string(dictionary["start"]) ?? "",
            end: PlanificacionValue.string(dictionary["end"]) ?? "",
            type: PlanificacionValue.string(dictionary["type"]) ?? "tradicional",
            unidadCurricularId: PlanificacionValue.string(dictionary["unidadCurricularId"])
        )
    }
}

extension PlanificacionCurso {
    static func fromFirestore(
        _ dictionary: [String: Any],
        fallbackCurso: String? = nil,
        fallbackAsignatura: String? = nil
    ) -> PlanificacionCurso? {
        let curso = PlanificacionValue.string(dictionary["curso"]) ?? fallbackCurso ?? ""
        let asignatura = PlanificacionValue.string(dictionary["asignatura"]) ?? fallbackAsignatura ?? ""
        guard !curso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let rawUnits = PlanificacionValue.dictionaryArray(dictionary["units"])
        var usedIds = Set<Int>()
        var nextId = 1
        let units = rawUnits.enumerated().map { index, rawUnit -> UnidadPlan in
            var unit = UnidadPlan.fromFirestore(rawUnit, fallbackId: index + 1)
            if unit.id <= 0 || usedIds.contains(unit.id) {
                while usedIds.contains(nextId) {
                    nextId += 1
                }
                unit.id = nextId
            }
            usedIds.insert(unit.id)
            nextId = max(nextId, unit.id + 1)
            return unit
        }

        return PlanificacionCurso(curso: curso, asignatura: asignatura, units: units)
    }
}

private enum PlanificacionValue {
    static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? CustomStringConvertible {
            let text = value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Int32 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        if let value = value as? Float { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    static func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        if let value = value as? [[String: Any]] {
            return value
        }
        if let value = value as? [Any] {
            return value.compactMap { $0 as? [String: Any] }
        }
        return []
    }
}

// MARK: - Ver Unidad (Pedagogía)
struct IndicadorEditado: Codable, Hashable, Identifiable {
    var id: String
    var texto: String
    var seleccionado: Bool
    var esPropio: Bool?
}

struct OAEditado: Codable, Hashable, Identifiable {
    var id: String // "OA1", "OA2"... o "PROP_1"
    var numero: Int?
    var tipo: String? // "oa" o "oat"
    var descripcion: String
    var seleccionado: Bool
    var indicadores: [IndicadorEditado]
    var esPropio: Bool?
    var tags: [String]?
}

struct ElementoCurricular: Codable, Hashable, Identifiable {
    var id: String
    var texto: String
    var seleccionado: Bool
    var esPropio: Bool?
}

struct EstrategiaEvaluacionUnidad: Codable, Hashable, Identifiable {
    var id: String
    var nombre: String
    var instrumento: String
    var ponderacion: Double?
}

struct VerUnidadGuardada: Codable, Hashable {
    var asignatura: String
    var curso: String
    var unidadId: String
    var descripcion: String
    var contextoDocente: String
    var objetivoDocente: String
    var horas: Int
    var clases: Int
    var oas: [OAEditado]
    var habilidades: [ElementoCurricular]
    var conocimientos: [ElementoCurricular]
    var actitudes: [ElementoCurricular]
    var conocimientosPrevios: String?
    var recursosMaterialesUnidad: [String]?
    var estrategiasEvaluacion: [EstrategiaEvaluacionUnidad]?
}

// MARK: - Cronograma
struct ClaseCronograma: Codable, Hashable, Identifiable {
    var id: Int { numero }
    var numero: Int
    var fecha: String
    var oaIds: [String]
    var duplicadaDe: Int?
}

struct CronogramaUnidadData: Codable, Hashable {
    var asignatura: String
    var curso: String
    var unidadId: String
    var totalClases: Int
    var clases: [ClaseCronograma]
}

// MARK: - Actividad de Clase (Detalle Diario)
struct ActividadClase: Codable, Hashable, Identifiable {
    var id: String // "{curso}_{unidadId}_clase{N}"
    var asignatura: String
    var curso: String
    var unidadId: String
    var numeroClase: Int
    var fecha: String
    var oaIds: [String]
    var objetivo: String
    var inicio: String
    var desarrollo: String
    var cierre: String
    var adecuacion: String
    var habilidades: [String]
    var actitudes: [String]
    var materiales: [String]
    var tics: [String]
    var estado: String // "no_planificada", "planificada", "realizada"
    var sincronizada: Bool
    var contextoProfesor: String?
    var indicadoresPorOa: [String: [String]]?
}
