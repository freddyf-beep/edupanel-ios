import Foundation
import FirebaseAuth
import FirebaseFirestore

struct EvaluacionesRepository {
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

    // MARK: - Diagnóstico (temporal)

    func diagnostico() async throws -> EvaluacionesDiagnostico {
        let uid = (try? getUid()) ?? "—"
        let rubricasSnap = try await getDocuments(try userCol(col: "rubricas"))
        let listasSnap = try await getDocuments(try userCol(col: "listas_cotejo"))

        func cursos(_ snap: QuerySnapshot) -> [String] {
            Array(Set(snap.documents.compactMap { $0.data()["curso"] as? String })).sorted()
        }
        func asignaturas(_ snap: QuerySnapshot) -> [String] {
            Array(Set(snap.documents.compactMap { $0.data()["asignatura"] as? String })).sorted()
        }
        func decodificadas(_ snap: QuerySnapshot, _ tipo: DecodeTipo) -> Int {
            snap.documents.filter { doc in
                switch tipo {
                case .rubrica: return decode(RubricaTemplate.self, from: doc) != nil
                case .lista: return decode(ListaCotejoTemplate.self, from: doc) != nil
                }
            }.count
        }

        return EvaluacionesDiagnostico(
            uid: uid,
            totalRubricas: rubricasSnap.documents.count,
            rubricasDecodificadas: decodificadas(rubricasSnap, .rubrica),
            cursosRubricas: cursos(rubricasSnap),
            asignaturasRubricas: asignaturas(rubricasSnap),
            totalListas: listasSnap.documents.count,
            listasDecodificadas: decodificadas(listasSnap, .lista),
            cursosListas: cursos(listasSnap),
            asignaturasListas: asignaturas(listasSnap)
        )
    }

    private enum DecodeTipo { case rubrica, lista }

    // MARK: - Listas de Cotejo

    func cargarListasCotejo(asignatura: String?, curso: String) async throws -> [ListaCotejoTemplate] {
        let snapshot = try await getDocuments(try userCol(col: "listas_cotejo"))
        return snapshot.documents
            .compactMap { decode(ListaCotejoTemplate.self, from: $0) }
            .filter { $0.curso == curso && (asignatura == nil || $0.asignatura == asignatura) }
            .sorted { ($0.fechaActualizacion ?? .distantPast) > ($1.fechaActualizacion ?? .distantPast) }
    }

    func cargarListaCotejo(id: String) async throws -> ListaCotejoTemplate? {
        let snapshot = try await getDocument(try userDoc(col: "listas_cotejo", id: id))
        guard snapshot.exists else { return nil }
        return decode(ListaCotejoTemplate.self, from: snapshot)
    }

    func guardarListaCotejo(_ lista: ListaCotejoTemplate) async throws {
        var normalizada = lista
        normalizada.normalizar()
        guard var dict = normalizada.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if lista.fechaActualizacion == nil {
            dict["createdAt"] = FieldValue.serverTimestamp()
        }
        try await setData(dict, at: try userDoc(col: "listas_cotejo", id: normalizada.id), merge: true)
    }

    func eliminarListaCotejo(id: String) async throws {
        try await deleteDocument(try userDoc(col: "listas_cotejo", id: id))
        let evalId = EvaluacionesIDs.buildListaEvaluacionId(listaId: id)
        try? await deleteDocument(try userDoc(col: "listas_cotejo_evaluaciones", id: evalId))
    }

    func cargarEvaluacionLista(listaId: String) async throws -> ListaCotejoEvaluacion? {
        let id = EvaluacionesIDs.buildListaEvaluacionId(listaId: listaId)
        let snapshot = try await getDocument(try userDoc(col: "listas_cotejo_evaluaciones", id: id))
        guard snapshot.exists else { return nil }
        return decode(ListaCotejoEvaluacion.self, from: snapshot)
    }

    func guardarEvaluacionLista(_ evaluacion: ListaCotejoEvaluacion) async throws {
        guard var dict = evaluacion.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if evaluacion.bloqueada == true {
            dict["bloqueadaEn"] = FieldValue.serverTimestamp()
        } else {
            dict["bloqueadaEn"] = FieldValue.delete()
        }
        try await setData(dict, at: try userDoc(col: "listas_cotejo_evaluaciones", id: evaluacion.id), merge: true)
    }

    // MARK: - Rúbricas

