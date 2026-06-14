import Foundation

// MARK: - Listas de Cotejo

struct IndicadorListaCotejo: Codable, Identifiable, Hashable {
    var id: String
    var orden: Int
    var texto: String
    var oasVinculados: [String]?
    var esTransversal: Bool?
    var focoDiferenciadoActivo: Bool?
    var focoDiferenciadoTexto: String?
    var puedoFilmarloConfirmado: Bool?

    static func nuevo() -> IndicadorListaCotejo {
        IndicadorListaCotejo(id: EvaluacionesIDs.uid(prefix: "ind"), orden: 1, texto: "", oasVinculados: [])
    }
}

struct SeccionListaCotejo: Codable, Identifiable, Hashable {
    var id: String
    var orden: Int
    var nombre: String
    var oasVinculados: [String]
    var indicadores: [IndicadorListaCotejo]

    static func nueva(numero: Int) -> SeccionListaCotejo {
        SeccionListaCotejo(
            id: EvaluacionesIDs.uid(prefix: "sec"),
            orden: numero,
            nombre: "Seccion \(numero)",
            oasVinculados: [],
            indicadores: [.nuevo()]
        )
    }
}

struct ListaCotejoMetadatos: Codable, Hashable {
    var objetivos: [String]
    var indicadores: [String]
    var objetivosTransversales: [String]

    static let vacios = ListaCotejoMetadatos(objetivos: [], indicadores: [], objetivosTransversales: [])
}

struct ListaCotejoTemplate: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var asignatura: String
    var curso: String
    var unidadId: String?
    var unidadNombre: String?
    var metadatosCurriculares: ListaCotejoMetadatos?
    var secciones: [SeccionListaCotejo]
    var puntajePorSi: Double
    var puntajeMaximo: Double
    var instruccionesMetodologicas: String?
    var escalaDicotomica: [String]?
    var rbd: String?
    var nombreEstablecimiento: String?
    var docenteNombre: String?

    var fechaActualizacion: Date? = nil

    private enum CodingKeys: String, CodingKey {
        case id, nombre, asignatura, curso, unidadId, unidadNombre, metadatosCurriculares
        case secciones, puntajePorSi, puntajeMaximo, instruccionesMetodologicas
        case escalaDicotomica, rbd, nombreEstablecimiento, docenteNombre
    }

    var etiquetaSi: String { escalaDicotomica?.first ?? "Sí" }
    var etiquetaNo: String { (escalaDicotomica?.count ?? 0) > 1 ? escalaDicotomica![1] : "No" }

    var indicadoresTotales: [IndicadorListaCotejo] {
        secciones.flatMap(\.indicadores)
    }

    mutating func normalizar() {
        nombre = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        secciones = secciones
            .sorted { $0.orden < $1.orden }
            .map { seccion in
                var next = seccion
                next.indicadores = seccion.indicadores
                    .sorted { $0.orden < $1.orden }
                    .compactMap { indicador in
                        var nextInd = indicador
                        nextInd.texto = indicador.texto.trimmingCharacters(in: .whitespacesAndNewlines)
                        return nextInd.texto.isEmpty ? nil : nextInd
                    }
                return next
            }
            .filter { !$0.indicadores.isEmpty }
            .enumerated()
            .map { index, seccion in
                var next = seccion
                next.orden = index + 1
                let nombreLimpio = seccion.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
                next.nombre = nombreLimpio.isEmpty ? "Seccion \(index + 1)" : nombreLimpio
                for indIndex in next.indicadores.indices {
                    next.indicadores[indIndex].orden = indIndex + 1
                }
                return next
            }
        puntajePorSi = puntajePorSi > 0 ? puntajePorSi : 1
        puntajeMaximo = Double(indicadoresTotales.count) * puntajePorSi
    }

    static func nueva(asignatura: String, curso: String) -> ListaCotejoTemplate {
        ListaCotejoTemplate(
            id: EvaluacionesIDs.buildListaCotejoId(asignatura: asignatura, curso: curso),
            nombre: "",
            asignatura: asignatura,
            curso: curso,
            metadatosCurriculares: .vacios,
            secciones: [.nueva(numero: 1)],
            puntajePorSi: 1,
            puntajeMaximo: 1,
            escalaDicotomica: ["Sí", "No"]
        )
    }
}

