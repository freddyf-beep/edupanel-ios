import Foundation
import FirebaseFirestore

// MARK: - Procedencia

enum EvaluacionScope: Hashable {
    case principal
    case colegio(String)

    static func resolve(_ colegioActivoId: String?) -> EvaluacionScope {
        let clean = colegioActivoId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty || clean.lowercased() == "principal" ? .principal : .colegio(clean)
    }

    var colegioId: String? {
        guard case .colegio(let id) = self else { return nil }
        return id
    }
}

struct PruebasCargaResultado {
    var pruebas: [PruebaTemplate]
    var documentosConAdvertencias: Int
    var isFromCache: Bool
}

// MARK: - Documento de prueba

struct PruebaTemplate: Identifiable {
    let id: String
    let scope: EvaluacionScope
    let isFromCache: Bool
    let raw: [String: Any]
    let nombre: String
    let asignatura: String
    let curso: String
    let unidadId: String?
    let unidadNombre: String?
    let docenteNombre: String?
    let tipoEvaluacion: String
    let ponderacion: Double?
    let tiempoMinutos: Int?
    let exigencia: Double
    let instruccionesGenerales: [String]
    let metadatosCurriculares: PruebaMetadatosCurriculares
    let oas: [OAEditado]?
    let secciones: [PruebaSeccion]
    let adaptacionesPie: [PruebaAdaptacionPIE]
    let puntajeMaximo: Double
    let estado: String
    let bloqueada: Bool
    let fechaCreacion: Date?
    let fechaActualizacion: Date?
    let issues: [String]

    var totalItems: Int {
        secciones.reduce(0) { $0 + $1.items.count }
    }

    var puntajeCalculado: Double {
        secciones.reduce(0) { total, section in
            total + section.items.reduce(0) { $0 + $1.puntaje }
        }
    }

    var isApplied: Bool {
        estado.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression) == "aplicada"
    }

    var tieneContenidoDesconocido: Bool {
        secciones.contains { section in
            section.estimulo.contains { $0.kind.isUnknown } ||
            section.items.contains { item in
                item.kind.isUnknown || item.recursos.contains { $0.kind.isUnknown }
            }
        }
    }
}

struct PruebaMetadatosCurriculares {
    let objetivos: [String]
    let indicadores: [String]
    let objetivosTransversales: [String]

    static let empty = PruebaMetadatosCurriculares(
        objetivos: [],
        indicadores: [],
        objetivosTransversales: []
    )
}

struct PruebaSeccion: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let orden: Int
    let titulo: String
    let instrucciones: String
    let estimulo: [PruebaContentBlock]
    let tipoPredominante: String?
    let items: [PruebaItem]
}

struct PruebaAdaptacionPIE: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let nombre: String
    let estudianteId: String?
    let estudianteNombre: String?
    let diagnostico: String
    let notasAdecuacion: String
    let instruccionesGenerales: [String]
    let secciones: [PruebaSeccion]
    let fechaCreacion: Date?
    let fechaActualizacion: Date?
}

// MARK: - Ítems

enum PruebaItemKind: Hashable {
    case seleccionMultiple
    case verdaderoFalso
    case pareados
    case ordenar
    case completar
    case respuestaCorta
    case desarrollo
    case unknown(String)

    static func resolve(_ rawValue: String) -> PruebaItemKind {
        let key = rawValue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch key {
        case "seleccion_multiple", "seleccion", "multiple", "alternativas": return .seleccionMultiple
        case "verdadero_falso", "verdadero", "vf": return .verdaderoFalso
        case "pareados", "pareado", "terminos_pareados": return .pareados
        case "ordenar", "orden", "secuencia": return .ordenar
        case "completar", "rellenar": return .completar
        case "respuesta_corta", "respuesta": return .respuestaCorta
        case "desarrollo", "desarrollo_visual", "abierta": return .desarrollo
        default: return .unknown(rawValue)
        }
    }

    var label: String {
        switch self {
        case .seleccionMultiple: return "Selección múltiple"
        case .verdaderoFalso: return "Verdadero o falso"
        case .pareados: return "Términos pareados"
        case .ordenar: return "Ordenar secuencia"
        case .completar: return "Completar"
        case .respuestaCorta: return "Respuesta corta"
        case .desarrollo: return "Desarrollo"
        case .unknown(let value): return value.isEmpty ? "Tipo desconocido" : value
        }
    }

