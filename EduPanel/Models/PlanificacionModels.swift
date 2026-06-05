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

struct ArchivoAdjunto: Codable, Hashable, Identifiable {
    var id: String
    var nombre: String
    var url: String
    var storagePath: String? = nil
    var tipo: String? = nil
    var tamano: Double? = nil
    var subidoEn: String? = nil
    var provider: String? = nil
    var driveFileId: String? = nil
    var driveFolderId: String? = nil
    var webViewLink: String? = nil
    var previewUrl: String? = nil
    var syncedAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case nombre
        case url
        case storagePath
        case tipo
        case tamano = "tama\u{00F1}o"
        case subidoEn
        case provider
        case driveFileId
        case driveFolderId
        case webViewLink
        case previewUrl
        case syncedAt
    }

    init(
        id: String,
        nombre: String,
        url: String,
        storagePath: String? = nil,
        tipo: String? = nil,
        tamano: Double? = nil,
        subidoEn: String? = nil,
        provider: String? = nil,
        driveFileId: String? = nil,
        driveFolderId: String? = nil,
        webViewLink: String? = nil,
        previewUrl: String? = nil,
        syncedAt: String? = nil
    ) {
        self.id = id
        self.nombre = nombre
        self.url = url
        self.storagePath = storagePath
        self.tipo = tipo
        self.tamano = tamano
        self.subidoEn = subidoEn
        self.provider = provider
        self.driveFileId = driveFileId
        self.driveFolderId = driveFolderId
        self.webViewLink = webViewLink
        self.previewUrl = previewUrl
        self.syncedAt = syncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? container.decode(String.self, forKey: .nombre)) ?? "Archivo"
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        storagePath = try? container.decode(String.self, forKey: .storagePath)
        tipo = try? container.decode(String.self, forKey: .tipo)
        tamano = (try? container.decode(Double.self, forKey: .tamano)) ?? (try? Double(container.decode(Int.self, forKey: .tamano)))
        subidoEn = try? container.decode(String.self, forKey: .subidoEn)
        provider = try? container.decode(String.self, forKey: .provider)
        driveFileId = try? container.decode(String.self, forKey: .driveFileId)
        driveFolderId = try? container.decode(String.self, forKey: .driveFolderId)
        webViewLink = try? container.decode(String.self, forKey: .webViewLink)
        previewUrl = try? container.decode(String.self, forKey: .previewUrl)
        syncedAt = try? container.decode(String.self, forKey: .syncedAt)
    }
}

struct ActividadDocente: Codable, Hashable, Identifiable {
    var id: String
    var titulo: String
    var descripcion: String? = nil
    var tipo: String? = nil
    var duracion: Int? = nil
    var momento: String? = nil
    var recursos: [String]? = nil

    init(id: String, titulo: String, descripcion: String? = nil, tipo: String? = nil, duracion: Int? = nil, momento: String? = nil, recursos: [String]? = nil) {
        self.id = id
        self.titulo = titulo
        self.descripcion = descripcion
        self.tipo = tipo
        self.duracion = duracion
        self.momento = momento
        self.recursos = recursos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        titulo = (try? container.decode(String.self, forKey: .titulo)) ?? "Actividad"
        descripcion = try? container.decode(String.self, forKey: .descripcion)
        tipo = try? container.decode(String.self, forKey: .tipo)
        duracion = try? container.decode(Int.self, forKey: .duracion)
        momento = try? container.decode(String.self, forKey: .momento)
        recursos = try? container.decode([String].self, forKey: .recursos)
    }
}

struct AnalisisBloom: Codable, Hashable, Identifiable {
    var id: String
    var nivel: String? = nil
    var evidencia: String? = nil
    var sugerencia: String? = nil

    init(id: String, nivel: String? = nil, evidencia: String? = nil, sugerencia: String? = nil) {
        self.id = id
        self.nivel = nivel
        self.evidencia = evidencia
        self.sugerencia = sugerencia
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nivel = try? container.decode(String.self, forKey: .nivel)
        evidencia = try? container.decode(String.self, forKey: .evidencia)
        sugerencia = try? container.decode(String.self, forKey: .sugerencia)
    }
}

struct ObjetivoMultinivel: Codable, Hashable {
    var basico: String? = nil
    var intermedio: String? = nil
    var avanzado: String? = nil
}

struct IndicadorEvaluacion: Codable, Hashable, Identifiable {
    var id: String
    var texto: String
    var oaId: String? = nil
    var seleccionado: Bool? = nil

    init(id: String, texto: String, oaId: String? = nil, seleccionado: Bool? = nil) {
        self.id = id
        self.texto = texto
        self.oaId = oaId
        self.seleccionado = seleccionado
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        texto = (try? container.decode(String.self, forKey: .texto)) ?? ""
        oaId = try? container.decode(String.self, forKey: .oaId)
        seleccionado = try? container.decode(Bool.self, forKey: .seleccionado)
    }
}

struct ActividadEvaluacion: Codable, Hashable {
    var tipo: String? = nil
    var descripcion: String? = nil
    var instrumento: String? = nil
}

struct DesarrolloFormal: Codable, Hashable {
    var inicio: String? = nil
    var desarrollo: String? = nil
    var cierre: String? = nil
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
    var recursosMaterialesUnidadArchivos: [ArchivoAdjunto]? = nil
    var estrategiasEvaluacion: [EstrategiaEvaluacionUnidad]?
    var actividades: [ActividadDocente]? = nil
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
    var archivos: [ArchivoAdjunto]? = nil
    var estado: String // "no_planificada", "planificada", "realizada"
    var sincronizada: Bool
    var contextoProfesor: String?
    var analisisBloom: [AnalisisBloom]? = nil
    var objetivoMultinivel: ObjetivoMultinivel? = nil
    var indicadoresEvaluacion: [IndicadorEvaluacion]? = nil
    var actividadEvaluacion: ActividadEvaluacion? = nil
    var desarrolloFormal: DesarrolloFormal? = nil
    var indicadoresPorOa: [String: [String]]?
}
