import Foundation
import FirebaseFirestore

// MARK: - Modelos curriculares (colección global `curriculo`)

struct OACurricular: Codable, Hashable {
    var id: String
    var tipo: String?
    var numero: Int
    var descripcion: String
    var indicadores: [String]?
}

struct UnidadCurricular: Codable, Hashable, Identifiable {
    var id: String
    var numeroUnidad: Int
    var nombreUnidad: String
    var proposito: String?
    var conocimientos: [String]?
    var habilidades: [String]?
    var actitudes: [String]?
    var conocimientosPrevios: [String]?
    var objetivosAprendizaje: [OACurricular]?

    enum CodingKeys: String, CodingKey {
        case id
        case numeroUnidad = "numero_unidad"
        case nombreUnidad = "nombre_unidad"
        case proposito
        case conocimientos
        case habilidades
        case actitudes
        case conocimientosPrevios = "conocimientos_previos"
        case objetivosAprendizaje = "objetivos_aprendizaje"
    }
}

// MARK: - Repositorio del currículum oficial

/// Lee la colección GLOBAL `curriculo/{docId}/unidades/...` (no vive bajo users/{uid}).
/// Cachea en memoria porque son datos de referencia que casi no cambian.
actor CurriculoRepository {
    private let db: Firestore
    private var unidadesCache: [String: [UnidadCurricular]] = [:]
    private var unidadCache: [String: UnidadCurricular] = [:]

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func getUnidades(asignatura: String, nivel: String) async throws -> [UnidadCurricular] {
        let docId = PlanificacionRepository.buildDocId(asignatura: asignatura, nivel: nivel)
        if let cached = unidadesCache[docId] { return cached }

        let ref = db.collection("curriculo").document(docId).collection("unidades")
        let snapshot = try await getDocuments(ref.order(by: "numero_unidad"))
        let unidades = snapshot.documents.compactMap { doc -> UnidadCurricular? in
            var dict = doc.data()
            dict["id"] = doc.documentID
            return UnidadCurricular.from(dictionary: dict)
        }
        unidadesCache[docId] = unidades
        return unidades
    }

    func getNivelesDisponibles(asignatura: String) async throws -> [String] {
        let snapshot = try await getDocuments(db.collection("curriculo"))
        let levels = AcademicContract.officialLevels.filter { level in
            let expectedID = PlanificacionRepository.buildDocId(asignatura: asignatura, nivel: level)
            return snapshot.documents.contains { document in
                guard document.documentID == expectedID else { return false }
                let data = document.data()
                return data["ready"] as? Bool != false
            }
        }
        return levels
    }

    func getUnidadCompleta(asignatura: String, nivel: String, unidadId: String) async throws -> UnidadCurricular? {
        let docId = PlanificacionRepository.buildDocId(asignatura: asignatura, nivel: nivel)
        let cacheKey = "\(docId):\(unidadId)"
        if let cached = unidadCache[cacheKey] { return cached }

        let unidadRef = db.collection("curriculo").document(docId).collection("unidades").document(unidadId)
        let unidadSnap = try await getDocument(unidadRef)
        guard unidadSnap.exists, var dict = unidadSnap.data() else { return nil }
        dict["id"] = unidadSnap.documentID

        let oaRef = unidadRef.collection("objetivos_aprendizaje")
        let oaSnap = try await getDocuments(oaRef.order(by: "numero"))
        if !oaSnap.documents.isEmpty {
            dict["objetivos_aprendizaje"] = oaSnap.documents.map { oaDoc -> [String: Any] in
                var oaDict = oaDoc.data()
                oaDict["id"] = oaDoc.documentID
                return oaDict
            }
        }

        guard let unidad = UnidadCurricular.from(dictionary: dict) else { return nil }
        unidadCache[cacheKey] = unidad
        return unidad
    }

    // MARK: - Firestore helpers

    private func getDocument(_ ref: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            ref.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: DashboardRepositoryError.missingUser)
                }
            }
        }
    }

    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: DashboardRepositoryError.missingUser)
                }
            }
        }
    }
}

// MARK: - OAs editables: inicialización y merge (puerto de lib/curriculo.ts)

enum CurriculoOA {
    /// OAs base oficiales de una unidad, todos seleccionados por defecto.
    static func initOAs(unidad: UnidadCurricular, asignatura: String) -> [OAEditado] {
        (unidad.objetivosAprendizaje ?? []).map { oa in
            OAEditado(
                id: "OA\(oa.numero)",
                numero: oa.numero,
                tipo: (oa.tipo ?? "").uppercased() == "OAT" ? "oat" : "oa",
                descripcion: oa.descripcion,
                seleccionado: true,
                indicadores: (oa.indicadores ?? []).enumerated().map { index, texto in
                    IndicadorEditado(id: "OA\(oa.numero)_IND\(index)", texto: texto, seleccionado: true, esPropio: false)
                },
                esPropio: false,
                tags: [asignatura]
            )
        }
    }