    var icon: String {
        switch self {
        case .seleccionMultiple: return "checkmark.circle"
        case .verdaderoFalso: return "checkmark.square"
        case .pareados: return "arrow.left.arrow.right"
        case .ordenar: return "list.number"
        case .completar: return "text.insert"
        case .respuestaCorta: return "text.cursor"
        case .desarrollo: return "text.alignleft"
        case .unknown: return "questionmark.diamond"
        }
    }

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

struct PruebaItem: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let rawType: String
    let kind: PruebaItemKind
    let enunciado: String
    let puntaje: Double
    let oaVinculado: String?
    let habilidad: String?
    let recursos: [PruebaContentBlock]
    let alternativas: [PruebaAlternativa]
    let respuestaCorrecta: Bool?
    let pideJustificacion: Bool
    let columnaA: [PruebaPareadoA]
    let columnaB: [PruebaPareadoB]
    let pasos: [PruebaPaso]
    let textoConBlancos: String?
    let respuestasCorrectas: [String]
    let bancoPalabras: [String]
    let respuestaEsperada: String?
    let lineasRespuesta: Int?
    let pautaCorreccion: String?
    let criterios: [PruebaCriterioDesarrollo]
}

struct PruebaAlternativa: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let originalIndex: Int
    let texto: String
    let esCorrecta: Bool
    let imagenUrl: String?
    let imagenStoragePath: String?
}

struct PruebaPareadoA: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let originalIndex: Int
    let texto: String
    let imagenUrl: String?
}

struct PruebaPareadoB: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let originalIndex: Int
    let texto: String
    let correctaParaAId: String?
}

struct PruebaPaso: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let originalIndex: Int
    let texto: String
}

struct PruebaCriterioDesarrollo: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let originalIndex: Int
    let texto: String
    let puntaje: Double
}

// MARK: - Bloques de contenido

enum PruebaContentBlockKind: Hashable {
    case texto
    case imagen
    case tabla
    case separador
    case unknown(String)

    static func resolve(_ rawValue: String) -> PruebaContentBlockKind {
        switch rawValue.lowercased() {
        case "texto": return .texto
        case "imagen": return .imagen
        case "tabla": return .tabla
        case "separador": return .separador
        default: return .unknown(rawValue)
        }
    }

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

struct PruebaContentBlock: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let rawType: String
    let kind: PruebaContentBlockKind
    let html: String?
    let estilo: String?
    let url: String?
    let storagePath: String?
    let alt: String?
    let caption: String?
    let ancho: String?
    let alineacion: String?
    let cabeceras: [String]
    let filas: [[String]]
    let primeraColumnaCabecera: Bool
}

// MARK: - Aplicación y resultados

struct PruebaAplicacion: Identifiable {
    let id: String
    let scope: EvaluacionScope
    let isFromCache: Bool
    let raw: [String: Any]
    let pruebaId: String
    let pruebaNombre: String
    let asignatura: String
    let curso: String
    let fechaAplicacion: String?
    let resultados: [PruebaResultadoEstudiante]
    let bloqueada: Bool
    let fechaActualizacion: Date?
    let issues: [String]

    var completados: [PruebaResultadoEstudiante] {
        resultados.filter { $0.completado && !$0.ausente }
    }

    var promedio: Double? {
        let notas = completados.compactMap(\.nota)
        guard !notas.isEmpty else { return nil }
        return notas.reduce(0, +) / Double(notas.count)
    }
}

struct PruebaResultadoEstudiante: Identifiable {
    let id: String
    let sourceId: String?
    let raw: [String: Any]
    let nombre: String
    let hasPie: Bool
    let respuestas: [String: Any]
    let puntajePorItem: [String: Double]
    let puntajeTotal: Double
    let nota: Double?
    let observaciones: String?
    let completado: Bool
    let ausente: Bool
}

// MARK: - Parser Firestore tolerante y lossless