struct EstudianteListaCotejo: Codable, Identifiable, Hashable {
    var estudianteId: String
    var nombre: String
    var hasPie: Bool
    var respuestas: [String: Bool]
    var observaciones: String
    var puntaje: Double?
    var porcentaje: Double?
    var nota: Double?
    var completado: Bool

    var id: String { estudianteId }

    mutating func recalcular(con lista: ListaCotejoTemplate) {
        let puntajePorSi = lista.puntajePorSi > 0 ? lista.puntajePorSi : 1
        let ids = lista.indicadoresTotales.map(\.id)
        let nuevoPuntaje = ids.reduce(0.0) { total, indicadorId in
            total + (respuestas[indicadorId] == true ? puntajePorSi : 0)
        }
        puntaje = nuevoPuntaje
        porcentaje = lista.puntajeMaximo > 0 ? (nuevoPuntaje / lista.puntajeMaximo * 100).rounded() : 0
        nota = NotaChilena.calcular(puntaje: nuevoPuntaje, puntajeMaximo: lista.puntajeMaximo, exigencia: hasPie ? 0.5 : 0.6)
        completado = !ids.isEmpty && ids.allSatisfy { respuestas[$0] != nil }
    }

    static func desde(estudiante: EstudiantePerfil) -> EstudianteListaCotejo {
        EstudianteListaCotejo(
            estudianteId: estudiante.id,
            nombre: estudiante.nombre,
            hasPie: estudiante.pie,
            respuestas: [:],
            observaciones: "",
            completado: false
        )
    }
}

struct GrupoListaCotejo: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var estudiantes: [EstudianteListaCotejo]

    var esAusentes: Bool {
        nombre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ausentes"
    }
}

struct ListaCotejoEvaluacion: Codable, Identifiable, Hashable {
    var id: String
    var listaId: String
    var listaNombre: String
    var asignatura: String
    var curso: String
    var grupos: [GrupoListaCotejo]
    var puntajeMaximo: Double
    var bloqueada: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, listaId, listaNombre, asignatura, curso, grupos, puntajeMaximo, bloqueada
    }

    var todosLosEstudiantes: [EstudianteListaCotejo] {
        grupos.flatMap(\.estudiantes)
    }

    var estudiantesAusentes: [EstudianteListaCotejo] {
        grupos.first(where: \.esAusentes)?.estudiantes ?? []
    }

    static func nueva(lista: ListaCotejoTemplate, estudiantes: [EstudiantePerfil]) -> ListaCotejoEvaluacion {
        var iniciales = estudiantes.map(EstudianteListaCotejo.desde)
        for index in iniciales.indices {
            iniciales[index].recalcular(con: lista)
        }
        return ListaCotejoEvaluacion(
            id: EvaluacionesIDs.buildListaEvaluacionId(listaId: lista.id),
            listaId: lista.id,
            listaNombre: lista.nombre,
            asignatura: lista.asignatura,
            curso: lista.curso,
            grupos: [GrupoListaCotejo(id: "grupo_1", nombre: "Grupo 1", estudiantes: iniciales)],
            puntajeMaximo: lista.puntajeMaximo
        )
    }

    mutating func sincronizarEstudiantes(_ alumnos: [EstudiantePerfil], lista: ListaCotejoTemplate) {
        let porId = Dictionary(alumnos.map { ($0.id, $0) }) { first, _ in first }
        let porNombre = Dictionary(alumnos.map { (EvaluacionesIDs.normalizeName($0.nombre), $0) }) { first, _ in first }

        if grupos.isEmpty {
            grupos = [GrupoListaCotejo(id: "grupo_1", nombre: "Grupo 1", estudiantes: [])]
        }

        for grupoIndex in grupos.indices {
            for estIndex in grupos[grupoIndex].estudiantes.indices {
                var est = grupos[grupoIndex].estudiantes[estIndex]
                if let alumno = porId[est.estudianteId] ?? porNombre[EvaluacionesIDs.normalizeName(est.nombre)] {
                    est.estudianteId = alumno.id
                    est.nombre = alumno.nombre
                    est.hasPie = alumno.pie
                }
                est.recalcular(con: lista)
                grupos[grupoIndex].estudiantes[estIndex] = est
            }
        }

        let asignados = Set(grupos.flatMap { $0.estudiantes.map(\.estudianteId) })
        let nuevos = alumnos.filter { !asignados.contains($0.id) }
        if !nuevos.isEmpty {
            var agregados = nuevos.map(EstudianteListaCotejo.desde)
            for index in agregados.indices {
                agregados[index].recalcular(con: lista)
            }
            grupos[0].estudiantes.append(contentsOf: agregados)
        }
        puntajeMaximo = lista.puntajeMaximo
    }
}