    /// Merge: base oficial ← overrides guardados ← edits propios, preservando huérfanos como propios.
    static func mergeOAs(base: [OAEditado], saved: [OAEditado]) -> [OAEditado] {
        let baseIds = Set(base.map(canonicalOAKey))
        let savedById = Dictionary(saved.map { (canonicalOAKey($0), $0) }) { first, _ in first }

        let mergedBase: [OAEditado] = base.map { oa in
            guard let existing = savedById[canonicalOAKey(oa)] else { return oa }
            var next = oa
            next.descripcion = existing.descripcion.isEmpty ? oa.descripcion : existing.descripcion
            next.seleccionado = existing.seleccionado
            let oficialesActualizados = oa.indicadores.map { ind in
                existing.indicadores.first {
                    canonicalPedagogicalKey($0.id) == canonicalPedagogicalKey(ind.id)
                } ?? ind
            }
            let propios = existing.indicadores.filter { $0.esPropio == true }
            next.indicadores = oficialesActualizados + propios
            return next
        }

        let huerfanos: [OAEditado] = saved
            .filter { !baseIds.contains(canonicalOAKey($0)) }
            .map { oa in
                var next = oa
                next.esPropio = true
                return next
            }

        var vistos = Set<String>()
        return (mergedBase + huerfanos).filter { oa in
            let key = canonicalOAKey(oa)
            guard !vistos.contains(key) else { return false }
            vistos.insert(key)
            return true
        }
    }

    private static func canonicalOAKey(_ oa: OAEditado) -> String {
        if let number = oa.numero {
            return "oa\(number)"
        }
        return canonicalPedagogicalKey(oa.id)
    }

    private static func canonicalPedagogicalKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    static func nuevoOAPropio(numero: Int?, tipo: String, descripcion: String, asignatura: String) -> OAEditado {
        OAEditado(
            id: EvaluacionesIDs.uid(prefix: "PROP"),
            numero: numero,
            tipo: tipo,
            descripcion: descripcion,
            seleccionado: true,
            indicadores: [],
            esPropio: true,
            tags: [asignatura]
        )
    }

    static func nuevoIndicadorPropio(oaId: String, texto: String) -> IndicadorEditado {
        IndicadorEditado(id: "\(oaId)_IND_\(EvaluacionesIDs.uid(prefix: "p"))", texto: texto, seleccionado: true, esPropio: true)
    }
}

// MARK: - Resolución de nivel curricular (curso → nivel)

enum CurriculoNivel {
    static func resolver(
        curso: String,
        asignatura: String? = nil,
        catalogLevel: String? = nil,
        mapping: [String: String],
        subjectMapping: [String: [String: String]] = [:]
    ) -> String? {
        let limpio = curso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return nil }

        if let asignatura = asignatura?.trimmingCharacters(in: .whitespacesAndNewlines),
           !asignatura.isEmpty {
            let courseKeys = subjectMapping.keys.filter { key in
                subjectMapping[key]?.contains(where: {
                    $0.key.localizedCaseInsensitiveCompare(asignatura) == .orderedSame &&
                    !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }) == true
            }
            if let key = resolveCourseKey(limpio, keys: courseKeys),
               let subjects = subjectMapping[key],
               let level = subjects.first(where: {
                   $0.key.localizedCaseInsensitiveCompare(asignatura) == .orderedSame
               })?.value.trimmingCharacters(in: .whitespacesAndNewlines),
               !level.isEmpty {
                return level
            }
        }

        if let catalogLevel = catalogLevel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !catalogLevel.isEmpty {
            return catalogLevel
        }

        if let directo = mapping[limpio], !directo.isEmpty { return directo }

        if let key = resolveCourseKey(limpio, keys: Array(mapping.keys)),
           let nivel = mapping[key], !nivel.isEmpty {
            return nivel
        }

        return inferirDesdeNombreCurso(limpio)
    }

    private static func resolveCourseKey(_ course: String, keys: [String]) -> String? {
        if let exact = keys.first(where: {
            $0.localizedCaseInsensitiveCompare(course) == .orderedSame
        }) {
            return exact
        }
        if let prefix = keys.first(where: {
            course.localizedCaseInsensitiveContains($0) ||
            $0.localizedCaseInsensitiveContains(course)
        }) {
            return prefix
        }
        if let courseGrade = grado(de: course) {
            return keys.first { grado(de: $0) == courseGrade }
        }
        return nil
    }

    private static func inferirDesdeNombreCurso(_ course: String) -> String? {
        let folded = course.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "es_CL")
        ).lowercased()
        guard let gradeText = folded.firstMatch(of: /\d+/).map({ String($0.output) }),
              let grade = Int(gradeText) else {
            return nil
        }

        if folded.contains("medio"), (1...4).contains(grade) {
            return ["1ro", "2do", "3ro", "4to"][grade - 1] + " Medio"
        }
        if (1...8).contains(grade) {
            return ["1ro", "2do", "3ro", "4to", "5to", "6to", "7mo", "8vo"][grade - 1] + " Básico"
        }
        return nil
    }

    private static func grado(de valor: String) -> String? {
        let scalars = valor.unicodeScalars
        var digitos = ""
        for scalar in scalars where CharacterSet.decimalDigits.contains(scalar) {
            digitos.unicodeScalars.append(scalar)
        }
        return digitos.isEmpty ? nil : digitos
    }
}