enum PruebaDocumentParser {
    static func prueba(
        id: String,
        scope: EvaluacionScope,
        isFromCache: Bool,
        dictionary: [String: Any]
    ) -> PruebaTemplate {
        var issues: [String] = []
        let sectionDicts = Read.dictionaryArray(dictionary["secciones"])
        let sections = sectionDicts.enumerated().map { index, value in
            section(value, path: "\(id)/section/\(index)", fallbackOrder: index + 1, issues: &issues)
        }
        let adaptations = Read.dictionaryArray(dictionary["adaptacionesPie"]).enumerated().map { index, value in
            adaptation(value, path: "\(id)/pie/\(index)", issues: &issues)
        }
        let metadata = Read.dictionary(dictionary["metadatosCurriculares"])
        let oas = Read.decodeOAs(dictionary["oas"])
        if dictionary["oas"] != nil, oas == nil {
            issues.append("La selección curricular OA usa un formato futuro o no legible; se conservará intacta.")
        }
        let storedScore = Read.double(dictionary["puntajeMaximo"])
        let calculatedScore = sections.reduce(0) { total, section in
            total + section.items.reduce(0) { $0 + $1.puntaje }
        }
        let course = Read.string(dictionary["curso"])
        if course.isEmpty { issues.append("La prueba no declara curso.") }
        if sections.isEmpty { issues.append("La prueba no contiene secciones legibles.") }

        return PruebaTemplate(
            id: id,
            scope: scope,
            isFromCache: isFromCache,
            raw: dictionary,
            nombre: Read.string(dictionary["nombre"]),
            asignatura: Read.string(dictionary["asignatura"]),
            curso: course,
            unidadId: Read.optionalString(dictionary["unidadId"]),
            unidadNombre: Read.optionalString(dictionary["unidadNombre"]),
            docenteNombre: Read.optionalString(dictionary["docenteNombre"]),
            tipoEvaluacion: Read.optionalString(dictionary["tipoEvaluacion"]) ?? "sumativa",
            ponderacion: Read.double(dictionary["ponderacion"]),
            tiempoMinutos: Read.int(dictionary["tiempoMinutos"]),
            exigencia: Read.double(dictionary["exigencia"]) ?? 0.6,
            instruccionesGenerales: Read.stringArray(dictionary["instruccionesGenerales"]),
            metadatosCurriculares: metadata.map {
                PruebaMetadatosCurriculares(
                    objetivos: Read.stringArray($0["objetivos"]),
                    indicadores: Read.stringArray($0["indicadores"]),
                    objetivosTransversales: Read.stringArray($0["objetivosTransversales"])
                )
            } ?? .empty,
            oas: oas,
            secciones: sections,
            adaptacionesPie: adaptations,
            puntajeMaximo: storedScore ?? calculatedScore,
            estado: Read.optionalString(dictionary["estado"]) ?? "borrador",
            bloqueada: Read.bool(dictionary["bloqueada"]) ?? false,
            fechaCreacion: Read.date(dictionary["createdAt"]),
            fechaActualizacion: Read.date(dictionary["updatedAt"]),
            issues: issues
        )
    }

    static func aplicacion(
        id: String,
        scope: EvaluacionScope,
        isFromCache: Bool,
        dictionary: [String: Any]
    ) -> PruebaAplicacion {
        var issues: [String] = []
        let results = Read.dictionaryArray(dictionary["resultados"]).enumerated().map { index, value in
            result(value, path: "\(id)/result/\(index)", issues: &issues)
        }
        let pruebaId = Read.string(dictionary["pruebaId"])
        if pruebaId.isEmpty { issues.append("La aplicación no declara pruebaId.") }
        return PruebaAplicacion(
            id: id,
            scope: scope,
            isFromCache: isFromCache,
            raw: dictionary,
            pruebaId: pruebaId,
            pruebaNombre: Read.string(dictionary["pruebaNombre"]),
            asignatura: Read.string(dictionary["asignatura"]),
            curso: Read.string(dictionary["curso"]),
            fechaAplicacion: Read.optionalString(dictionary["fechaAplicacion"]),
            resultados: results,
            bloqueada: Read.bool(dictionary["bloqueada"]) ?? false,
            fechaActualizacion: Read.date(dictionary["updatedAt"]),
            issues: issues
        )
    }

