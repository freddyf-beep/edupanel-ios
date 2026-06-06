import Foundation

// MARK: - Planificacion por Curso
struct UnidadPlan: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var color: String
    var hours: Int
    var start: String
    var end: String
    var type: String
    var unidadCurricularId: String?

    var hasDates: Bool {
        !start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !end.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct PlanificacionCurso: Codable, Hashable {
    var curso: String
    var asignatura: String
    var units: [UnidadPlan]

    var routeKey: String {
        "\(asignatura)::\(curso)"
    }
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

enum PlanificacionValue {
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
        if let value = value as? [[String: Any]] { return value }
        if let value = value as? [Any] { return value.compactMap { $0 as? [String: Any] } }
        return []
    }
}

private struct FlexibleTextObject: Decodable {
    var id: String?
    var texto: String?
    var text: String?
    var nombre: String?
    var name: String?
    var titulo: String?
    var title: String?
    var descripcion: String?
    var description: String?
    var label: String?
    var value: String?
    var codigo: String?
    var code: String?

    var textValue: String? {
        [id, texto, text, nombre, name, titulo, title, descripcion, description, label, value, codigo, code]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct FlexibleStringList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let values = try? container.decode([String].self) {
            self.values = Self.clean(values)
            return
        }

        if let values = try? container.decode([Int].self) {
            self.values = values.map(String.init)
            return
        }

        if let values = try? container.decode([Double].self) {
            self.values = values.map { value in
                value.rounded() == value ? String(Int(value)) : String(value)
            }
            return
        }

        if let values = try? container.decode([Bool].self) {
            self.values = values.map { $0 ? "true" : "false" }
            return
        }

        if let values = try? container.decode([FlexibleTextObject].self) {
            self.values = Self.clean(values.compactMap(\.textValue))
            return
        }

        if let value = try? container.decode(String.self) {
            self.values = Self.clean([value])
            return
        }

        if let value = try? container.decode(Int.self) {
            self.values = [String(value)]
            return
        }

        if let value = try? container.decode(Double.self) {
            self.values = [value.rounded() == value ? String(Int(value)) : String(value)]
            return
        }

        if let value = try? container.decode(Bool.self) {
            self.values = [value ? "true" : "false"]
            return
        }

        self.values = []
    }

    private static func clean(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension KeyedDecodingContainer {
    func decodeString(_ key: Key, default defaultValue: String = "") -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return defaultValue
    }

    func decodeInt(_ key: Key, default defaultValue: Int = 0) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key),
           let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return defaultValue
    }

    func decodeDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeBool(_ key: Key, default defaultValue: Bool = false) -> Bool {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "si", "sí", "yes"].contains(normalized) { return true }
            if ["false", "0", "no"].contains(normalized) { return false }
        }
        return defaultValue
    }

    func decodeArray<T: Decodable>(_ type: [T].Type, forKey key: Key, default defaultValue: [T] = []) -> [T] {
        (try? decode(type, forKey: key)) ?? defaultValue
    }

    func decodeStringArray(_ key: Key, default defaultValue: [String] = []) -> [String] {
        if let value = try? decode(FlexibleStringList.self, forKey: key) { return value.values }
        return defaultValue
    }

    func decodeStringArrayMap(_ key: Key) -> [String: [String]]? {
        if let value = try? decode([String: FlexibleStringList].self, forKey: key) {
            return value.mapValues(\.values)
        }
        if let value = try? decode([String: String].self, forKey: key) {
            return value.reduce(into: [String: [String]]()) { result, element in
                let text = element.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result[element.key] = [text]
                }
            }
        }
        return nil
    }
}

private func firstNonEmpty(_ values: String...) -> String {
    values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? ""
}

private func firstNonEmptyOptional(_ values: String?...) -> String? {
    values
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
}

private func firstNonEmptyList(_ values: [String]...) -> [String] {
    values.first { !$0.isEmpty } ?? []
}

// MARK: - Ver Unidad
struct IndicadorEditado: Codable, Hashable, Identifiable {
    var id: String
    var texto: String
    var seleccionado: Bool
    var esPropio: Bool?

    enum CodingKeys: String, CodingKey {
        case id, texto, seleccionado, esPropio
    }