// MARK: - Rúbricas

struct NivelEvaluacion: Codable, Hashable {
    var descripcion: String
    var puntos: Double
}

struct NivelesCriterio: Codable, Hashable {
    var logrado: NivelEvaluacion
    var casiLogrado: NivelEvaluacion
    var parcialmenteLogrado: NivelEvaluacion
    var porLograr: NivelEvaluacion

    static let vacios = NivelesCriterio(
        logrado: NivelEvaluacion(descripcion: "", puntos: 4),
        casiLogrado: NivelEvaluacion(descripcion: "", puntos: 3),
        parcialmenteLogrado: NivelEvaluacion(descripcion: "", puntos: 2),
        porLograr: NivelEvaluacion(descripcion: "", puntos: 1)
    )
}

struct CriterioRubrica: Codable, Identifiable, Hashable {
    var id: String
    var orden: Int
    var nombre: String
    var ponderacion: Double?
    var niveles: NivelesCriterio

    static func nuevo() -> CriterioRubrica {
        CriterioRubrica(id: EvaluacionesIDs.uid(prefix: "crit"), orden: 1, nombre: "", niveles: .vacios)
    }
}

struct RubricaParte: Codable, Identifiable, Hashable {
    var id: String
    var orden: Int
    var nombre: String
    var oasVinculados: [String]
    var criterios: [CriterioRubrica]

    static func nueva(numero: Int) -> RubricaParte {
        RubricaParte(
            id: EvaluacionesIDs.uid(prefix: "parte"),
            orden: numero,
            nombre: "Parte \(numero)",
            oasVinculados: [],
            criterios: [.nuevo()]
        )
    }
}

struct RubricaGrupoConfig: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var orden: Int

    static func porDefecto(count: Int = 4) -> [RubricaGrupoConfig] {
        (1...count).map { RubricaGrupoConfig(id: "grupo_\($0)", nombre: "Grupo \($0)", orden: $0) }
    }
}

struct RubricaTemplate: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var asignatura: String
    var curso: String
    var unidadId: String?
    var unidadNombre: String?
    var usaPonderaciones: Bool?
    var metadatosCurriculares: ListaCotejoMetadatos?
    var gruposConfig: [RubricaGrupoConfig]?
    var partes: [RubricaParte]
    var puntajeMaximo: Double

    var fechaActualizacion: Date? = nil

    private enum CodingKeys: String, CodingKey {
        case id, nombre, asignatura, curso, unidadId, unidadNombre, usaPonderaciones
        case metadatosCurriculares, gruposConfig, partes, puntajeMaximo
    }

    var criteriosTotales: [CriterioRubrica] {
        partes.flatMap(\.criterios)
    }

    mutating func normalizar() {
        nombre = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        partes = partes
            .sorted { $0.orden < $1.orden }
            .enumerated()
            .map { index, parte in
                var next = parte
                next.orden = index + 1
                next.criterios = parte.criterios
                    .sorted { $0.orden < $1.orden }
                    .enumerated()
                    .map { critIndex, criterio in
                        var nextCrit = criterio
                        nextCrit.orden = critIndex + 1
                        return nextCrit
                    }
                return next
            }
        puntajeMaximo = Self.calcularPuntajeMaximo(partes: partes)
    }

    static func calcularPuntajeMaximo(partes: [RubricaParte]) -> Double {
        partes.reduce(0) { total, parte in
            total + parte.criterios.reduce(0) { $0 + 4 * ($1.ponderacion ?? 1) }
        }
    }

    func calcularPuntaje(puntajes: [String: Double]) -> Double {
        partes.reduce(0) { total, parte in
            total + parte.criterios.reduce(0) { acc, criterio in
                acc + (puntajes[criterio.id] ?? 0) * (criterio.ponderacion ?? 1)
            }
        }
    }

    static func nueva(asignatura: String, curso: String) -> RubricaTemplate {
        RubricaTemplate(
            id: EvaluacionesIDs.buildRubricaId(asignatura: asignatura, curso: curso),
            nombre: "",
            asignatura: asignatura,
            curso: curso,
            metadatosCurriculares: .vacios,
            gruposConfig: RubricaGrupoConfig.porDefecto(),
            partes: [.nueva(numero: 1)],
            puntajeMaximo: 4
        )
    }
}