    func cargarRubricas(asignatura: String?, curso: String) async throws -> [RubricaTemplate] {
        let snapshot = try await getDocuments(try userCol(col: "rubricas"))
        return snapshot.documents
            .compactMap { decode(RubricaTemplate.self, from: $0) }
            .filter { $0.curso == curso && (asignatura == nil || $0.asignatura == asignatura) }
            .sorted { ($0.fechaActualizacion ?? .distantPast) > ($1.fechaActualizacion ?? .distantPast) }
    }

    func cargarRubrica(id: String) async throws -> RubricaTemplate? {
        let snapshot = try await getDocument(try userDoc(col: "rubricas", id: id))
        guard snapshot.exists else { return nil }
        return decode(RubricaTemplate.self, from: snapshot)
    }

    func guardarRubrica(_ rubrica: RubricaTemplate) async throws {
        var normalizada = rubrica
        normalizada.normalizar()
        guard var dict = normalizada.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if rubrica.fechaActualizacion == nil {
            dict["createdAt"] = FieldValue.serverTimestamp()
        }
        try await setData(dict, at: try userDoc(col: "rubricas", id: normalizada.id), merge: true)
    }

    func eliminarRubrica(id: String) async throws {
        try await deleteDocument(try userDoc(col: "rubricas", id: id))
        let evalId = EvaluacionesIDs.buildRubricaEvaluacionId(rubricaId: id)
        try? await deleteDocument(try userDoc(col: "rubricas_evaluaciones", id: evalId))
    }

    func cargarEvaluacionRubrica(rubricaId: String) async throws -> EvaluacionRubrica? {
        let id = EvaluacionesIDs.buildRubricaEvaluacionId(rubricaId: rubricaId)
        let snapshot = try await getDocument(try userDoc(col: "rubricas_evaluaciones", id: id))
        guard snapshot.exists else { return nil }
        return decode(EvaluacionRubrica.self, from: snapshot)
    }

    func guardarEvaluacionRubrica(_ evaluacion: EvaluacionRubrica) async throws {
        guard var dict = evaluacion.dictionary else {
            throw EvaluacionesRepositoryError.encoding
        }
        dict.removeValue(forKey: "id")
        dict["updatedAt"] = FieldValue.serverTimestamp()
        if evaluacion.bloqueada == true {
            dict["bloqueadaEn"] = FieldValue.serverTimestamp()
        } else {
            dict["bloqueadaEn"] = FieldValue.delete()
        }
        try await setData(dict, at: try userDoc(col: "rubricas_evaluaciones", id: evaluacion.id), merge: true)
    }

    // MARK: - Sincronización con Calificaciones

    func sincronizarRubricaConCalificaciones(
        rubrica: RubricaTemplate,
        evaluacion: EvaluacionRubrica,
        roster: [EstudiantePerfil],
        sobrescribir: Bool
    ) async throws -> SyncCalificacionesResultado {
        let evaluacionId = EvaluacionesIDs.buildRubricaEvaluacionId(rubricaId: rubrica.id)
        var notasCalculadas: [String: (nombre: String, nota: String)] = [:]
        var estudiantesSinNota = 0

        for est in evaluacion.todosLosEstudiantes {
            let tienePuntajes = !est.puntajes.isEmpty
            guard tienePuntajes || est.completado else {
                estudiantesSinNota += 1
                continue
            }
            let puntaje = rubrica.calcularPuntaje(puntajes: est.puntajes)
            let nota = NotaChilena.calcular(puntaje: puntaje, puntajeMaximo: rubrica.puntajeMaximo, exigencia: est.hasPie ? 0.5 : 0.6)
            notasCalculadas[est.estudianteId] = (est.nombre, String(format: "%.1f", nota))
        }

        return try await aplicarSincronizacion(
            asignatura: rubrica.asignatura,
            curso: rubrica.curso,
            evaluacionId: evaluacionId,
            label: rubrica.nombre.isEmpty ? (evaluacion.rubricaNombre.isEmpty ? "R\u{00FA}brica" : evaluacion.rubricaNombre) : rubrica.nombre,
            unidadId: rubrica.unidadId,
            oaIds: Self.oaIds(oas: rubrica.oas, refs: rubrica.partes.flatMap(\.oasVinculados)),
            notasCalculadas: notasCalculadas,
            estudiantesSinNota: estudiantesSinNota,
            roster: roster,
            sobrescribir: sobrescribir
        )
    }