    private static func section(
        _ dictionary: [String: Any],
        path: String,
        fallbackOrder: Int,
        issues: inout [String]
    ) -> PruebaSeccion {
        let sourceId = Read.optionalString(dictionary["id"])
        let order = Read.int(dictionary["orden"]) ?? fallbackOrder
        let itemDicts = Read.dictionaryArray(dictionary["items"])
        let items = itemDicts.enumerated().map { index, value in
            item(value, path: "\(path)/item/\(index)", issues: &issues)
        }
        let blocks = Read.dictionaryArray(dictionary["estimulo"]).enumerated().map { index, value in
            contentBlock(value, path: "\(path)/stimulus/\(index)", issues: &issues)
        }
        return PruebaSeccion(
            id: "\(path)/\(sourceId ?? "missing")",
            sourceId: sourceId,
            raw: dictionary,
            orden: order,
            titulo: Read.optionalString(dictionary["titulo"]) ?? "Ítem \(roman(order))",
            instrucciones: Read.string(dictionary["instrucciones"]),
            estimulo: blocks,
            tipoPredominante: Read.optionalString(dictionary["tipoPredominante"]),
            items: items
        )
    }

    private static func adaptation(
        _ dictionary: [String: Any],
        path: String,
        issues: inout [String]
    ) -> PruebaAdaptacionPIE {
        let sourceId = Read.optionalString(dictionary["id"])
        let sections = Read.dictionaryArray(dictionary["secciones"]).enumerated().map { index, value in
            section(value, path: "\(path)/section/\(index)", fallbackOrder: index + 1, issues: &issues)
        }
        return PruebaAdaptacionPIE(
            id: "\(path)/\(sourceId ?? "missing")",
            sourceId: sourceId,
            raw: dictionary,
            nombre: Read.optionalString(dictionary["nombre"]) ?? "Adecuación PIE",
            estudianteId: Read.optionalString(dictionary["estudianteId"]),
            estudianteNombre: Read.optionalString(dictionary["estudianteNombre"]),
            diagnostico: Read.string(dictionary["diagnostico"]),
            notasAdecuacion: Read.string(dictionary["notasAdecuacion"]),
            instruccionesGenerales: Read.stringArray(dictionary["instruccionesGenerales"]),
            secciones: sections,
            fechaCreacion: Read.date(dictionary["createdAt"]),
            fechaActualizacion: Read.date(dictionary["updatedAt"])
        )
    }

    private static func item(
        _ dictionary: [String: Any],
        path: String,
        issues: inout [String]
    ) -> PruebaItem {
        let sourceId = Read.optionalString(dictionary["id"])
        let rawType = Read.string(dictionary["tipo"])
        let kind = PruebaItemKind.resolve(rawType)
        if kind.isUnknown { issues.append("Ítem con tipo no reconocido: \(rawType.isEmpty ? "sin tipo" : rawType).") }
        let resources = Read.dictionaryArray(dictionary["recursos"]).enumerated().map { index, value in
            contentBlock(value, path: "\(path)/resource/\(index)", issues: &issues)
        }
        let alternatives = Read.dictionaryArray(dictionary["alternativas"]).enumerated().map { index, value in
            let alternativeId = Read.optionalString(value["id"])
            return PruebaAlternativa(
                id: "\(path)/alternative/\(index)/\(alternativeId ?? "missing")",
                sourceId: alternativeId,
                raw: value,
                originalIndex: index,
                texto: Read.string(value["texto"]),
                esCorrecta: Read.bool(value["esCorrecta"]) ?? Read.bool(value["correcta"]) ?? false,
                imagenUrl: Read.optionalString(value["imagenUrl"]),
                imagenStoragePath: Read.optionalString(value["imagenStoragePath"])
            )
        }
        let columnA = Read.dictionaryArray(dictionary["columnaA"]).enumerated().map { index, value in
            let valueId = Read.optionalString(value["id"])
            return PruebaPareadoA(
                id: "\(path)/column-a/\(index)/\(valueId ?? "missing")",
                sourceId: valueId,
                raw: value,
                originalIndex: index,
                texto: Read.string(value["texto"]),
                imagenUrl: Read.optionalString(value["imagenUrl"])
            )
        }
        let columnB = Read.dictionaryArray(dictionary["columnaB"]).enumerated().map { index, value in
            let valueId = Read.optionalString(value["id"])
            return PruebaPareadoB(
                id: "\(path)/column-b/\(index)/\(valueId ?? "missing")",
                sourceId: valueId,
                raw: value,
                originalIndex: index,
                texto: Read.string(value["texto"]),
                correctaParaAId: Read.optionalString(value["correctaParaAId"]) ?? Read.optionalString(value["pareCon"])
            )
        }
        let steps = Read.dictionaryArray(dictionary["pasos"]).enumerated().map { index, value in
            let valueId = Read.optionalString(value["id"])
            return PruebaPaso(
                id: "\(path)/step/\(index)/\(valueId ?? "missing")",
                sourceId: valueId,
                raw: value,
                originalIndex: index,
                texto: Read.string(value["texto"])
            )
        }
        let criteria = Read.dictionaryArray(dictionary["criterios"]).enumerated().map { index, value in
            let valueId = Read.optionalString(value["id"])
            return PruebaCriterioDesarrollo(
                id: "\(path)/criterion/\(index)/\(valueId ?? "missing")",
                sourceId: valueId,
                raw: value,
                originalIndex: index,
                texto: Read.string(value["texto"]),
                puntaje: Read.double(value["puntaje"]) ?? 0
            )
        }
        return PruebaItem(
            id: "\(path)/\(sourceId ?? "missing")",
            sourceId: sourceId,
            raw: dictionary,
            rawType: rawType,
            kind: kind,
            enunciado: Read.string(dictionary["enunciado"]),
            puntaje: max(0, Read.double(dictionary["puntaje"]) ?? 0),
            oaVinculado: Read.optionalString(dictionary["oaVinculado"]),
            habilidad: Read.optionalString(dictionary["habilidad"]),
            recursos: resources,
            alternativas: alternatives,
            respuestaCorrecta: Read.bool(dictionary["respuestaCorrecta"]) ?? Read.bool(dictionary["correcta"]),
            pideJustificacion: Read.bool(dictionary["pideJustificacion"]) ?? false,
            columnaA: columnA,
            columnaB: columnB,
            pasos: steps,
            textoConBlancos: Read.optionalString(dictionary["textoConBlancos"]),
            respuestasCorrectas: Read.stringArray(dictionary["respuestas"]),
            bancoPalabras: Read.stringArray(dictionary["bancoPalabras"]),
            respuestaEsperada: Read.optionalString(dictionary["respuestaEsperada"]),
            lineasRespuesta: Read.int(dictionary["lineasRespuesta"]),
            pautaCorreccion: Read.optionalString(dictionary["pautaCorreccion"]),
            criterios: criteria
        )
    }