struct EstudianteRubrica: Codable, Identifiable, Hashable {
    var estudianteId: String
    var nombre: String
    var hasPie: Bool
    var puntajes: [String: Double]
    var observaciones: String
    var nota: Double?
    var completado: Bool

    var id: String { estudianteId }

    mutating func recalcular(con rubrica: RubricaTemplate) {
        let puntaje = rubrica.calcularPuntaje(puntajes: puntajes)
        nota = NotaChilena.calcular(puntaje: puntaje, puntajeMaximo: rubrica.puntajeMaximo, exigencia: hasPie ? 0.5 : 0.6)
        completado = puntajes.count == rubrica.criteriosTotales.count && !rubrica.criteriosTotales.isEmpty
    }

    static func desde(estudiante: EstudiantePerfil) -> EstudianteRubrica {
        EstudianteRubrica(
            estudianteId: estudiante.id,
            nombre: estudiante.nombre,
            hasPie: estudiante.pie,
            puntajes: [:],
            observaciones: "",
            completado: false
        )
    }
}

struct GrupoRubrica: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String
    var estudiantes: [EstudianteRubrica]

    var esAusentes: Bool {
        nombre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ausentes"
    }
}

struct EvaluacionRubrica: Codable, Identifiable, Hashable {
    var id: String
    var rubricaId: String
    var rubricaNombre: String
    var asignatura: String
    var curso: String
    var grupos: [GrupoRubrica]
    var puntajeMaximo: Double
    var bloqueada: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, rubricaId, rubricaNombre, asignatura, curso, grupos, puntajeMaximo, bloqueada
    }

    var todosLosEstudiantes: [EstudianteRubrica] {
        grupos.flatMap(\.estudiantes)
    }

    var estudiantesAusentes: [EstudianteRubrica] {
        grupos.first(where: \.esAusentes)?.estudiantes ?? []
    }

    static func nueva(rubrica: RubricaTemplate) -> EvaluacionRubrica {
        let grupos = (rubrica.gruposConfig ?? RubricaGrupoConfig.porDefecto())
            .sorted { $0.orden < $1.orden }
            .map { GrupoRubrica(id: $0.id, nombre: $0.nombre, estudiantes: []) }
        return EvaluacionRubrica(
            id: EvaluacionesIDs.buildRubricaEvaluacionId(rubricaId: rubrica.id),
            rubricaId: rubrica.id,
            rubricaNombre: rubrica.nombre,
            asignatura: rubrica.asignatura,
            curso: rubrica.curso,
            grupos: grupos,
            puntajeMaximo: rubrica.puntajeMaximo
        )
    }

    mutating func sincronizarEstudiantes(_ alumnos: [EstudiantePerfil], rubrica: RubricaTemplate) {
        let porId = Dictionary(alumnos.map { ($0.id, $0) }) { first, _ in first }
        let porNombre = Dictionary(alumnos.map { (EvaluacionesIDs.normalizeName($0.nombre), $0) }) { first, _ in first }

        if grupos.isEmpty {
            grupos = [GrupoRubrica(id: "grupo_1", nombre: "Grupo 1", estudiantes: [])]
        }

        for grupoIndex in grupos.indices {
            for estIndex in grupos[grupoIndex].estudiantes.indices {
                var est = grupos[grupoIndex].estudiantes[estIndex]
                if let alumno = porId[est.estudianteId] ?? porNombre[EvaluacionesIDs.normalizeName(est.nombre)] {
                    est.estudianteId = alumno.id
                    est.nombre = alumno.nombre
                    est.hasPie = alumno.pie
                }
                est.recalcular(con: rubrica)
                grupos[grupoIndex].estudiantes[estIndex] = est
            }
        }

        let asignados = Set(grupos.flatMap { $0.estudiantes.map(\.estudianteId) })
        let nuevos = alumnos.filter { !asignados.contains($0.id) }
        if !nuevos.isEmpty {
            var agregados = nuevos.map(EstudianteRubrica.desde)
            for index in agregados.indices {
                agregados[index].recalcular(con: rubrica)
            }
            grupos[0].estudiantes.append(contentsOf: agregados)
        }
        puntajeMaximo = rubrica.puntajeMaximo
    }
}

