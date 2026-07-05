import Foundation

struct EstudianteCalif: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var orden: Int?
    var notas: [String: String]
    var decimas: [String: Int]?
    var hasPie: Bool
    var pieDiagnostico: String?
}

struct EvaluacionCalif: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var tipo: String
    var periodo: String
    var ponderacion: Double?
    var oaIds: [String]?
    var unidadId: String?
}

struct CalificacionesDoc: Codable, Hashable {
    var asignatura: String
    var curso: String
    var estudiantes: [EstudianteCalif]
    var evaluaciones: [EvaluacionCalif]
}

extension CalificacionesDoc {
    func notaEfectiva(estudiante: EstudianteCalif, evalId: String) -> Double? {
        guard let raw = estudiante.notas[evalId] else { return nil }
        let limpio = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty,
              let nota = Double(limpio.replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        let decima = Double(estudiante.decimas?[evalId] ?? 0) * 0.1
        return min(7.0, nota + decima)
    }

    func promedio(estudiante: EstudianteCalif, evaluaciones: [EvaluacionCalif]) -> Double? {
        let notas = evaluaciones.compactMap { evaluacion -> (nota: Double, ponderacion: Double?)? in
            guard let nota = notaEfectiva(estudiante: estudiante, evalId: evaluacion.id) else { return nil }
            return (nota, evaluacion.ponderacion)
        }
        guard !notas.isEmpty else { return nil }

        let puedePonderar = notas.allSatisfy { ($0.ponderacion ?? 0) > 0 }
        let promedio: Double
        if puedePonderar {
            let sumaPonderada = notas.reduce(0.0) { $0 + $1.nota * ($1.ponderacion ?? 0) }
            let sumaPesos = notas.reduce(0.0) { $0 + ($1.ponderacion ?? 0) }
            promedio = sumaPesos > 0 ? sumaPonderada / sumaPesos : notas.map(\.nota).reduce(0, +) / Double(notas.count)
        } else {
            promedio = notas.map(\.nota).reduce(0, +) / Double(notas.count)
        }
        return (promedio * 10).rounded() / 10
    }
}

private extension KeyedDecodingContainer {
    func calString(_ key: Key, default defaultValue: String = "") -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(format: "%.1f", value) }
        return defaultValue
    }

    func calStringOpt(_ key: Key) -> String? {
        try? decode(String.self, forKey: key)
    }

    func calIntOpt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func calDoubleOpt(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    func calBool(_ key: Key, default defaultValue: Bool = false) -> Bool {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            let limpio = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["true", "1", "si", "sí", "yes"].contains(limpio)
        }
        return defaultValue
    }

    func calStringArray(_ key: Key) -> [String]? {
        if let value = try? decode([String].self, forKey: key) { return value }
        return nil
    }

    func calArray<T: Decodable>(_ type: [T].Type, _ key: Key) -> [T] {
        (try? decode(type, forKey: key)) ?? []
    }

    func calNotaMap(_ key: Key) -> [String: String] {
        if let value = try? decode([String: String].self, forKey: key) { return value }
        if let value = try? decode([String: Double].self, forKey: key) {
            return value.mapValues { String(format: "%.1f", $0) }
        }
        if let value = try? decode([String: Int].self, forKey: key) {
            return value.mapValues { String(format: "%.1f", Double($0)) }
        }
        return [:]
    }

    func calIntMap(_ key: Key) -> [String: Int]? {
        if let value = try? decode([String: Int].self, forKey: key) { return value }
        if let value = try? decode([String: Double].self, forKey: key) {
            return value.mapValues { Int($0) }
        }
        if let value = try? decode([String: String].self, forKey: key) {
            let mapped = value.compactMapValues { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return mapped.isEmpty ? nil : mapped
        }
        return nil
    }
}

extension EstudianteCalif {
    private enum TolerantKeys: String, CodingKey {
        case id, name, nombre, orden, notas, decimas, hasPie, pieDiagnostico
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        id = c.calString(.id, default: EvaluacionesIDs.uid(prefix: "est"))
        name = c.calString(.name)
        if name.isEmpty { name = c.calString(.nombre) }
        orden = c.calIntOpt(.orden)
        notas = c.calNotaMap(.notas)
        decimas = c.calIntMap(.decimas)
        hasPie = c.calBool(.hasPie)
        pieDiagnostico = c.calStringOpt(.pieDiagnostico)
    }
}

extension EvaluacionCalif {
    private enum TolerantKeys: String, CodingKey {
        case id, label, tipo, periodo, ponderacion, oaIds, unidadId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        id = c.calString(.id, default: EvaluacionesIDs.uid(prefix: "eval"))
        label = c.calString(.label, default: "Evaluacion")
        tipo = c.calString(.tipo, default: "sumativa")
        periodo = c.calString(.periodo, default: "s1")
        ponderacion = c.calDoubleOpt(.ponderacion)
        oaIds = c.calStringArray(.oaIds)
        unidadId = c.calStringOpt(.unidadId)
    }
}

extension CalificacionesDoc {
    private enum TolerantKeys: String, CodingKey {
        case asignatura, curso, estudiantes, evaluaciones
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        asignatura = c.calString(.asignatura)
        curso = c.calString(.curso)
        estudiantes = c.calArray([EstudianteCalif].self, .estudiantes)
        evaluaciones = c.calArray([EvaluacionCalif].self, .evaluaciones)
    }
}