    init(id: String, texto: String, seleccionado: Bool, esPropio: Bool? = nil) {
        self.id = id
        self.texto = texto
        self.seleccionado = seleccionado
        self.esPropio = esPropio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id, default: UUID().uuidString)
        texto = container.decodeString(.texto)
        seleccionado = container.decodeBool(.seleccionado)
        esPropio = try? container.decode(Bool.self, forKey: .esPropio)
    }
}

struct OAEditado: Codable, Hashable, Identifiable {
    var id: String
    var numero: Int?
    var tipo: String?
    var descripcion: String
    var seleccionado: Bool
    var indicadores: [IndicadorEditado]
    var esPropio: Bool?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, numero, tipo, descripcion, seleccionado, indicadores, esPropio, tags
    }

    init(
        id: String,
        numero: Int? = nil,
        tipo: String? = nil,
        descripcion: String,
        seleccionado: Bool,
        indicadores: [IndicadorEditado],
        esPropio: Bool? = nil,
        tags: [String]? = nil
    ) {
        self.id = id
        self.numero = numero
        self.tipo = tipo
        self.descripcion = descripcion
        self.seleccionado = seleccionado
        self.indicadores = indicadores
        self.esPropio = esPropio
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id, default: UUID().uuidString)
        let decodedNumber = container.decodeInt(.numero, default: 0)
        numero = decodedNumber == 0 ? nil : decodedNumber
        tipo = try? container.decode(String.self, forKey: .tipo)
        descripcion = container.decodeString(.descripcion)
        seleccionado = container.decodeBool(.seleccionado)
        indicadores = container.decodeArray([IndicadorEditado].self, forKey: .indicadores)
        esPropio = try? container.decode(Bool.self, forKey: .esPropio)
        tags = try? container.decode([String].self, forKey: .tags)
    }
}

struct ElementoCurricular: Codable, Hashable, Identifiable {
    var id: String
    var texto: String
    var seleccionado: Bool
    var esPropio: Bool?

    enum CodingKeys: String, CodingKey {
        case id, texto, seleccionado, esPropio
    }

    init(id: String, texto: String, seleccionado: Bool, esPropio: Bool? = nil) {
        self.id = id
        self.texto = texto
        self.seleccionado = seleccionado
        self.esPropio = esPropio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id, default: UUID().uuidString)
        texto = container.decodeString(.texto)
        seleccionado = container.decodeBool(.seleccionado)
        esPropio = try? container.decode(Bool.self, forKey: .esPropio)
    }
}

struct EstrategiaEvaluacionUnidad: Codable, Hashable, Identifiable {
    var id: String
    var nombre: String
    var instrumento: String
    var ponderacion: Double?

    enum CodingKeys: String, CodingKey {
        case id, nombre, instrumento, ponderacion
    }

    init(id: String, nombre: String, instrumento: String, ponderacion: Double? = nil) {
        self.id = id
        self.nombre = nombre
        self.instrumento = instrumento
        self.ponderacion = ponderacion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id, default: UUID().uuidString)
        nombre = container.decodeString(.nombre, default: "Estrategia")
        instrumento = container.decodeString(.instrumento)
        ponderacion = container.decodeDouble(.ponderacion)
    }
}