    func sincronizarListaConCalificaciones(
        lista: ListaCotejoTemplate,
        evaluacion: ListaCotejoEvaluacion,
        roster: [EstudiantePerfil],
        sobrescribir: Bool
    ) async throws -> SyncCalificacionesResultado {
        let evaluacionId = EvaluacionesIDs.buildListaEvaluacionId(listaId: lista.id)
        var notasCalculadas: [String: (nombre: String, nota: String)] = [:]
        var estudiantesSinNota = 0

        for est in evaluacion.todosLosEstudiantes {
            let tieneRespuestas = !est.respuestas.isEmpty
            guard tieneRespuestas || est.completado else {
                estudiantesSinNota += 1
                continue
            }
            var temp = est
            temp.recalcular(con: lista)
            let nota = temp.nota ?? NotaChilena.calcular(puntaje: 0, puntajeMaximo: lista.puntajeMaximo, exigencia: est.hasPie ? 0.5 : 0.6)
            notasCalculadas[est.estudianteId] = (est.nombre, String(format: "%.1f", nota))
        }

        return try await aplicarSincronizacion(
            asignatura: lista.asignatura,
            curso: lista.curso,
            evaluacionId: evaluacionId,
            label: lista.nombre.isEmpty ? (evaluacion.listaNombre.isEmpty ? "Lista de cotejo" : evaluacion.listaNombre) : lista.nombre,
            unidadId: lista.unidadId,
            oaIds: Self.oaIds(oas: lista.oas, refs: lista.secciones.flatMap(\.oasVinculados)),
            notasCalculadas: notasCalculadas,
            estudiantesSinNota: estudiantesSinNota,
            roster: roster,
            sobrescribir: sobrescribir
        )
    }