// MARK: - Niveles de la rúbrica (UI)

enum NivelRubrica: Double, CaseIterable, Identifiable {
    case logrado = 4
    case casiLogrado = 3
    case parcialmenteLogrado = 2
    case porLograr = 1

    var id: Double { rawValue }

    var etiqueta: String {
        switch self {
        case .logrado: return "L"
        case .casiLogrado: return "CL"
        case .parcialmenteLogrado: return "PL"
        case .porLograr: return "PL*"
        }
    }

    var titulo: String {
        switch self {
        case .logrado: return "Logrado"
        case .casiLogrado: return "Casi logrado"
        case .parcialmenteLogrado: return "Parcialmente logrado"
        case .porLograr: return "Por lograr"
        }
    }

    func descripcion(en criterio: CriterioRubrica) -> String {
        switch self {
        case .logrado: return criterio.niveles.logrado.descripcion
        case .casiLogrado: return criterio.niveles.casiLogrado.descripcion
        case .parcialmenteLogrado: return criterio.niveles.parcialmenteLogrado.descripcion
        case .porLograr: return criterio.niveles.porLograr.descripcion
        }
    }
}

// MARK: - Helpers compartidos

enum NotaChilena {
    static func calcular(puntaje: Double, puntajeMaximo: Double, exigencia: Double = 0.6) -> Double {
        guard puntajeMaximo > 0 else { return 1.0 }
        let porcentaje = min(1, max(0, puntaje / puntajeMaximo))
        let exigenciaNormalizada = min(0.95, max(0.05, exigencia))
        let nota: Double
        if porcentaje < exigenciaNormalizada {
            nota = 1 + (3 * porcentaje) / exigenciaNormalizada
        } else {
            nota = 4 + (3 * (porcentaje - exigenciaNormalizada)) / (1 - exigenciaNormalizada)
        }
        return (min(7, max(1, nota)) * 10).rounded() / 10
    }

    static func formato(_ nota: Double?) -> String {
        guard let nota else { return "—" }
        return String(format: "%.1f", nota)
    }
}

enum EvaluacionesIDs {
    static func slug(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }

    static func uid(prefix: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = String(UUID().uuidString.prefix(5)).lowercased()
        return "\(prefix)_\(timestamp)_\(random)"
    }

    static func normalizeName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "es_CL"))
    }

    static func buildListaCotejoId(asignatura: String, curso: String) -> String {
        "lista_\(slug(asignatura))_\(slug(curso))_\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    static func buildListaEvaluacionId(listaId: String) -> String {
        "eval_\(listaId)"
    }

    static func buildRubricaId(asignatura: String, curso: String) -> String {
        "rubrica_\(slug(asignatura))_\(slug(curso))_\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    static func buildRubricaEvaluacionId(rubricaId: String) -> String {
        "eval_\(rubricaId)"
    }
}