struct ArchivoAdjunto: Codable, Hashable, Identifiable {
    var id: String
    var nombre: String
    var url: String
    var storagePath: String?
    var tipo: String?
    var tamano: Double?
    var subidoEn: String?
    var provider: String?
    var driveFileId: String?
    var driveFolderId: String?
    var webViewLink: String?
    var previewUrl: String?
    var syncedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, nombre, url, storagePath, tipo, subidoEn, provider, driveFileId, driveFolderId, webViewLink, previewUrl, syncedAt
        case tamano = "tama\u{00F1}o"
        case tamanoASCII = "tamano"
        case tamanoBroken = "tama\u{00C3}\u{00B1}o"
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
        id = container.decodeString(.id, default: UUID().uuidString)
        nombre = container.decodeString(.nombre, default: "Archivo")
        url = container.decodeString(.url)
        storagePath = try? container.decode(String.self, forKey: .storagePath)
        tipo = try? container.decode(String.self, forKey: .tipo)
        tamano = container.decodeDouble(.tamano) ?? container.decodeDouble(.tamanoASCII) ?? container.decodeDouble(.tamanoBroken)
        let decodedSubidoEn = container.decodeString(.subidoEn)
        subidoEn = decodedSubidoEn.isEmpty ? nil : decodedSubidoEn
        provider = try? container.decode(String.self, forKey: .provider)
        driveFileId = try? container.decode(String.self, forKey: .driveFileId)
        driveFolderId = try? container.decode(String.self, forKey: .driveFolderId)
        webViewLink = try? container.decode(String.self, forKey: .webViewLink)
        previewUrl = try? container.decode(String.self, forKey: .previewUrl)
        let decodedSyncedAt = container.decodeString(.syncedAt)
        syncedAt = decodedSyncedAt.isEmpty ? nil : decodedSyncedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nombre, forKey: .nombre)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(storagePath, forKey: .storagePath)
        try container.encodeIfPresent(tipo, forKey: .tipo)
        try container.encodeIfPresent(tamano, forKey: .tamano)
        try container.encodeIfPresent(subidoEn, forKey: .subidoEn)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(driveFileId, forKey: .driveFileId)
        try container.encodeIfPresent(driveFolderId, forKey: .driveFolderId)
        try container.encodeIfPresent(webViewLink, forKey: .webViewLink)
        try container.encodeIfPresent(previewUrl, forKey: .previewUrl)
        try container.encodeIfPresent(syncedAt, forKey: .syncedAt)
    }
}

struct ActividadDocente: Codable, Hashable, Identifiable {
    var id: String
    var titulo: String
    var nombre: String?
    var descripcion: String?
    var tipo: String?
    var duracion: Int?
    var duracionTexto: String?
    var fecha: String?
    var estado: String?
    var momento: String?
    var recursos: [String]?

    enum CodingKeys: String, CodingKey {
        case id, titulo, nombre, descripcion, tipo, duracion, fecha, estado, momento, recursos
    }

    init(id: String, titulo: String, nombre: String? = nil, descripcion: String? = nil, tipo: String? = nil, duracion: Int? = nil, duracionTexto: String? = nil, fecha: String? = nil, estado: String? = nil, momento: String? = nil, recursos: [String]? = nil) {
        self.id = id
        self.titulo = titulo
        self.nombre = nombre
        self.descripcion = descripcion
        self.tipo = tipo
        self.duracion = duracion
        self.duracionTexto = duracionTexto
        self.fecha = fecha
        self.estado = estado
        self.momento = momento
        self.recursos = recursos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id, default: UUID().uuidString)
        nombre = try? container.decode(String.self, forKey: .nombre)
        titulo = container.decodeString(.titulo, default: nombre ?? "Actividad")
        descripcion = try? container.decode(String.self, forKey: .descripcion)
        tipo = try? container.decode(String.self, forKey: .tipo)
        duracion = container.decodeInt(.duracion, default: 0)
        if duracion == 0 { duracion = nil }
        duracionTexto = try? container.decode(String.self, forKey: .duracion)
        fecha = try? container.decode(String.self, forKey: .fecha)
        estado = try? container.decode(String.self, forKey: .estado)
        momento = try? container.decode(String.self, forKey: .momento)
        let decodedResources = container.decodeStringArray(.recursos)
        recursos = decodedResources.isEmpty ? nil : decodedResources
    }
}

struct AnalisisBloom: Codable, Hashable, Identifiable {
    var id: String
    var oaId: String?
    var categoria: String?
    var nivel: String?
    var justificacion: String?
    var verbosSugeridos: [String]?

    enum CodingKeys: String, CodingKey {
        case id, oaId, categoria, nivel, justificacion, verbosSugeridos
    }

    init(id: String, oaId: String? = nil, categoria: String? = nil, nivel: String? = nil, justificacion: String? = nil, verbosSugeridos: [String]? = nil) {
        self.id = id
        self.oaId = oaId
        self.categoria = categoria
        self.nivel = nivel
        self.justificacion = justificacion
        self.verbosSugeridos = verbosSugeridos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        oaId = try? container.decode(String.self, forKey: .oaId)
        id = container.decodeString(.id, default: oaId ?? UUID().uuidString)
        categoria = try? container.decode(String.self, forKey: .categoria)
        nivel = try? container.decode(String.self, forKey: .nivel)
        justificacion = try? container.decode(String.self, forKey: .justificacion)
        let decodedVerbTags = container.decodeStringArray(.verbosSugeridos)
        verbosSugeridos = decodedVerbTags.isEmpty ? nil : decodedVerbTags
    }
}