    private func aplicarSincronizacion(
        asignatura: String,
        curso: String,
        evaluacionId: String,
        label: String,
        unidadId: String?,
        oaIds: [String],
        notasCalculadas: [String: (nombre: String, nota: String)],
        estudiantesSinNota: Int,
        roster: [EstudiantePerfil],
        sobrescribir: Bool
    ) async throws -> SyncCalificacionesResultado {
        let calId = Self.buildCalificacionesId(asignatura: asignatura, curso: curso)
        let ref = try userDoc(col: "calificaciones", id: calId)
        let snapshot = try await getDocument(ref)
        let data = snapshot.data() ?? [:]
        let estudiantesBase = data["estudiantes"] as? [[String: Any]] ?? []
        let evaluacionesBase = data["evaluaciones"] as? [[String: Any]] ?? []
        let evaluacionExistia = evaluacionesBase.contains { ($0["id"] as? String) == evaluacionId }

        var estudiantesMap: [String: [String: Any]] = [:]
        for (index, est) in roster.enumerated() {
            estudiantesMap[est.id] = [
                "id": est.id,
                "name": est.nombre,
                "orden": est.orden > 0 ? est.orden : index + 1,
                "notas": [String: Any](),
                "hasPie": est.pie,
                "pieDiagnostico": est.pieDiagnostico
            ]
        }
        for est in estudiantesBase {
            guard let id = est["id"] as? String else { continue }
            var merged = estudiantesMap[id] ?? [:]
            for (key, value) in est { merged[key] = value }
            let name = (est["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (estudiantesMap[id]?["name"] as? String)
                ?? (est["nombre"] as? String)
                ?? ""
            merged["name"] = name
            var notas = (estudiantesMap[id]?["notas"] as? [String: Any]) ?? [:]
            if let estNotas = est["notas"] as? [String: Any] {
                for (key, value) in estNotas { notas[key] = value }
            }
            merged["notas"] = notas
            estudiantesMap[id] = merged
        }
        for (id, val) in notasCalculadas where estudiantesMap[id] == nil {
            estudiantesMap[id] = ["id": id, "name": val.nombre, "notas": [String: Any](), "hasPie": false]
        }

        var conflictos: [SyncConflicto] = []
        for (id, val) in notasCalculadas {
            let anterior = Self.normalizarNota((estudiantesMap[id]?["notas"] as? [String: Any])?[evaluacionId])
            if !anterior.isEmpty && anterior != val.nota {
                conflictos.append(SyncConflicto(estudianteId: id, nombre: val.nombre, anterior: anterior, nueva: val.nota))
            }
        }

        if !conflictos.isEmpty && !sobrescribir {
            return SyncCalificacionesResultado(
                evaluacionId: evaluacionId,
                notasSincronizadas: notasCalculadas.count,
                estudiantesSinNota: estudiantesSinNota,
                evaluacionExistia: evaluacionExistia,
                requiereConfirmacion: true,
                conflictos: conflictos
            )
        }

        for (id, val) in notasCalculadas {
            guard var est = estudiantesMap[id] else { continue }
            var notas = (est["notas"] as? [String: Any]) ?? [:]
            notas[evaluacionId] = val.nota
            est["notas"] = notas
            estudiantesMap[id] = est
        }

        var evalEntry: [String: Any] = [
            "id": evaluacionId,
            "label": label,
            "tipo": "sumativa",
            "periodo": Self.periodoActual(),
            "oaIds": oaIds
        ]
        if let unidadId, !unidadId.isEmpty { evalEntry["unidadId"] = unidadId }

        let evaluacionesActualizadas: [[String: Any]] = evaluacionExistia
            ? evaluacionesBase.map { ev in
                (ev["id"] as? String) == evaluacionId ? ev.merging(evalEntry) { _, nuevo in nuevo } : ev
            }
            : evaluacionesBase + [evalEntry]

        let estudiantesOrdenados = estudiantesMap.values.sorted {
            (Self.asInt($0["orden"]) ?? 999) < (Self.asInt($1["orden"]) ?? 999)
        }

        try await setData([
            "asignatura": asignatura,
            "curso": curso,
            "estudiantes": estudiantesOrdenados,
            "evaluaciones": evaluacionesActualizadas,
            "updatedAt": FieldValue.serverTimestamp()
        ], at: ref, merge: true)

        return SyncCalificacionesResultado(
            evaluacionId: evaluacionId,
            notasSincronizadas: notasCalculadas.count,
            estudiantesSinNota: estudiantesSinNota,
            evaluacionExistia: evaluacionExistia,
            requiereConfirmacion: false,
            conflictos: conflictos
        )
    }

    // MARK: - Helpers de Calificaciones

    static func buildCalificacionesId(asignatura: String, curso: String) -> String {
        let combinado = "calif_\(asignatura)_\(curso)"
        return combinado
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }

    static func periodoActual(now: Date = Date()) -> String {
        let mes = Calendar.current.component(.month, from: now)
        return mes <= 7 ? "s1" : "s2"
    }

    static func oaIds(oas: [OAEditado]?, refs: [String]) -> [String] {
        var ids: [String] = []
        var vistos = Set<String>()
        func agregar(_ valor: String) {
            guard !valor.isEmpty, !vistos.contains(valor) else { return }
            vistos.insert(valor)
            ids.append(valor)
        }
        (oas ?? []).filter(\.seleccionado).forEach { agregar($0.id) }
        let regex = try? NSRegularExpression(pattern: "\\bOA\\s*(\\d+)\\b", options: .caseInsensitive)
        for ref in refs {
            let limpio = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty else { continue }
            if let regex,
               let match = regex.firstMatch(in: limpio, range: NSRange(limpio.startIndex..., in: limpio)),
               let numeroRange = Range(match.range(at: 1), in: limpio) {
                agregar("OA\(limpio[numeroRange])")
            } else {
                agregar(limpio)
            }
        }
        return ids
    }

    static func normalizarNota(_ value: Any?) -> String {
        guard let value else { return "" }
        if let numero = asDouble(value) {
            return String(format: "%.1f", numero)
        }
        let str = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return "" }
        if let numero = Double(str.replacingOccurrences(of: ",", with: ".")) {
            return String(format: "%.1f", numero)
        }
        return str
    }

    private static func asInt(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let number as NSNumber: return number.intValue
        case let double as Double: return Int(double)
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func asDouble(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }

    // MARK: - Decodificación

    private func decode<T: Decodable>(_ type: T.Type, from snapshot: DocumentSnapshot) -> T? {
        guard var dict = snapshot.data() else { return nil }
        dict["id"] = snapshot.documentID
        guard var value = T.from(dictionary: dict) else { return nil }
        if var lista = value as? ListaCotejoTemplate {
            lista.fechaActualizacion = timestampDate(dict)
            value = lista as! T
        } else if var rubrica = value as? RubricaTemplate {
            rubrica.fechaActualizacion = timestampDate(dict)
            value = rubrica as! T
        }
        return value
    }

    private func timestampDate(_ dict: [String: Any]) -> Date? {
        let raw = dict["updatedAt"] ?? dict["createdAt"]
        return (raw as? Timestamp)?.dateValue()
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

    private func getDocuments(_ col: CollectionReference) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            col.getDocuments { snapshot, error in
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

enum EvaluacionesRepositoryError: LocalizedError {
    case encoding

    var errorDescription: String? {
        switch self {
        case .encoding: return "No se pudo preparar el documento para guardar."
        }
    }
}