    private static func contentBlock(
        _ dictionary: [String: Any],
        path: String,
        issues: inout [String]
    ) -> PruebaContentBlock {
        let sourceId = Read.optionalString(dictionary["id"])
        let rawType = Read.string(dictionary["tipo"])
        let kind = PruebaContentBlockKind.resolve(rawType)
        if kind.isUnknown { issues.append("Bloque de contenido no reconocido: \(rawType.isEmpty ? "sin tipo" : rawType).") }
        let data = Read.dictionary(dictionary["data"]) ?? [:]
        return PruebaContentBlock(
            id: "\(path)/\(sourceId ?? "missing")",
            sourceId: sourceId,
            raw: dictionary,
            rawType: rawType,
            kind: kind,
            html: Read.optionalString(data["html"]),
            estilo: Read.optionalString(data["estilo"]),
            url: Read.optionalString(data["url"]),
            storagePath: Read.optionalString(data["storagePath"]),
            alt: Read.optionalString(data["alt"]),
            caption: Read.optionalString(data["caption"]),
            ancho: Read.optionalString(data["ancho"]),
            alineacion: Read.optionalString(data["alineacion"]),
            cabeceras: Read.stringArray(data["cabeceras"]),
            filas: Read.nestedStringArray(data["filas"]),
            primeraColumnaCabecera: Read.bool(data["primeraColumnaCabecera"]) ?? false
        )
    }

    private static func result(
        _ dictionary: [String: Any],
        path: String,
        issues: inout [String]
    ) -> PruebaResultadoEstudiante {
        let sourceId = Read.optionalString(dictionary["estudianteId"])
        if sourceId == nil { issues.append("Resultado sin estudianteId.") }
        return PruebaResultadoEstudiante(
            id: "\(path)/\(sourceId ?? "missing")",
            sourceId: sourceId,
            raw: dictionary,
            nombre: Read.optionalString(dictionary["nombre"]) ?? Read.optionalString(dictionary["name"]) ?? "Estudiante",
            hasPie: Read.bool(dictionary["hasPie"]) ?? Read.bool(dictionary["pie"]) ?? false,
            respuestas: Read.dictionary(dictionary["respuestas"]) ?? [:],
            puntajePorItem: Read.doubleMap(dictionary["puntajePorItem"]),
            puntajeTotal: Read.double(dictionary["puntajeTotal"]) ?? 0,
            nota: Read.double(dictionary["nota"]),
            observaciones: Read.optionalString(dictionary["observaciones"]),
            completado: Read.bool(dictionary["completado"]) ?? false,
            ausente: Read.bool(dictionary["ausente"]) ?? false
        )
    }