struct ObjetivoMultinivel: Codable, Hashable {
    var basico: String?
    var intermedio: String?
    var avanzado: String?
    var recomendado: String?

    var textoRecomendado: String? {
        switch recomendado?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "basico", "básico":
            return basico
        case "intermedio":
            return intermedio
        case "avanzado":
            return avanzado
        default:
            return firstNonEmptyOptional(intermedio, basico, avanzado)
        }
    }
}

struct IndicadorEvaluacion: Codable, Hashable, Identifiable {
    var id: String
    var texto: String
    var oaId: String?
    var seleccionado: Bool?
    var dimension: String?
    var nivelBloom: String?

    enum CodingKeys: String, CodingKey {
        case id, texto, oaId, seleccionado, dimension, nivelBloom
        case descripcion, nombre, selected
    }

    init(id: String, texto: String, oaId: String? = nil, seleccionado: Bool? = nil, dimension: String? = nil, nivelBloom: String? = nil) {
        self.id = id
        self.texto = texto
        self.oaId = oaId
        self.seleccionado = seleccionado
        self.dimension = dimension
        self.nivelBloom = nivelBloom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id, default: UUID().uuidString)
        texto = firstNonEmpty(
            container.decodeString(.texto),
            container.decodeString(.descripcion),
            container.decodeString(.nombre)
        )
        oaId = try? container.decode(String.self, forKey: .oaId)
        seleccionado = (try? container.decode(Bool.self, forKey: .seleccionado)) ?? (try? container.decode(Bool.self, forKey: .selected))
        dimension = try? container.decode(String.self, forKey: .dimension)
        nivelBloom = try? container.decode(String.self, forKey: .nivelBloom)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(texto, forKey: .texto)
        try container.encodeIfPresent(oaId, forKey: .oaId)
        try container.encodeIfPresent(seleccionado, forKey: .seleccionado)
        try container.encodeIfPresent(dimension, forKey: .dimension)
        try container.encodeIfPresent(nivelBloom, forKey: .nivelBloom)
    }
}

struct ActividadEvaluacion: Codable, Hashable {
    var tipo: String?
    var descripcion: String?
    var instrumento: String?
    var criterios: [String]?
    var alineacionMBE: [String]?

    enum CodingKeys: String, CodingKey {
        case tipo, descripcion, instrumento, criterios, alineacionMBE
        case description, alineacionMbe, alineacion
    }

    init(tipo: String? = nil, descripcion: String? = nil, instrumento: String? = nil, criterios: [String]? = nil, alineacionMBE: [String]? = nil) {
        self.tipo = tipo
        self.descripcion = descripcion
        self.instrumento = instrumento
        self.criterios = criterios
        self.alineacionMBE = alineacionMBE
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tipo = firstNonEmptyOptional(try? container.decode(String.self, forKey: .tipo))
        descripcion = firstNonEmptyOptional(
            try? container.decode(String.self, forKey: .descripcion),
            try? container.decode(String.self, forKey: .description)
        )
        instrumento = firstNonEmptyOptional(try? container.decode(String.self, forKey: .instrumento))

        let decodedCriteria = container.decodeStringArray(.criterios)
        criterios = decodedCriteria.isEmpty ? nil : decodedCriteria

        let decodedAlignment = firstNonEmptyList(
            container.decodeStringArray(.alineacionMBE),
            container.decodeStringArray(.alineacionMbe),
            container.decodeStringArray(.alineacion)
        )
        alineacionMBE = decodedAlignment.isEmpty ? nil : decodedAlignment
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(tipo, forKey: .tipo)
        try container.encodeIfPresent(descripcion, forKey: .descripcion)
        try container.encodeIfPresent(instrumento, forKey: .instrumento)
        try container.encodeIfPresent(criterios, forKey: .criterios)
        try container.encodeIfPresent(alineacionMBE, forKey: .alineacionMBE)
    }
}

