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
