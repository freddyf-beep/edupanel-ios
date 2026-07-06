import Foundation
import FirebaseAuth
import FirebaseFirestore

struct PlanificacionRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private func getUid() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DashboardRepositoryError.missingUser
        }
        return uid
    }

    private func userDoc(col: String, id: String) throws -> DocumentReference {
        let uid = try getUid()
        return db.collection("users").document(uid).collection(col).document(id)
    }

    private func userCol(col: String) throws -> CollectionReference {
        let uid = try getUid()
        return db.collection("users").document(uid).collection(col)
    }

    // MARK: - sluggifiers
    static func buildDocId(asignatura: String, nivel: String) -> String {
        let combined = "\(asignatura)_\(nivel)"
        return combined.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }

    static func buildPlanCursoId(asignatura: String, curso: String) -> String {
        let combined = "plan_\(asignatura)_\(curso)"
        return combined.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }

    static func buildVerUnidadId(asignatura: String, curso: String, unidadId: String) -> String {
        return buildDocId(asignatura: asignatura, nivel: curso) + "_" + unidadId
    }

    static func buildCronogramaUnidadId(asignatura: String, curso: String, unidadId: String) -> String {
        return buildDocId(asignatura: asignatura, nivel: curso) + "_crono_" + unidadId
    }

    static func cronogramaKey(curso: String, unidadId: String) -> String {
        "\(curso)::\(unidadId)"
    }

    static func cronogramaKey(asignatura: String, curso: String, unidadId: String) -> String {
        "\(asignatura)::\(curso)::\(unidadId)"
    }

    static func unidadIdFromIndex(_ index: Int) -> String {
        "unidad_\(index + 1)"
    }

    static func unidadIdCandidates(unit: UnidadPlan, index: Int? = nil) -> [String] {
        var ids: [String] = [
            String(unit.id),
            "unidad_\(unit.id)"
        ]

        if let unidadCurricularId = unit.unidadCurricularId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !unidadCurricularId.isEmpty {
            ids.append(unidadCurricularId)
        }

        if let index {
            ids.append(unidadIdFromIndex(index))
        }

        return uniqueNonEmpty(ids)
    }

    static func unidadIdCandidates(raw unidadId: String) -> [String] {
        let clean = unidadId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        let numeric = clean.replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
        var ids = [clean]
        if !numeric.isEmpty {
            ids.append(numeric)
            ids.append("unidad_\(numeric)")
        }
        return uniqueNonEmpty(ids)
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    static func buildActividadClaseId(curso: String, unidadId: String, numeroClase: Int, asignatura: String) -> String {
        return buildDocId(asignatura: asignatura, nivel: curso) + "_" + unidadId + "_clase\(numeroClase)"
    }

    // MARK: - Database Actions

    func listarPlanesCurso(asignatura: String) async throws -> [PlanificacionCurso] {
        let colRef = try userCol(col: "planificaciones_curso")
        return try await withCheckedThrowingContinuation { continuation in
            colRef.whereField("asignatura", isEqualTo: asignatura).getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    let results = snapshot.documents.compactMap { doc -> PlanificacionCurso? in
                        let dict = doc.data()
                        return PlanificacionCurso.fromFirestore(dict, fallbackAsignatura: asignatura)
                    }
                    continuation.resume(returning: results)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func listarTodosPlanesCurso(posiblesCursos: [String] = [], posiblesAsignaturas: [String] = []) async throws -> [PlanificacionCurso] {
        let colRef = try userCol(col: "planificaciones_curso")
        return try await withCheckedThrowingContinuation { continuation in
            colRef.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    let results = snapshot.documents.compactMap { doc -> PlanificacionCurso? in
                        let dict = doc.data()
                        let docId = doc.documentID
                        
                        var fallbackCurso: String? = nil
                        var fallbackAsignatura: String? = nil
                        
                        for asignatura in posiblesAsignaturas {
                            for curso in posiblesCursos {
                                let expectedId = Self.buildPlanCursoId(asignatura: asignatura, curso: curso)
                                if expectedId == docId {
                                    fallbackCurso = curso
                                    fallbackAsignatura = asignatura
                                    break
                                }
                            }
                            if fallbackCurso != nil { break }
                        }
                        
                        if fallbackCurso == nil && docId.hasPrefix("plan_") {
                            let cleanId = String(docId.dropFirst(5))
                            for asignatura in posiblesAsignaturas {
                                let slugAsig = asignatura.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
                                    .lowercased()
                                    .replacingOccurrences(of: " ", with: "_")
                                    .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
                                if cleanId.hasPrefix(slugAsig + "_") {
                                    fallbackAsignatura = asignatura
                                    let slugCursoPart = String(cleanId.dropFirst(slugAsig.count + 1))
                                    for curso in posiblesCursos {
                                        let slugCurso = curso.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
                                            .lowercased()
                                            .replacingOccurrences(of: " ", with: "_")
                                            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
                                        if slugCurso == slugCursoPart {
                                            fallbackCurso = curso
                                            break
                                        }
                                    }
                                    break
                                }
                            }
                        }
                        
                        return PlanificacionCurso.fromFirestore(dict, fallbackCurso: fallbackCurso, fallbackAsignatura: fallbackAsignatura)
                    }
                    continuation.resume(returning: results)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func cargarPlanCurso(asignatura: String, curso: String) async throws -> PlanificacionCurso? {
        let docId = Self.buildPlanCursoId(asignatura: asignatura, curso: curso)
        let docRef = try userDoc(col: "planificaciones_curso", id: docId)
        let snapshot = try await getDocument(docRef)
        guard snapshot.exists, let dict = snapshot.data() else {
            return nil
        }
        return PlanificacionCurso.fromFirestore(dict, fallbackCurso: curso, fallbackAsignatura: asignatura)
    }

    func guardarPlanCurso(asignatura: String, curso: String, units: [UnidadPlan]) async throws {
        let docId = Self.buildPlanCursoId(asignatura: asignatura, curso: curso)
        let docRef = try userDoc(col: "planificaciones_curso", id: docId)
        let plan = PlanificacionCurso(curso: curso, asignatura: asignatura, units: units)
        guard var dict = plan.dictionary else {
            throw NSError(domain: "PlanificacionRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }
        dict["updatedAt"] = FieldValue.serverTimestamp()
        try await setData(dict, at: docRef, merge: false)
    }

    func cargarVerUnidad(asignatura: String, curso: String, unidadId: String) async throws -> VerUnidadGuardada? {
        let docId = Self.buildVerUnidadId(asignatura: asignatura, curso: curso, unidadId: unidadId)
        let docRef = try userDoc(col: "ver_unidad", id: docId)
        let snapshot = try await getDocument(docRef)
        guard snapshot.exists, let dict = snapshot.data() else {
            return nil
        }
        return VerUnidadGuardada.from(dictionary: dict)
    }

    func cargarVerUnidadesCurso(asignatura: String, curso: String) async throws -> [String: VerUnidadGuardada] {
        let query = try userCol(col: "ver_unidad")
            .whereField("asignatura", isEqualTo: asignatura)
            .whereField("curso", isEqualTo: curso)
        let snapshot = try await getDocuments(query)

        var result: [String: VerUnidadGuardada] = [:]
        for doc in snapshot.documents {
            guard let data = VerUnidadGuardada.from(dictionary: doc.data()) else { continue }
            let unidadId = data.unidadId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !unidadId.isEmpty else { continue }
            result[unidadId] = data
        }
        return result
    }

    func cargarVerUnidadConFallback(asignatura: String, curso: String, unidadId: String) async throws -> VerUnidadGuardada? {
        let candidates = Self.unidadIdCandidates(raw: unidadId)
        for candidate in candidates {
            if let data = try await cargarVerUnidad(asignatura: asignatura, curso: curso, unidadId: candidate) {
                var resolved = data
                if resolved.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolved.unidadId = candidate
                }
                return resolved
            }
        }

        for candidate in candidates {
            if let data = try? await buscarVerUnidadPorCampos(asignatura: asignatura, curso: curso, unidadId: candidate) {
                var resolved = data
                if resolved.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolved.unidadId = candidate
                }
                return resolved
            }
        }
        return nil
    }

    private func buscarVerUnidadPorCampos(asignatura: String, curso: String, unidadId: String) async throws -> VerUnidadGuardada? {
        let query = try userCol(col: "ver_unidad")
            .whereField("asignatura", isEqualTo: asignatura)
            .whereField("curso", isEqualTo: curso)
            .whereField("unidadId", isEqualTo: unidadId)
            .limit(to: 1)
        guard let snapshot = try await getFirstDocument(query), let dict = snapshot.data() else {
            return nil
        }
        return VerUnidadGuardada.from(dictionary: dict)
    }

    func guardarVerUnidad(asignatura: String, curso: String, unidadId: String, data: VerUnidadGuardada) async throws {
        let docId = Self.buildVerUnidadId(asignatura: asignatura, curso: curso, unidadId: unidadId)
        let docRef = try userDoc(col: "ver_unidad", id: docId)
        guard var dict = data.dictionary else {
            throw NSError(domain: "PlanificacionRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }
        dict["updatedAt"] = FieldValue.serverTimestamp()
        try await setData(dict, at: docRef, merge: true)
    }

    func cargarCronogramaUnidad(asignatura: String, curso: String, unidadId: String) async throws -> CronogramaUnidadData? {
        let docId = Self.buildCronogramaUnidadId(asignatura: asignatura, curso: curso, unidadId: unidadId)
        let docRef = try userDoc(col: "cronograma_unidad", id: docId)
        let snapshot = try await getDocument(docRef)
        guard snapshot.exists, let dict = snapshot.data() else {
            return nil
        }
        return CronogramaUnidadData.from(dictionary: dict)
    }

    func cargarCronogramaUnidadConFallback(asignatura: String, curso: String, unidadIds: [String]) async throws -> CronogramaUnidadData? {
        let candidates = Self.uniqueNonEmpty(unidadIds.flatMap { Self.unidadIdCandidates(raw: $0) })
        for candidate in candidates {
            if let data = try await cargarCronogramaUnidad(asignatura: asignatura, curso: curso, unidadId: candidate) {
                var resolved = data
                if resolved.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolved.unidadId = candidate
                }
                return resolved
            }
        }

        for candidate in candidates {
            if let data = try? await buscarCronogramaUnidadPorCampos(asignatura: asignatura, curso: curso, unidadId: candidate) {
                var resolved = data
                if resolved.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolved.unidadId = candidate
                }
                return resolved
            }
        }
        return nil
    }

    private func buscarCronogramaUnidadPorCampos(asignatura: String, curso: String, unidadId: String) async throws -> CronogramaUnidadData? {
        let query = try userCol(col: "cronograma_unidad")
            .whereField("asignatura", isEqualTo: asignatura)
            .whereField("curso", isEqualTo: curso)
            .whereField("unidadId", isEqualTo: unidadId)
            .limit(to: 1)
        guard let snapshot = try await getFirstDocument(query), let dict = snapshot.data() else {
            return nil
        }
        return CronogramaUnidadData.from(dictionary: dict)
    }

    func cargarCronogramas(asignatura: String, planes: [PlanificacionCurso]) async -> [String: CronogramaUnidadData] {
        var results: [String: CronogramaUnidadData] = [:]

        for plan in planes {
            for (index, unit) in plan.units.enumerated() {
                let canonicalId = String(unit.id)
                let candidates = Self.unidadIdCandidates(unit: unit, index: index)
                if let crono = try? await cargarCronogramaUnidadConFallback(asignatura: asignatura, curso: plan.curso, unidadIds: candidates) {
                    results[Self.cronogramaKey(asignatura: asignatura, curso: plan.curso, unidadId: canonicalId)] = crono
                    results[Self.cronogramaKey(curso: plan.curso, unidadId: canonicalId)] = crono
                }
            }
        }

        return results
    }

    func guardarCronogramaUnidad(asignatura: String, curso: String, unidadId: String, totalClases: Int, clases: [ClaseCronograma]) async throws {
        let docId = Self.buildCronogramaUnidadId(asignatura: asignatura, curso: curso, unidadId: unidadId)
        let docRef = try userDoc(col: "cronograma_unidad", id: docId)
        let data = CronogramaUnidadData(asignatura: asignatura, curso: curso, unidadId: unidadId, totalClases: totalClases, clases: clases)
        guard var dict = data.dictionary else {
            throw NSError(domain: "PlanificacionRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }
        dict["updatedAt"] = FieldValue.serverTimestamp()
        try await setData(dict, at: docRef, merge: false)
    }

    func cargarActividadClase(curso: String, unidadId: String, numeroClase: Int, asignatura: String) async throws -> ActividadClase? {
        let docId = Self.buildActividadClaseId(curso: curso, unidadId: unidadId, numeroClase: numeroClase, asignatura: asignatura)
        let docRef = try userDoc(col: "actividades_clase", id: docId)
        let snapshot = try await getDocument(docRef)
        guard snapshot.exists, let dict = snapshot.data() else {
            return nil
        }
        return ActividadClase.from(dictionary: dict)
    }

    func cargarActividadClaseConFallback(curso: String, unidadId: String, numeroClase: Int, asignatura: String) async throws -> ActividadClase? {
        let candidates = Self.unidadIdCandidates(raw: unidadId)
        for candidate in candidates {
            if let data = try await cargarActividadClase(curso: curso, unidadId: candidate, numeroClase: numeroClase, asignatura: asignatura) {
                var resolved = data
                if resolved.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolved.unidadId = candidate
                }
                return resolved
            }
        }

        for candidate in candidates {
            if let data = try? await buscarActividadClasePorCampos(curso: curso, unidadId: candidate, numeroClase: numeroClase, asignatura: asignatura) {
                var resolved = data
                if resolved.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolved.unidadId = candidate
                }
                return resolved
            }
        }
        return nil
    }

    private func buscarActividadClasePorCampos(curso: String, unidadId: String, numeroClase: Int, asignatura: String) async throws -> ActividadClase? {
        let query = try userCol(col: "actividades_clase")
            .whereField("asignatura", isEqualTo: asignatura)
            .whereField("curso", isEqualTo: curso)
            .whereField("unidadId", isEqualTo: unidadId)
            .whereField("numeroClase", isEqualTo: numeroClase)
            .limit(to: 1)
        guard let snapshot = try await getFirstDocument(query), let dict = snapshot.data() else {
            return nil
        }
        return ActividadClase.from(dictionary: dict)
    }

    func guardarActividadClase(data: ActividadClase) async throws {
        let docId = Self.buildActividadClaseId(curso: data.curso, unidadId: data.unidadId, numeroClase: data.numeroClase, asignatura: data.asignatura)
        let docRef = try userDoc(col: "actividades_clase", id: docId)
        guard var dict = data.dictionary else {
            throw NSError(domain: "PlanificacionRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }
        // Filter out NSNull values to preserve Firestore schema cleanliness
        dict = dict.filter { !($1 is NSNull) }
        dict["updatedAt"] = FieldValue.serverTimestamp()
        try await setData(dict, at: docRef, merge: true)
    }

    func eliminarUnidadCompleta(asignatura: String, curso: String, unidadId: String) async throws {
        let verUnidadId = Self.buildVerUnidadId(asignatura: asignatura, curso: curso, unidadId: unidadId)
        let cronogramaId = Self.buildCronogramaUnidadId(asignatura: asignatura, curso: curso, unidadId: unidadId)
        
        let verUnidadRef = try userDoc(col: "ver_unidad", id: verUnidadId)
        let cronogramaRef = try userDoc(col: "cronograma_unidad", id: cronogramaId)
        
        let crono = try? await cargarCronogramaUnidad(asignatura: asignatura, curso: curso, unidadId: unidadId)
        let totalClases = max(crono?.totalClases ?? 0, crono?.clases.count ?? 0)
        
        try await deleteDocument(verUnidadRef)
        try await deleteDocument(cronogramaRef)
        
        let count = max(totalClases, 30)
        for n in 1...count {
            let actId = Self.buildActividadClaseId(curso: curso, unidadId: unidadId, numeroClase: n, asignatura: asignatura)
            if let actRef = try? userDoc(col: "actividades_clase", id: actId) {
                try? await deleteDocument(actRef)
            }
        }
    }

    // MARK: - Firestore Helpers

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

    private func getFirstDocument(_ query: Query) async throws -> DocumentSnapshot? {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: snapshot?.documents.first)
                }
            }
        }
    }

    private func setData(_ data: [String: Any], at ref: DocumentReference, merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func deleteDocument(_ ref: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// MARK: - Decodable/Encodable Extensions for Firestore [String: Any]
extension Decodable {
    static func from(dictionary: [String: Any]) -> Self? {
        do {
            let sanitized = FirestoreJSON.sanitize(dictionary)
            let data = try JSONSerialization.data(withJSONObject: sanitized, options: [])
            let decoder = JSONDecoder()
            return try decoder.decode(Self.self, from: data)
        } catch {
            print("Firestore Decodable Error on \(Self.self): \(error)")
            return nil
        }
    }
}

private enum FirestoreJSON {
    static func sanitize(_ dictionary: [String: Any]) -> [String: Any] {
        dictionary.reduce(into: [:]) { partialResult, element in
            if let value = sanitize(element.value) {
                partialResult[element.key] = value
            }
        }
    }

    private static func sanitize(_ value: Any) -> Any? {
        switch value {
        case let value as String:
            return value
        case let value as Bool:
            return value
        case let value as Int:
            return value
        case let value as Int64:
            return value
        case let value as Int32:
            return value
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as NSNumber:
            return value
        case _ as NSNull:
            return NSNull()
        case let value as [String: Any]:
            return sanitize(value)
        case let value as [Any]:
            return value.compactMap { sanitize($0) }
        default:
            return nil
        }
    }
}

extension Encodable {
    var dictionary: [String: Any]? {
        do {
            let data = try JSONEncoder().encode(self)
            let object = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            return object as? [String: Any]
        } catch {
            print("Firestore Encodable Error on \(Self.self): \(error)")
            return nil
        }
    }
}