struct DesarrolloFormal: Codable, Hashable {
    var inicio: String?
    var desarrollo: String?
    var cierre: String?
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
    var recursosMaterialesUnidadArchivos: [ArchivoAdjunto]?
    var estrategiasEvaluacion: [EstrategiaEvaluacionUnidad]?
    var actividades: [ActividadDocente]?

    enum CodingKeys: String, CodingKey {
        case asignatura, curso, unidadId, descripcion, contextoDocente, objetivoDocente, horas, clases, oas, habilidades, conocimientos, actitudes, conocimientosPrevios, recursosMaterialesUnidad, recursosMaterialesUnidadArchivos, estrategiasEvaluacion, actividades
    }

    init(
        asignatura: String,
        curso: String,
        unidadId: String,
        descripcion: String,
        contextoDocente: String,
        objetivoDocente: String,
        horas: Int,
        clases: Int,
        oas: [OAEditado],
        habilidades: [ElementoCurricular],
        conocimientos: [ElementoCurricular],
        actitudes: [ElementoCurricular],
        conocimientosPrevios: String? = nil,
        recursosMaterialesUnidad: [String]? = nil,
        recursosMaterialesUnidadArchivos: [ArchivoAdjunto]? = nil,
        estrategiasEvaluacion: [EstrategiaEvaluacionUnidad]? = nil,
        actividades: [ActividadDocente]? = nil
    ) {
        self.asignatura = asignatura
        self.curso = curso
        self.unidadId = unidadId
        self.descripcion = descripcion
        self.contextoDocente = contextoDocente
        self.objetivoDocente = objetivoDocente
        self.horas = horas
        self.clases = clases
        self.oas = oas
        self.habilidades = habilidades
        self.conocimientos = conocimientos
        self.actitudes = actitudes
        self.conocimientosPrevios = conocimientosPrevios
        self.recursosMaterialesUnidad = recursosMaterialesUnidad
        self.recursosMaterialesUnidadArchivos = recursosMaterialesUnidadArchivos
        self.estrategiasEvaluacion = estrategiasEvaluacion
        self.actividades = actividades
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asignatura = container.decodeString(.asignatura)
        curso = container.decodeString(.curso)
        unidadId = container.decodeString(.unidadId)
        descripcion = container.decodeString(.descripcion)
        contextoDocente = container.decodeString(.contextoDocente)
        objetivoDocente = container.decodeString(.objetivoDocente)
        horas = container.decodeInt(.horas)
        clases = container.decodeInt(.clases)
        oas = container.decodeArray([OAEditado].self, forKey: .oas)
        habilidades = container.decodeArray([ElementoCurricular].self, forKey: .habilidades)
        conocimientos = container.decodeArray([ElementoCurricular].self, forKey: .conocimientos)
        actitudes = container.decodeArray([ElementoCurricular].self, forKey: .actitudes)
        conocimientosPrevios = try? container.decode(String.self, forKey: .conocimientosPrevios)
        recursosMaterialesUnidad = try? container.decode([String].self, forKey: .recursosMaterialesUnidad)
        recursosMaterialesUnidadArchivos = try? container.decode([ArchivoAdjunto].self, forKey: .recursosMaterialesUnidadArchivos)
        estrategiasEvaluacion = try? container.decode([EstrategiaEvaluacionUnidad].self, forKey: .estrategiasEvaluacion)
        actividades = try? container.decode([ActividadDocente].self, forKey: .actividades)
    }
}

// MARK: - Cronograma
struct ClaseCronograma: Codable, Hashable, Identifiable {
    var id: Int { numero }
    var numero: Int
    var fecha: String
    var oaIds: [String]
    var duplicadaDe: Int?

    enum CodingKeys: String, CodingKey {
        case numero, fecha, oaIds, duplicadaDe
    }

    init(numero: Int, fecha: String, oaIds: [String], duplicadaDe: Int? = nil) {
        self.numero = numero
        self.fecha = fecha
        self.oaIds = oaIds
        self.duplicadaDe = duplicadaDe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numero = container.decodeInt(.numero)
        fecha = container.decodeString(.fecha)
        oaIds = container.decodeStringArray(.oaIds)
        duplicadaDe = try? container.decode(Int.self, forKey: .duplicadaDe)
    }
}