    private static func roman(_ value: Int) -> String {
        guard value > 0, value < 40 else { return String(value) }
        let values: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var number = value
        var result = ""
        for (amount, symbol) in values {
            while number >= amount {
                result += symbol
                number -= amount
            }
        }
        return result
    }
}

private enum Read {
    static func string(_ value: Any?) -> String {
        optionalString(value) ?? ""
    }

    static func optionalString(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case is Bool: return nil
        case let number as NSNumber: return number.stringValue
        case let int as Int: return String(int)
        case let double as Double: return String(double)
        default: return nil
        }
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case is Bool: return nil
        case let number as NSNumber: return number.doubleValue
        case let int as Int: return Double(int)
        case let double as Double: return double
        case let string as String: return Double(string.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        guard let number = double(value), number.isFinite else { return nil }
        return Int(number)
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.intValue != 0
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "si", "sí": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        if let dictionaries = value as? [[String: Any]] { return dictionaries }
        return (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    static func stringArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { optionalString($0) }
    }

    static func nestedStringArray(_ value: Any?) -> [[String]] {
        guard let values = value as? [Any] else { return [] }
        return values.map { stringArray($0) }
    }

    static func doubleMap(_ value: Any?) -> [String: Double] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.reduce(into: [:]) { result, entry in
            if let number = double(entry.value) { result[entry.key] = number }
        }
    }

    static func decodeOAs(_ value: Any?) -> [OAEditado]? {
        guard let values = value as? [Any] else { return nil }
        var sanitized: [[String: Any]] = []
        sanitized.reserveCapacity(values.count)
        for (oaIndex, rawValue) in values.enumerated() {
            guard let oa = rawValue as? [String: Any] else { return nil }
            var cleanOA: [String: Any] = [:]
            if let number = int(oa["numero"]) { cleanOA["numero"] = number }
            if let type = optionalString(oa["tipo"]) { cleanOA["tipo"] = type }
            cleanOA["descripcion"] = optionalString(oa["descripcion"]) ?? ""
            cleanOA["seleccionado"] = bool(oa["seleccionado"]) ?? false
            if let own = bool(oa["esPropio"]) { cleanOA["esPropio"] = own }
            if oa["tags"] is [Any] { cleanOA["tags"] = stringArray(oa["tags"]) }
            let oaId = optionalString(oa["id"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            cleanOA["id"] = oaId.isEmpty ? "oa_heredado_\(oaIndex)" : oaId
            if let rawIndicators = oa["indicadores"] as? [Any] {
                var indicators: [[String: Any]] = []
                indicators.reserveCapacity(rawIndicators.count)
                for (indicatorIndex, rawIndicator) in rawIndicators.enumerated() {
                    guard let indicator = rawIndicator as? [String: Any] else { return nil }
                    var cleanIndicator: [String: Any] = [:]
                    cleanIndicator["texto"] = optionalString(indicator["texto"]) ?? ""
                    cleanIndicator["seleccionado"] = bool(indicator["seleccionado"]) ?? false
                    if let own = bool(indicator["esPropio"]) { cleanIndicator["esPropio"] = own }
                    let indicatorId = optionalString(indicator["id"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    cleanIndicator["id"] = indicatorId.isEmpty
                        ? "ind_heredado_\(oaIndex)_\(indicatorIndex)" : indicatorId
                    indicators.append(cleanIndicator)
                }
                cleanOA["indicadores"] = indicators
            }
            sanitized.append(cleanOA)
        }
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized) else { return nil }
        return try? JSONDecoder().decode([OAEditado].self, from: data)
    }

    static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        if let number = double(value) {
            let seconds = number > 10_000_000_000 ? number / 1_000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        if let dictionary = value as? [String: Any],
           let seconds = double(dictionary["seconds"] ?? dictionary["_seconds"]) {
            let nanos = double(dictionary["nanoseconds"] ?? dictionary["_nanoseconds"]) ?? 0
            return Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000)
        }
        guard let string = value as? String else { return nil }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        for format in ["yyyy-MM-dd", "dd/MM/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_CL")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