struct CronogramaUnidadData: Codable, Hashable {
    var asignatura: String
    var curso: String
    var unidadId: String
    var totalClases: Int
    var clases: [ClaseCronograma]

    enum CodingKeys: String, CodingKey {
        case asignatura, curso, unidadId, totalClases, clases
    }

    init(asignatura: String, curso: String, unidadId: String, totalClases: Int, clases: [ClaseCronograma]) {
        self.asignatura = asignatura
        self.curso = curso
        self.unidadId = unidadId
        self.totalClases = totalClases
        self.clases = clases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asignatura = container.decodeString(.asignatura)
        curso = container.decodeString(.curso)
        unidadId = container.decodeString(.unidadId)
        clases = container.decodeArray([ClaseCronograma].self, forKey: .clases)
        totalClases = max(container.decodeInt(.totalClases), clases.map(\.numero).max() ?? clases.count)
    }
}

// MARK: - Actividad de Clase
struct ActividadClase: Codable, Hashable, Identifiable {
    var id: String
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
    var archivos: [ArchivoAdjunto]?
    var estado: String
    var sincronizada: Bool
    var contextoProfesor: String?
    var analisisBloom: [AnalisisBloom]?
    var objetivoMultinivel: ObjetivoMultinivel?
    var indicadoresEvaluacion: [IndicadorEvaluacion]?
    var actividadEvaluacion: ActividadEvaluacion?
    var desarrolloFormal: DesarrolloFormal?
    var indicadoresPorOa: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case id, asignatura, curso, unidadId, numeroClase, fecha, oaIds, objetivo, inicio, desarrollo, cierre, adecuacion, habilidades, actitudes, materiales, tics, archivos, estado, sincronizada, contextoProfesor, analisisBloom, objetivoMultinivel, indicadoresEvaluacion, actividadEvaluacion, desarrolloFormal, indicadoresPorOa
        case objetivoClase, actividad, recursos, herramientasTic, contextoDocente
    }

    init(
        id: String,
        asignatura: String,
        curso: String,
        unidadId: String,
        numeroClase: Int,
        fecha: String,
        oaIds: [String],
        objetivo: String,
        inicio: String,
        desarrollo: String,
        cierre: String,
        adecuacion: String,
        habilidades: [String],
        actitudes: [String],
        materiales: [String],
        tics: [String],
        archivos: [ArchivoAdjunto]? = nil,
        estado: String,
        sincronizada: Bool,
        contextoProfesor: String? = nil,
        analisisBloom: [AnalisisBloom]? = nil,
        objetivoMultinivel: ObjetivoMultinivel? = nil,
        indicadoresEvaluacion: [IndicadorEvaluacion]? = nil,
        actividadEvaluacion: ActividadEvaluacion? = nil,
        desarrolloFormal: DesarrolloFormal? = nil,
        indicadoresPorOa: [String: [String]]? = nil
    ) {
        self.id = id
        self.asignatura = asignatura
        self.curso = curso
        self.unidadId = unidadId
        self.numeroClase = numeroClase
        self.fecha = fecha
        self.oaIds = oaIds
        self.objetivo = objetivo
        self.inicio = inicio
        self.desarrollo = desarrollo
        self.cierre = cierre
        self.adecuacion = adecuacion
        self.habilidades = habilidades
        self.actitudes = actitudes
        self.materiales = materiales
        self.tics = tics
        self.archivos = archivos
        self.estado = estado
        self.sincronizada = sincronizada
        self.contextoProfesor = contextoProfesor
        self.analisisBloom = analisisBloom
        self.objetivoMultinivel = objetivoMultinivel
        self.indicadoresEvaluacion = indicadoresEvaluacion
        self.actividadEvaluacion = actividadEvaluacion
        self.desarrolloFormal = desarrolloFormal
        self.indicadoresPorOa = indicadoresPorOa
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeString(.id, default: UUID().uuidString)
        asignatura = container.decodeString(.asignatura)
        curso = container.decodeString(.curso)
        unidadId = container.decodeString(.unidadId)
        numeroClase = container.decodeInt(.numeroClase, default: 1)
        fecha = container.decodeString(.fecha)
        oaIds = container.decodeStringArray(.oaIds)
        let decodedObjetivoMultinivel = try? container.decode(ObjetivoMultinivel.self, forKey: .objetivoMultinivel)
        let decodedDesarrolloFormal = try? container.decode(DesarrolloFormal.self, forKey: .desarrolloFormal)
        objetivoMultinivel = decodedObjetivoMultinivel
        desarrolloFormal = decodedDesarrolloFormal
        objetivo = firstNonEmpty(
            container.decodeString(.objetivo),
            container.decodeString(.objetivoClase),
            decodedObjetivoMultinivel?.textoRecomendado ?? ""
        )
        inicio = container.decodeString(.inicio)
        desarrollo = firstNonEmpty(container.decodeString(.desarrollo), container.decodeString(.actividad))
        cierre = container.decodeString(.cierre)
        adecuacion = container.decodeString(.adecuacion)
        habilidades = container.decodeStringArray(.habilidades)
        actitudes = container.decodeStringArray(.actitudes)
        materiales = container.decodeStringArray(.materiales)
        if materiales.isEmpty {
            materiales = container.decodeStringArray(.recursos)
        }
        tics = container.decodeStringArray(.tics)
        if tics.isEmpty {
            tics = container.decodeStringArray(.herramientasTic)
        }
        archivos = try? container.decode([ArchivoAdjunto].self, forKey: .archivos)
        estado = container.decodeString(.estado, default: "no_planificada")
        sincronizada = container.decodeBool(.sincronizada)
        contextoProfesor = firstNonEmptyOptional(
            try? container.decode(String.self, forKey: .contextoProfesor),
            try? container.decode(String.self, forKey: .contextoDocente)
        )
        analisisBloom = try? container.decode([AnalisisBloom].self, forKey: .analisisBloom)
        indicadoresEvaluacion = try? container.decode([IndicadorEvaluacion].self, forKey: .indicadoresEvaluacion)
        actividadEvaluacion = try? container.decode(ActividadEvaluacion.self, forKey: .actividadEvaluacion)
        indicadoresPorOa = container.decodeStringArrayMap(.indicadoresPorOa)
        if let decodedDesarrolloFormal {
            inicio = firstNonEmpty(inicio, decodedDesarrolloFormal.inicio ?? "")
            desarrollo = firstNonEmpty(desarrollo, decodedDesarrolloFormal.desarrollo ?? "")
            cierre = firstNonEmpty(cierre, decodedDesarrolloFormal.cierre ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(asignatura, forKey: .asignatura)
        try container.encode(curso, forKey: .curso)
        try container.encode(unidadId, forKey: .unidadId)
        try container.encode(numeroClase, forKey: .numeroClase)
        try container.encode(fecha, forKey: .fecha)
        try container.encode(oaIds, forKey: .oaIds)
        try container.encode(objetivo, forKey: .objetivo)
        try container.encode(inicio, forKey: .inicio)
        try container.encode(desarrollo, forKey: .desarrollo)
        try container.encode(cierre, forKey: .cierre)
        try container.encode(adecuacion, forKey: .adecuacion)
        try container.encode(habilidades, forKey: .habilidades)
        try container.encode(actitudes, forKey: .actitudes)
        try container.encode(materiales, forKey: .materiales)
        try container.encode(tics, forKey: .tics)
        try container.encodeIfPresent(archivos, forKey: .archivos)
        try container.encode(estado, forKey: .estado)
        try container.encode(sincronizada, forKey: .sincronizada)
        try container.encodeIfPresent(contextoProfesor, forKey: .contextoProfesor)
        try container.encodeIfPresent(analisisBloom, forKey: .analisisBloom)
        try container.encodeIfPresent(objetivoMultinivel, forKey: .objetivoMultinivel)
        try container.encodeIfPresent(indicadoresEvaluacion, forKey: .indicadoresEvaluacion)
        try container.encodeIfPresent(actividadEvaluacion, forKey: .actividadEvaluacion)
        try container.encodeIfPresent(desarrolloFormal, forKey: .desarrolloFormal)
        try container.encodeIfPresent(indicadoresPorOa, forKey: .indicadoresPorOa)
    }
}
