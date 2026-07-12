import Foundation
import FirebaseAuth
import FirebaseFirestore

struct EvaluacionesRepository {
    /// La web guarda bajo este uid cuando el docente usa la página sin iniciar sesión.
    /// iOS lo consulta como fallback de LECTURA cuando la cuenta propia no tiene datos.
    static let invitadoUid = "mock-invitado-uid-12345"

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

    private func doc(uid: String, col: String, id: String) -> DocumentReference {
        db.collection("users").document(uid).collection(col).document(id)
    }

    private func col(uid: String, col nombre: String) -> CollectionReference {
        db.collection("users").document(uid).collection(nombre)
    }

    private func userDoc(col: String, id: String) throws -> DocumentReference {
        doc(uid: try getUid(), col: col, id: id)
    }

    private func userCol(col nombre: String) throws -> CollectionReference {
        col(uid: try getUid(), col: nombre)
    }

    private func scopedCol(uid: String, scope: EvaluacionScope, name: String) -> CollectionReference {
        let user = db.collection("users").document(uid)
        switch scope {
        case .principal:
            return user.collection(name)
        case .colegio(let colegioId):
            return user.collection("colegios").document(colegioId).collection(name)
        }
    }

    private func scopedDoc(uid: String, scope: EvaluacionScope, collection: String, id: String) -> DocumentReference {
        scopedCol(uid: uid, scope: scope, name: collection).document(id)
    }

    private func validate(scope: EvaluacionScope) throws {
        guard case .colegio(let id) = scope else { return }
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/") else {
            throw EvaluacionesRepositoryError.invalidScope
        }
    }

    /// Documentos de la colección propia; si está totalmente vacía, intenta la del invitado.
    private func documentosConFallback(col nombre: String) async throws -> [QueryDocumentSnapshot] {
        let propios = try await getDocuments(try userCol(col: nombre)).documents
        if !propios.isEmpty { return propios }
        let invitado = try? await getDocuments(col(uid: Self.invitadoUid, col: nombre)).documents
        return invitado ?? []
    }

    /// Documento por id bajo la cuenta propia; si no existe, intenta bajo el invitado.
    private func documentoConFallback(col nombre: String, id: String) async throws -> DocumentSnapshot? {
        let propio = try await getDocument(try userDoc(col: nombre, id: id))
        if propio.exists { return propio }
        if let invitado = try? await getDocument(doc(uid: Self.invitadoUid, col: nombre, id: id)), invitado.exists {
            return invitado
        }
        return nil
    }

    /// Comparación difusa de curso/asignatura: sin tildes, mayúsculas ni símbolos.
    static func normalizarClave(_ valor: String) -> String {
        valor.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private static func coincide(_ a: String, _ b: String) -> Bool {
        normalizarClave(a) == normalizarClave(b)
    }

    // MARK: - Listas de Cotejo

    func cargarListasCotejo(asignatura: String?, curso: String) async throws -> [ListaCotejoTemplate] {
        let documentos = try await documentosConFallback(col: "listas_cotejo")
        return documentos
            .compactMap { decode(ListaCotejoTemplate.self, from: $0) }
            .filter { lista in
                Self.coincide(lista.curso, curso) &&
                asignatura.map { Self.coincide(lista.asignatura, $0) } ?? true
            }
            .sorted { ($0.fechaActualizacion ?? .distantPast) > ($1.fechaActualizacion ?? .distantPast) }
    }

    func cargarListaCotejo(id: String) async throws -> ListaCotejoTemplate? {
        guard let snapshot = try await documentoConFallback(col: "listas_cotejo", id: id) else { return nil }
        return decode(ListaCotejoTemplate.self, from: snapshot)
    }

    func guardarListaCotejo(_ lista: ListaCotejoTemplate) async throws {
        var normalizada = lista
        normalizada.normalizar()
        if let meta = ListaCotejoMetadatos.desde(oas: normalizada.oas) {
            normalizada.metadatosCurriculares = meta
        }
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
        guard let snapshot = try await documentoConFallback(col: "listas_cotejo_evaluaciones", id: id) else { return nil }
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
        let documentos = try await documentosConFallback(col: "rubricas")
        return documentos
            .compactMap { decode(RubricaTemplate.self, from: $0) }
            .filter { rubrica in
                Self.coincide(rubrica.curso, curso) &&
                asignatura.map { Self.coincide(rubrica.asignatura, $0) } ?? true
            }
            .sorted { ($0.fechaActualizacion ?? .distantPast) > ($1.fechaActualizacion ?? .distantPast) }
    }

    func cargarRubrica(id: String) async throws -> RubricaTemplate? {
        guard let snapshot = try await documentoConFallback(col: "rubricas", id: id) else { return nil }
        return decode(RubricaTemplate.self, from: snapshot)
    }

    func guardarRubrica(_ rubrica: RubricaTemplate) async throws {
        var normalizada = rubrica
        normalizada.normalizar()
        if let meta = ListaCotejoMetadatos.desde(oas: normalizada.oas) {
            normalizada.metadatosCurriculares = meta
        }
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
        guard let snapshot = try await documentoConFallback(col: "rubricas_evaluaciones", id: id) else { return nil }
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

    // MARK: - Pruebas (lectura lossless)

    /// Lee exclusivamente el ámbito activo. Pruebas no usa el fallback invitado porque
    /// una procedencia equivocada podría mezclar documentos entre usuarios o colegios.
    func cargarPruebas(curso: String, scope: EvaluacionScope) async throws -> PruebasCargaResultado {
        try validate(scope: scope)
        let uid = try getUid()
        let snapshot = try await getDocuments(scopedCol(uid: uid, scope: scope, name: "pruebas"))
        let fromCache = snapshot.metadata.isFromCache
        var warningCount = 0

        let pruebas = snapshot.documents.compactMap { document -> PruebaTemplate? in
            let prueba = PruebaDocumentParser.prueba(
                id: document.documentID,
                scope: scope,
                isFromCache: fromCache,
                dictionary: document.data()
            )
            guard Self.coincide(prueba.curso, curso) else { return nil }
            if !prueba.issues.isEmpty || prueba.tieneContenidoDesconocido {
                warningCount += 1
            }
            return prueba
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.fechaActualizacion ?? lhs.fechaCreacion ?? .distantPast
            let rhsDate = rhs.fechaActualizacion ?? rhs.fechaCreacion ?? .distantPast
            if lhsDate == rhsDate { return lhs.id > rhs.id }
            return lhsDate > rhsDate
        }

        return PruebasCargaResultado(
            pruebas: pruebas,
            documentosConAdvertencias: warningCount,
            isFromCache: fromCache
        )
    }

    func cargarPrueba(id: String, scope: EvaluacionScope) async throws -> PruebaTemplate? {
        try validate(scope: scope)
        let uid = try getUid()
        let snapshot = try await getDocument(scopedDoc(uid: uid, scope: scope, collection: "pruebas", id: id))
        guard snapshot.exists else { return nil }
        guard let dictionary = snapshot.data() else {
            throw EvaluacionesRepositoryError.invalidDocument(collection: "pruebas", id: id)
        }
        return PruebaDocumentParser.prueba(
            id: snapshot.documentID,
            scope: scope,
            isFromCache: snapshot.metadata.isFromCache,
            dictionary: dictionary
        )
    }

    func cargarAplicacionPrueba(pruebaId: String, scope: EvaluacionScope) async throws -> PruebaAplicacion? {
        try validate(scope: scope)
        let uid = try getUid()
        let id = "apl_\(pruebaId)"
        let snapshot = try await getDocument(
            scopedDoc(uid: uid, scope: scope, collection: "pruebas_aplicaciones", id: id)
        )
        guard snapshot.exists else { return nil }
        guard let dictionary = snapshot.data() else {
            throw EvaluacionesRepositoryError.invalidDocument(collection: "pruebas_aplicaciones", id: id)
        }
        let application = PruebaDocumentParser.aplicacion(
            id: snapshot.documentID,
            scope: scope,
            isFromCache: snapshot.metadata.isFromCache,
            dictionary: dictionary
        )
        guard application.pruebaId == pruebaId else {
            throw EvaluacionesRepositoryError.mismatchedApplication(
                expected: pruebaId,
                actual: application.pruebaId
            )
        }
        return application
    }

    /// Carga el roster desde el mismo ámbito que la prueba. No usa el snapshot
    /// global del dashboard porque un colegio secundario tiene su propia colección.
    func cargarEstudiantesPrueba(curso: String, scope: EvaluacionScope) async throws -> [EstudiantePerfil] {
        try validate(scope: scope)
        let uid = try getUid()
        let collection = scopedCol(uid: uid, scope: scope, name: "estudiantes")
        let currentId = DashboardRepository.buildCursoId(curso)
        var snapshot = try await getDocument(collection.document(currentId))
        if !snapshot.exists {
            let legacyId = Self.buildLegacyCourseId(curso)
            if legacyId != currentId {
                snapshot = try await getDocument(collection.document(legacyId))
            }
        }
        guard snapshot.exists else { return [] }
        let rawStudents = (snapshot.data()?["alumnos"] as? [Any]) ?? []
        return rawStudents.enumerated()
            .compactMap { index, raw in
                guard let dictionary = raw as? [String: Any] else { return nil }
                return EstudiantePerfil.from(dictionary: dictionary, index: index)
            }
            .sorted { lhs, rhs in
                if lhs.orden != rhs.orden { return lhs.orden < rhs.orden }
                return lhs.nombre.localizedCaseInsensitiveCompare(rhs.nombre) == .orderedAscending
            }
    }

    /// Guarda resultados y cambia la prueba a `aplicada` en una sola transacción.
    /// El documento remoto es la base del merge para conservar campos futuros.
    @discardableResult
    func guardarAplicacionPrueba(
        _ draft: PruebaApplicationDraft,
        prueba: PruebaTemplate,
        scope: EvaluacionScope
    ) async throws -> String {
        try validate(scope: scope)
        guard prueba.scope == scope,
              draft.pruebaId == prueba.id,
              draft.id == "apl_\(prueba.id)" else {
            throw EvaluacionesRepositoryError.mismatchedApplication(
                expected: prueba.id,
                actual: draft.pruebaId
            )
        }

        let uid = try getUid()
        let applicationReference = scopedDoc(
            uid: uid,
            scope: scope,
            collection: "pruebas_aplicaciones",
            id: draft.id
        )
        let testReference = scopedDoc(uid: uid, scope: scope, collection: "pruebas", id: prueba.id)
        let knownItemIds = Set(prueba.secciones.flatMap(\.items).compactMap(\.sourceId))

        let _: Any? = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                // Firestore exige completar las lecturas antes de comenzar a escribir.
                let applicationSnapshot = try transaction.getDocument(applicationReference)
                let testSnapshot = try transaction.getDocument(testReference)
                guard testSnapshot.exists, var testPayload = testSnapshot.data() else {
                    throw EvaluacionesRepositoryError.invalidDocument(collection: "pruebas", id: prueba.id)
                }

                var applicationPayload: [String: Any]
                if draft.isNew {
                    guard !applicationSnapshot.exists else {
                        throw EvaluacionesRepositoryError.applicationEditConflict(path: "pruebas_aplicaciones/\(draft.id)")
                    }
                    applicationPayload = [:]
                } else {
                    guard applicationSnapshot.exists, let remoteData = applicationSnapshot.data() else {
                        throw EvaluacionesRepositoryError.invalidDocument(
                            collection: "pruebas_aplicaciones",
                            id: draft.id
                        )
                    }
                    let remoteApplication = PruebaDocumentParser.aplicacion(
                        id: draft.id,
                        scope: scope,
                        isFromCache: false,
                        dictionary: remoteData
                    )
                    let remoteDraft = PruebaApplicationDraft.build(
                        prueba: prueba,
                        application: remoteApplication,
                        roster: []
                    )
                    guard remoteDraft.baselineFingerprint == draft.baselineFingerprint else {
                        throw EvaluacionesRepositoryError.applicationEditConflict(
                            path: "pruebas_aplicaciones/\(draft.id)"
                        )
                    }
                    applicationPayload = remoteData
                }

                self.applyApplicationRootFields(
                    draft,
                    knownItemIds: knownItemIds,
                    payload: &applicationPayload
                )
                applicationPayload["updatedAt"] = FieldValue.serverTimestamp()
                transaction.setData(applicationPayload, forDocument: applicationReference, merge: false)

                if Self.normalizarClave(self.pruebaApplicationString(testPayload["estado"])) != "aplicada" {
                    testPayload["estado"] = "aplicada"
                    testPayload["updatedAt"] = FieldValue.serverTimestamp()
                    transaction.setData(testPayload, forDocument: testReference, merge: false)
                }
                return draft.id
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        return draft.id
    }

    private func applyApplicationRootFields(
        _ draft: PruebaApplicationDraft,
        knownItemIds: Set<String>,
        payload: inout [String: Any]
    ) {
        payload["pruebaId"] = draft.pruebaId
        payload["pruebaNombre"] = draft.pruebaNombre
        payload["asignatura"] = draft.asignatura
        payload["curso"] = draft.curso
        let date = draft.fechaAplicacion.trimmingCharacters(in: .whitespacesAndNewlines)
        if date.isEmpty { payload.removeValue(forKey: "fechaAplicacion") }
        else { payload["fechaAplicacion"] = date }
        if draft.bloqueada { payload["bloqueada"] = true }
        payload["resultados"] = mergeApplicationResults(
            draft.resultados,
            remoteValue: payload["resultados"],
            knownItemIds: knownItemIds
        )
    }

    private func mergeApplicationResults(
        _ drafts: [PruebaStudentResultDraft],
        remoteValue: Any?,
        knownItemIds: Set<String>
    ) -> [Any] {
        let remoteValues = (remoteValue as? [Any]) ?? []
        var claimed = Set<Int>()
        var merged: [Any] = []

        for draft in drafts {
            let match = applicationResultMatch(draft, remoteValues: remoteValues, claimed: claimed)
            guard let index = match,
                  let remote = remoteValues[index] as? [String: Any] else {
                merged.append(encodeApplicationResult(draft, remote: nil, knownItemIds: knownItemIds))
                continue
            }
            claimed.insert(index)
            if !draft.isNew, draft.contentFingerprint == draft.baselineFingerprint {
                merged.append(remote)
            } else {
                merged.append(encodeApplicationResult(draft, remote: remote, knownItemIds: knownItemIds))
            }
        }

        for index in remoteValues.indices where !claimed.contains(index) {
            merged.append(remoteValues[index])
        }
        return merged
    }

    private func applicationResultMatch(
        _ draft: PruebaStudentResultDraft,
        remoteValues: [Any],
        claimed: Set<Int>
    ) -> Int? {
        if let originalIndex = draft.originalIndex,
           remoteValues.indices.contains(originalIndex),
           !claimed.contains(originalIndex),
           let dictionary = remoteValues[originalIndex] as? [String: Any] {
            let remoteId = pruebaApplicationString(dictionary["estudianteId"])
            if draft.sourceId == nil || remoteId == draft.sourceId { return originalIndex }
        }
        guard let sourceId = draft.sourceId else { return nil }
        return remoteValues.indices.first { index in
            guard !claimed.contains(index),
                  let dictionary = remoteValues[index] as? [String: Any] else { return false }
            return pruebaApplicationString(dictionary["estudianteId"]) == sourceId
        }
    }

    private func encodeApplicationResult(
        _ draft: PruebaStudentResultDraft,
        remote: [String: Any]?,
        knownItemIds: Set<String>
    ) -> [String: Any] {
        var result = remote ?? [:]
        if let sourceId = draft.sourceId { result["estudianteId"] = sourceId }
        result["nombre"] = draft.nombre
        result["hasPie"] = draft.hasPie
        result["respuestas"] = mergeApplicationResponses(
            draft.respuestas,
            remoteValue: result["respuestas"],
            knownItemIds: knownItemIds
        )
        result["puntajePorItem"] = draft.puntajePorItem
        result["puntajeTotal"] = draft.puntajeTotal
        if let note = draft.nota { result["nota"] = note }
        else { result.removeValue(forKey: "nota") }
        if draft.observaciones.isEmpty { result.removeValue(forKey: "observaciones") }
        else { result["observaciones"] = draft.observaciones }
        result["completado"] = draft.completado
        result["ausente"] = draft.ausente
        return result
    }

    private func mergeApplicationResponses(
        _ drafts: [String: PruebaResponseDraft],
        remoteValue: Any?,
        knownItemIds: Set<String>
    ) -> [String: Any] {
        // No se eliminan claves ausentes: la web tampoco ofrece borrar una respuesta
        // y así sobreviven respuestas de ítems futuros o retirados de la plantilla.
        var result = (remoteValue as? [String: Any]) ?? [:]
        for itemId in drafts.keys.sorted() {
            guard knownItemIds.contains(itemId), let draft = drafts[itemId] else { continue }
            if !draft.isNew,
               draft.contentFingerprint == draft.baselineFingerprint,
               result[itemId] != nil {
                continue
            }
            result[itemId] = encodeApplicationResponse(draft, remote: result[itemId] as? [String: Any])
        }
        return result
    }

    private func encodeApplicationResponse(
        _ draft: PruebaResponseDraft,
        remote: [String: Any]?
    ) -> [String: Any] {
        var result = remote ?? [:]
        for key in [
            "tipo", "alternativaId", "valor", "justificacion", "emparejamientos",
            "orden", "respuestas", "texto", "puntajeManual", "puntajePorCriterio"
        ] {
            result.removeValue(forKey: key)
        }
        result["tipo"] = draft.type
        switch PruebaEditorItemType.resolve(draft.type) {
        case .seleccionMultiple:
            result["alternativaId"] = draft.alternativaId
        case .verdaderoFalso:
            if let value = draft.valor { result["valor"] = value }
            if !draft.justificacion.isEmpty { result["justificacion"] = draft.justificacion }
        case .pareados:
            result["emparejamientos"] = draft.emparejamientos
        case .ordenar:
            result["orden"] = draft.orden
        case .completar:
            result["respuestas"] = draft.respuestas
        case .respuestaCorta:
            result["texto"] = draft.texto
            if let score = draft.puntajeManual { result["puntajeManual"] = score }
        case .desarrollo:
            result["texto"] = draft.texto
            if let score = draft.puntajeManual { result["puntajeManual"] = score }
            if !draft.puntajePorCriterio.isEmpty {
                result["puntajePorCriterio"] = draft.puntajePorCriterio
            }
        case nil:
            // Una respuesta futura no es editable; conservar su diccionario remoto.
            return remote ?? result
        }
        return result
    }

    private static func buildLegacyCourseId(_ course: String) -> String {
        course.lowercased().replacingOccurrences(
            of: "[^a-z0-9]",
            with: "_",
            options: .regularExpression
        )
    }

    private func pruebaApplicationString(_ value: Any?) -> String {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return ""
        }
    }

    /// Persiste una prueba sin reconstruir el documento desde los modelos tipados.
    /// Para documentos existentes parte del payload remoto dentro de una transaccion,
    /// de modo que campos web futuros y miembros de array no interpretados sobrevivan.
    @discardableResult
    func guardarPruebaEditor(_ draft: PruebaEditorDraft, scope: EvaluacionScope) async throws -> String {
        try validate(scope: scope)
        let uid = try getUid()
        let isNew = draft.id == nil
        let id = draft.id ?? Self.buildPruebaId(asignatura: draft.asignatura, curso: draft.curso)
        let reference = scopedDoc(uid: uid, scope: scope, collection: "pruebas", id: id)

        let _: Any? = try await self.db.runTransaction { transaction, errorPointer -> Any? in
            do {
                if isNew {
                    let existing = try transaction.getDocument(reference)
                    guard !existing.exists else {
                        throw EvaluacionesRepositoryError.editConflict(path: "pruebas/\(id)")
                    }
                    var payload = try self.pruebaPayloadNueva(draft)
                    payload["createdAt"] = FieldValue.serverTimestamp()
                    payload["updatedAt"] = FieldValue.serverTimestamp()
                    transaction.setData(payload, forDocument: reference, merge: false)
                    return id
                }

                let snapshot = try transaction.getDocument(reference)
                guard snapshot.exists, let remoteData = snapshot.data() else {
                    throw EvaluacionesRepositoryError.invalidDocument(collection: "pruebas", id: id)
                }
                let remote = PruebaDocumentParser.prueba(
                    id: id,
                    scope: scope,
                    isFromCache: false,
                    dictionary: remoteData
                )
                if Self.normalizarClave(remote.estado) == "aplicada" {
                    throw EvaluacionesRepositoryError.appliedTestReadOnly
                }

                let remoteDraft = PruebaEditorDraft.from(remote)
                guard remoteDraft.editableFingerprint == draft.baselineFingerprint else {
                    throw EvaluacionesRepositoryError.editConflict(path: "pruebas/\(id)")
                }

                // Pulsar guardar sin cambios no altera ni siquiera updatedAt.
                guard draft.editableFingerprint != remoteDraft.editableFingerprint else { return id }

                var payload = remoteData
                var scoreStructureChanged = false
                try self.applyPruebaRootFields(
                    draft,
                    remote: remoteDraft,
                    payload: &payload,
                    scoreStructureChanged: &scoreStructureChanged
                )
                if scoreStructureChanged {
                    payload["puntajeMaximo"] = self.pruebaMaximumScore(from: payload["secciones"])
                }
                payload["updatedAt"] = FieldValue.serverTimestamp()
                transaction.setData(payload, forDocument: reference, merge: false)
                return id
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        return id
    }

    /// Construye una prueba canónica de vista previa sin escribir en Firestore.
    /// Se usa para exportar también los cambios todavía no guardados del editor.
    func prepararPruebaParaExportar(
        _ draft: PruebaEditorDraft,
        scope: EvaluacionScope,
        base: PruebaTemplate?
    ) throws -> PruebaTemplate {
        var data = try pruebaPayloadNueva(draft)
        if let base {
            // Campos futuros de raíz sobreviven en la vista previa; los campos
            // conocidos del borrador tienen prioridad.
            data = base.raw.merging(data) { _, draftValue in draftValue }
        }
        return PruebaDocumentParser.prueba(
            id: draft.id ?? "prueba_preview",
            scope: scope,
            isFromCache: false,
            dictionary: data
        )
    }

    func eliminarPrueba(id: String, scope: EvaluacionScope) async throws {
        try validate(scope: scope)
        let uid = try getUid()
        try await deleteDocument(scopedDoc(uid: uid, scope: scope, collection: "pruebas", id: id))
        try? await deleteDocument(
            scopedDoc(uid: uid, scope: scope, collection: "pruebas_aplicaciones", id: "apl_\(id)")
        )
    }

    @discardableResult
    func duplicarPrueba(_ prueba: PruebaTemplate, cursoDestino: String, scope: EvaluacionScope) async throws -> String {
        try validate(scope: scope)
        let uid = try getUid()
        let source = scopedDoc(uid: uid, scope: scope, collection: "pruebas", id: prueba.id)
        let snapshot = try await getDocument(source)
        guard snapshot.exists, var payload = snapshot.data() else {
            throw EvaluacionesRepositoryError.invalidDocument(collection: "pruebas", id: prueba.id)
        }

        let parsed = PruebaDocumentParser.prueba(
            id: prueba.id,
            scope: scope,
            isFromCache: snapshot.metadata.isFromCache,
            dictionary: payload
        )
        let cleanCourse = cursoDestino.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = Self.buildPruebaId(asignatura: parsed.asignatura, curso: cleanCourse)
        payload.removeValue(forKey: "id")
        payload["nombre"] = "\(parsed.nombre.isEmpty ? "Prueba" : parsed.nombre) (copia)"
        payload["curso"] = cleanCourse
        payload["estado"] = "borrador"
        payload["bloqueada"] = false
        payload.removeValue(forKey: "bloqueadaEn")
        payload["createdAt"] = FieldValue.serverTimestamp()
        payload["updatedAt"] = FieldValue.serverTimestamp()
        payload["secciones"] = regeneratedPruebaSections(payload["secciones"])
        try await setData(
            payload,
            at: scopedDoc(uid: uid, scope: scope, collection: "pruebas", id: id),
            merge: false
        )
        return id
    }

    private func pruebaPayloadNueva(_ draft: PruebaEditorDraft) throws -> [String: Any] {
        let sections = try encodePruebaSections(draft.secciones)
        var payload: [String: Any] = [
            "nombre": draft.nombre.trimmingCharacters(in: .whitespacesAndNewlines),
            "asignatura": draft.asignatura.trimmingCharacters(in: .whitespacesAndNewlines),
            "curso": draft.curso.trimmingCharacters(in: .whitespacesAndNewlines),
            "tipoEvaluacion": draft.tipoEvaluacion,
            "ponderacion": max(0, draft.ponderacion),
            "tiempoMinutos": max(1, draft.tiempoMinutos),
            "exigencia": min(1, max(0, draft.exigencia)),
            "instruccionesGenerales": cleanStrings(draft.instruccionesGenerales),
            "secciones": sections,
            "estado": draft.estado,
            "puntajeMaximo": pruebaMaximumScore(from: sections)
        ]
        if draft.bloqueada { payload["bloqueada"] = true }
        setPruebaOptionalString(draft.unidadId, key: "unidadId", in: &payload)
        setPruebaOptionalString(draft.unidadNombre, key: "unidadNombre", in: &payload)
        setPruebaOptionalString(draft.docenteNombre, key: "docenteNombre", in: &payload)
        try applyPruebaCurriculum(draft.oas, payload: &payload)
        return payload
    }

    private func applyPruebaRootFields(
        _ draft: PruebaEditorDraft,
        remote: PruebaEditorDraft,
        payload: inout [String: Any],
        scoreStructureChanged: inout Bool
    ) throws {
        if draft.nombre != remote.nombre {
            payload["nombre"] = draft.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if draft.asignatura != remote.asignatura {
            payload["asignatura"] = draft.asignatura.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if draft.curso != remote.curso {
            payload["curso"] = draft.curso.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if draft.unidadId != remote.unidadId {
            setPruebaOptionalString(draft.unidadId, key: "unidadId", in: &payload)
        }
        if draft.unidadNombre != remote.unidadNombre {
            setPruebaOptionalString(draft.unidadNombre, key: "unidadNombre", in: &payload)
        }
        if draft.docenteNombre != remote.docenteNombre {
            setPruebaOptionalString(draft.docenteNombre, key: "docenteNombre", in: &payload)
        }
        if draft.tipoEvaluacion != remote.tipoEvaluacion { payload["tipoEvaluacion"] = draft.tipoEvaluacion }
        if draft.ponderacion != remote.ponderacion { payload["ponderacion"] = max(0, draft.ponderacion) }
        if draft.tiempoMinutos != remote.tiempoMinutos { payload["tiempoMinutos"] = max(1, draft.tiempoMinutos) }
        if draft.exigencia != remote.exigencia { payload["exigencia"] = min(1, max(0, draft.exigencia)) }
        if draft.instruccionesGenerales != remote.instruccionesGenerales {
            payload["instruccionesGenerales"] = cleanStrings(draft.instruccionesGenerales)
        }
        if draft.oas != remote.oas {
            try applyPruebaCurriculum(
                draft.oas,
                remoteValue: payload["oas"],
                remoteOAs: remote.oas,
                payload: &payload
            )
        }
        if draft.estado != remote.estado { payload["estado"] = draft.estado }
        if draft.bloqueada != remote.bloqueada { payload["bloqueada"] = draft.bloqueada }

        let localSections = draft.secciones.map(\.contentFingerprint)
        let remoteSections = remote.secciones.map(\.contentFingerprint)
        if localSections != remoteSections {
            let result = try mergePruebaSections(
                draft.secciones,
                remoteValue: payload["secciones"],
                remoteDrafts: remote.secciones
            )
            payload["secciones"] = result.value
            scoreStructureChanged = result.scoreChanged
        }
    }

    private func applyPruebaCurriculum(
        _ oas: [OAEditado]?,
        remoteValue: Any? = nil,
        remoteOAs: [OAEditado]? = nil,
        payload: inout [String: Any]
    ) throws {
        guard let oas else {
            payload.removeValue(forKey: "oas")
            payload.removeValue(forKey: "metadatosCurriculares")
            return
        }
        if let remoteOAs {
            payload["oas"] = try mergePruebaOAs(oas, remoteValue: remoteValue, remoteOAs: remoteOAs)
        } else {
            payload["oas"] = try encodePruebaOAs(oas)
        }
        let metadata = ListaCotejoMetadatos.desde(oas: oas) ?? ListaCotejoMetadatos(
            objetivos: [], indicadores: [], objetivosTransversales: []
        )
        var rawMetadata = (payload["metadatosCurriculares"] as? [String: Any]) ?? [:]
        rawMetadata["objetivos"] = metadata.objetivos
        rawMetadata["indicadores"] = metadata.indicadores
        rawMetadata["objetivosTransversales"] = metadata.objetivosTransversales
        payload["metadatosCurriculares"] = rawMetadata
    }

    private func encodePruebaOAs(_ oas: [OAEditado]) throws -> [[String: Any]] {
        try oas.map { oa in
            guard let dictionary = oa.dictionary else { throw EvaluacionesRepositoryError.encoding }
            return dictionary
        }
    }

    private func mergePruebaOAs(
        _ local: [OAEditado],
        remoteValue: Any?,
        remoteOAs: [OAEditado]
    ) throws -> [Any] {
        let remoteValues = pruebaRawArray(remoteValue)
        let positions = pruebaDictionaryPositions(in: remoteValues)
        guard positions.count == remoteOAs.count else {
            throw EvaluacionesRepositoryError.editConflict(path: "oas")
        }
        var claimed = Set<Int>()
        var result: [Any] = []
        for (localIndex, oa) in local.enumerated() {
            let candidates = remoteOAs.indices.filter { remoteOAs[$0].id == oa.id }
            let remoteIndex: Int?
            if candidates.count == 1 {
                remoteIndex = candidates[0]
            } else if remoteOAs.indices.contains(localIndex), remoteOAs[localIndex].id == oa.id {
                remoteIndex = localIndex
            } else {
                remoteIndex = nil
            }
            guard let remoteIndex else {
                guard let encoded = oa.dictionary else { throw EvaluacionesRepositoryError.encoding }
                result.append(encoded)
                continue
            }
            let rawIndex = positions[remoteIndex]
            guard !claimed.contains(rawIndex), var raw = remoteValues[rawIndex] as? [String: Any] else {
                throw EvaluacionesRepositoryError.editConflict(path: "oas/\(oa.id)")
            }
            claimed.insert(rawIndex)
            let remote = remoteOAs[remoteIndex]
            if oa == remote {
                result.append(raw)
                continue
            }
            raw["id"] = oa.id
            setPruebaOptionalInt(oa.numero, key: "numero", in: &raw)
            setPruebaOptionalString(oa.tipo ?? "", key: "tipo", in: &raw)
            raw["descripcion"] = oa.descripcion
            raw["seleccionado"] = oa.seleccionado
            setPruebaOptionalBool(oa.esPropio, key: "esPropio", in: &raw)
            setPruebaOptionalStrings(oa.tags, key: "tags", in: &raw)
            if oa.indicadores != remote.indicadores {
                raw["indicadores"] = try mergePruebaIndicators(
                    oa.indicadores,
                    remoteValue: raw["indicadores"],
                    remoteIndicators: remote.indicadores,
                    path: "oas/\(oa.id)/indicadores"
                )
            }
            result.append(raw)
        }
        for index in remoteValues.indices where !claimed.contains(index) && !(remoteValues[index] is [String: Any]) {
            result.append(remoteValues[index])
        }
        return result
    }

    private func mergePruebaIndicators(
        _ local: [IndicadorEditado],
        remoteValue: Any?,
        remoteIndicators: [IndicadorEditado],
        path: String
    ) throws -> [Any] {
        let remoteValues = pruebaRawArray(remoteValue)
        let positions = pruebaDictionaryPositions(in: remoteValues)
        guard positions.count == remoteIndicators.count else {
            throw EvaluacionesRepositoryError.editConflict(path: path)
        }
        var claimed = Set<Int>()
        var result: [Any] = []
        for (localIndex, indicator) in local.enumerated() {
            let candidates = remoteIndicators.indices.filter { remoteIndicators[$0].id == indicator.id }
            let remoteIndex: Int?
            if candidates.count == 1 {
                remoteIndex = candidates[0]
            } else if remoteIndicators.indices.contains(localIndex),
                      remoteIndicators[localIndex].id == indicator.id {
                remoteIndex = localIndex
            } else {
                remoteIndex = nil
            }
            guard let remoteIndex else {
                guard let encoded = indicator.dictionary else { throw EvaluacionesRepositoryError.encoding }
                result.append(encoded)
                continue
            }
            let rawIndex = positions[remoteIndex]
            guard !claimed.contains(rawIndex), var raw = remoteValues[rawIndex] as? [String: Any] else {
                throw EvaluacionesRepositoryError.editConflict(path: "\(path)/\(indicator.id)")
            }
            claimed.insert(rawIndex)
            let remote = remoteIndicators[remoteIndex]
            if indicator == remote {
                result.append(raw)
                continue
            }
            raw["id"] = indicator.id
            raw["texto"] = indicator.texto
            raw["seleccionado"] = indicator.seleccionado
            setPruebaOptionalBool(indicator.esPropio, key: "esPropio", in: &raw)
            result.append(raw)
        }
        for index in remoteValues.indices where !claimed.contains(index) && !(remoteValues[index] is [String: Any]) {
            result.append(remoteValues[index])
        }
        return result
    }

    private func setPruebaOptionalInt(_ value: Int?, key: String, in payload: inout [String: Any]) {
        if let value { payload[key] = value } else { payload.removeValue(forKey: key) }
    }

    private func setPruebaOptionalBool(_ value: Bool?, key: String, in payload: inout [String: Any]) {
        if let value { payload[key] = value } else { payload.removeValue(forKey: key) }
    }

    private func setPruebaOptionalStrings(_ value: [String]?, key: String, in payload: inout [String: Any]) {
        if let value { payload[key] = value } else { payload.removeValue(forKey: key) }
    }

    private func setPruebaOptionalString(_ value: String, key: String, in payload: inout [String: Any]) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { payload.removeValue(forKey: key) }
        else { payload[key] = clean }
    }

    private func regeneratedPruebaSections(_ value: Any?) -> [Any] {
        pruebaRawArray(value).map { element in
            guard var section = element as? [String: Any] else { return element }
            section["id"] = "sec_\(UUID().uuidString.lowercased())"
            section["items"] = pruebaRawArray(section["items"]).map { itemValue in
                guard var item = itemValue as? [String: Any] else { return itemValue }
                item["id"] = "item_\(UUID().uuidString.lowercased())"
                return item
            }
            return section
        }
    }

    private static func buildPruebaId(asignatura: String, curso: String) -> String {
        let milliseconds = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        return "prueba_\(pruebaKeyPart(asignatura))_\(pruebaKeyPart(curso))_\(milliseconds)"
    }

    private static func pruebaKeyPart(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }

    private func pruebaRawArray(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private func pruebaDictionaryPositions(in values: [Any]) -> [Int] {
        values.indices.filter { values[$0] is [String: Any] }
    }

    private func pruebaMatch<D>(
        sourceId: String?,
        originalIndex: Int?,
        baselineFingerprint: String,
        remoteValues: [Any],
        remoteDrafts: [D],
        claimed: Set<Int>,
        remoteSourceId: (D) -> String?,
        remoteFingerprint: (D) -> String,
        path: String
    ) throws -> (rawIndex: Int, draftIndex: Int) {
        let positions = pruebaDictionaryPositions(in: remoteValues)
        if let sourceId, !sourceId.isEmpty {
            let candidates = remoteDrafts.indices.filter { remoteSourceId(remoteDrafts[$0]) == sourceId }
            if candidates.count == 1,
               positions.indices.contains(candidates[0]),
               !claimed.contains(positions[candidates[0]]) {
                return (positions[candidates[0]], candidates[0])
            }
        }
        if let originalIndex,
           remoteDrafts.indices.contains(originalIndex),
           positions.indices.contains(originalIndex),
           !claimed.contains(positions[originalIndex]),
           remoteFingerprint(remoteDrafts[originalIndex]) == baselineFingerprint {
            return (positions[originalIndex], originalIndex)
        }
        throw EvaluacionesRepositoryError.editConflict(path: path)
    }

    private func pruebaBlockSourceId(_ block: GuiaBlockDraft) -> String? {
        let last = block.id.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return last.isEmpty || last == "missing" ? nil : last
    }

    private func pruebaMaximumScore(from sectionsValue: Any?) -> Double {
        pruebaRawArray(sectionsValue).reduce(0) { sectionTotal, sectionValue in
            guard let section = sectionValue as? [String: Any] else { return sectionTotal }
            let itemTotal = pruebaRawArray(section["items"]).reduce(0) { total, itemValue in
                guard let item = itemValue as? [String: Any] else { return total }
                return total + max(0, Self.pruebaDouble(item["puntaje"]) ?? 0)
            }
            return sectionTotal + itemTotal
        }
    }

    private static func pruebaDouble(_ value: Any?) -> Double? {
        switch value {
        case is Bool: return nil
        case let number as NSNumber: return number.doubleValue
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    private func encodePruebaSections(_ drafts: [PruebaSectionDraft]) throws -> [Any] {
        var result: [Any] = []
        for draft in drafts where !draft.isDeleted {
            result.append(try encodePruebaSection(draft))
        }
        return result
    }

    private func encodePruebaSection(_ draft: PruebaSectionDraft) throws -> [String: Any] {
        var section: [String: Any] = [
            "id": draft.documentId,
            "orden": max(1, draft.orden),
            "titulo": draft.titulo,
            "instrucciones": draft.instrucciones,
            "estimulo": try encodePruebaBlocks(draft.estimulo),
            "items": try encodePruebaItems(draft.items)
        ]
        setPruebaOptionalString(draft.tipoPredominante, key: "tipoPredominante", in: &section)
        return section
    }

    private func mergePruebaSections(
        _ drafts: [PruebaSectionDraft],
        remoteValue: Any?,
        remoteDrafts: [PruebaSectionDraft]
    ) throws -> (value: [Any], scoreChanged: Bool) {
        let remoteValues = pruebaRawArray(remoteValue)
        var claimed = Set<Int>()
        var merged: [Any] = []
        var scoreChanged = false

        for draft in drafts {
            if draft.isNew {
                if !draft.isDeleted {
                    merged.append(try encodePruebaSection(draft))
                    scoreChanged = true
                }
                continue
            }
            let match = try pruebaMatch(
                sourceId: draft.sourceId,
                originalIndex: draft.originalIndex,
                baselineFingerprint: draft.baselineFingerprint,
                remoteValues: remoteValues,
                remoteDrafts: remoteDrafts,
                claimed: claimed,
                remoteSourceId: { $0.sourceId },
                remoteFingerprint: { $0.baselineFingerprint },
                path: "secciones/\(draft.originalIndex.map { String($0) } ?? draft.documentId)"
            )
            claimed.insert(match.rawIndex)
            guard !draft.isDeleted else {
                scoreChanged = true
                continue
            }
            guard var section = remoteValues[match.rawIndex] as? [String: Any] else {
                throw EvaluacionesRepositoryError.editConflict(path: "secciones/\(match.draftIndex)")
            }
            let remoteDraft = remoteDrafts[match.draftIndex]
            if draft.contentFingerprint == remoteDraft.contentFingerprint {
                merged.append(section)
                continue
            }
            if draft.orden != remoteDraft.orden { section["orden"] = max(1, draft.orden) }
            if draft.titulo != remoteDraft.titulo { section["titulo"] = draft.titulo }
            if draft.instrucciones != remoteDraft.instrucciones { section["instrucciones"] = draft.instrucciones }
            if draft.tipoPredominante != remoteDraft.tipoPredominante {
                setPruebaOptionalString(draft.tipoPredominante, key: "tipoPredominante", in: &section)
            }
            if draft.estimulo.map(\.contentFingerprint) != remoteDraft.estimulo.map(\.contentFingerprint) {
                section["estimulo"] = try mergePruebaBlocks(
                    draft.estimulo,
                    remoteValue: section["estimulo"],
                    remoteDrafts: remoteDraft.estimulo,
                    path: "secciones/\(match.draftIndex)/estimulo"
                )
            }
            if draft.items.map(\.contentFingerprint) != remoteDraft.items.map(\.contentFingerprint) {
                let itemResult = try mergePruebaItems(
                    draft.items,
                    remoteValue: section["items"],
                    remoteDrafts: remoteDraft.items,
                    path: "secciones/\(match.draftIndex)/items"
                )
                section["items"] = itemResult.value
                scoreChanged = scoreChanged || itemResult.scoreChanged
            }
            merged.append(section)
        }
        for index in remoteValues.indices where !claimed.contains(index) { merged.append(remoteValues[index]) }
        return (merged, scoreChanged)
    }

    private func encodePruebaItems(_ drafts: [PruebaItemDraft]) throws -> [Any] {
        var result: [Any] = []
        for draft in drafts where !draft.isDeleted {
            result.append(try encodePruebaItem(draft))
        }
        return result
    }

    private func encodePruebaItem(_ draft: PruebaItemDraft) throws -> [String: Any] {
        var item: [String: Any] = [
            "id": draft.documentId,
            "tipo": draft.type,
            "enunciado": draft.enunciado,
            "puntaje": max(0, draft.score)
        ]
        let resources = try encodePruebaBlocks(draft.resources)
        if !resources.isEmpty { item["recursos"] = resources }
        setPruebaOptionalString(draft.linkedOA, key: "oaVinculado", in: &item)
        setPruebaOptionalString(draft.habilidad, key: "habilidad", in: &item)
        try applyPruebaItemSpecific(draft, remote: nil, item: &item, path: "items/nuevo")
        return item
    }

    private func mergePruebaItems(
        _ drafts: [PruebaItemDraft],
        remoteValue: Any?,
        remoteDrafts: [PruebaItemDraft],
        path: String
    ) throws -> (value: [Any], scoreChanged: Bool) {
        let remoteValues = pruebaRawArray(remoteValue)
        var claimed = Set<Int>()
        var merged: [Any] = []
        var scoreChanged = false

        for draft in drafts {
            if draft.isNew {
                if !draft.isDeleted {
                    merged.append(try encodePruebaItem(draft))
                    scoreChanged = true
                }
                continue
            }
            let match = try pruebaMatch(
                sourceId: draft.sourceId,
                originalIndex: draft.originalIndex,
                baselineFingerprint: draft.baselineFingerprint,
                remoteValues: remoteValues,
                remoteDrafts: remoteDrafts,
                claimed: claimed,
                remoteSourceId: { $0.sourceId },
                remoteFingerprint: { $0.baselineFingerprint },
                path: "\(path)/\(draft.originalIndex.map { String($0) } ?? draft.documentId)"
            )
            claimed.insert(match.rawIndex)
            guard !draft.isDeleted else {
                scoreChanged = true
                continue
            }
            guard var item = remoteValues[match.rawIndex] as? [String: Any] else {
                throw EvaluacionesRepositoryError.editConflict(path: "\(path)/\(match.draftIndex)")
            }
            let remoteDraft = remoteDrafts[match.draftIndex]
            if draft.contentFingerprint == remoteDraft.contentFingerprint {
                merged.append(item)
                continue
            }
            if draft.isUnknown {
                merged.append(item)
                continue
            }
            if draft.type != remoteDraft.type { item["tipo"] = draft.type }
            if draft.enunciado != remoteDraft.enunciado { item["enunciado"] = draft.enunciado }
            if draft.score != remoteDraft.score {
                item["puntaje"] = max(0, draft.score)
                scoreChanged = true
            }
            if draft.linkedOA != remoteDraft.linkedOA {
                setPruebaOptionalString(draft.linkedOA, key: "oaVinculado", in: &item)
            }
            if draft.habilidad != remoteDraft.habilidad {
                setPruebaOptionalString(draft.habilidad, key: "habilidad", in: &item)
            }
            if draft.resources.map(\.contentFingerprint) != remoteDraft.resources.map(\.contentFingerprint) {
                item["recursos"] = try mergePruebaBlocks(
                    draft.resources,
                    remoteValue: item["recursos"],
                    remoteDrafts: remoteDraft.resources,
                    path: "\(path)/\(match.draftIndex)/recursos"
                )
            }
            try applyPruebaItemSpecific(
                draft,
                remote: remoteDraft,
                item: &item,
                path: "\(path)/\(match.draftIndex)"
            )
            merged.append(item)
        }
        for index in remoteValues.indices where !claimed.contains(index) { merged.append(remoteValues[index]) }
        return (merged, scoreChanged)
    }

    private func applyPruebaItemSpecific(
        _ draft: PruebaItemDraft,
        remote: PruebaItemDraft?,
        item: inout [String: Any],
        path: String
    ) throws {
        guard let type = PruebaEditorItemType.resolve(draft.type) else { return }
        let remoteHasSameType = remote.flatMap { PruebaEditorItemType.resolve($0.type) } == type
        switch type {
        case .seleccionMultiple:
            if remote == nil || !remoteHasSameType || draft.entriesA.map(\.contentFingerprint) != remote?.entriesA.map(\.contentFingerprint) {
                item["alternativas"] = try mergeOrEncodePruebaEntries(
                    draft.entriesA,
                    remoteValue: item["alternativas"],
                    remoteDrafts: remoteHasSameType ? remote?.entriesA ?? [] : [],
                    style: .alternative,
                    path: "\(path)/alternativas"
                )
            }
        case .verdaderoFalso:
            if remote == nil || !remoteHasSameType || draft.respuestaCorrecta != remote?.respuestaCorrecta {
                setPruebaAlias(draft.respuestaCorrecta, canonical: "respuestaCorrecta", aliases: ["correcta"], in: &item)
            }
            if remote == nil || !remoteHasSameType || draft.pideJustificacion != remote?.pideJustificacion {
                item["pideJustificacion"] = draft.pideJustificacion
            }
        case .pareados:
            if remote == nil || !remoteHasSameType || draft.entriesA.map(\.contentFingerprint) != remote?.entriesA.map(\.contentFingerprint) {
                item["columnaA"] = try mergeOrEncodePruebaEntries(
                    draft.entriesA, remoteValue: item["columnaA"],
                    remoteDrafts: remoteHasSameType ? remote?.entriesA ?? [] : [],
                    style: .pairA, path: "\(path)/columnaA"
                )
            }
            if remote == nil || !remoteHasSameType || draft.entriesB.map(\.contentFingerprint) != remote?.entriesB.map(\.contentFingerprint) {
                item["columnaB"] = try mergeOrEncodePruebaEntries(
                    draft.entriesB, remoteValue: item["columnaB"],
                    remoteDrafts: remoteHasSameType ? remote?.entriesB ?? [] : [],
                    style: .pairB, path: "\(path)/columnaB"
                )
            }
        case .ordenar:
            if remote == nil || !remoteHasSameType || draft.entriesA.map(\.contentFingerprint) != remote?.entriesA.map(\.contentFingerprint) {
                item["pasos"] = try mergeOrEncodePruebaEntries(
                    draft.entriesA, remoteValue: item["pasos"],
                    remoteDrafts: remoteHasSameType ? remote?.entriesA ?? [] : [],
                    style: .step, path: "\(path)/pasos"
                )
            }
        case .completar:
            if remote == nil || !remoteHasSameType || draft.textoConBlancos != remote?.textoConBlancos {
                item["textoConBlancos"] = draft.textoConBlancos
            }
            if remote == nil || !remoteHasSameType || draft.respuestas != remote?.respuestas {
                // Las respuestas son posicionales respecto de cada `__`; los vacíos
                // representan blancos aún no resueltos y no se pueden compactar.
                item["respuestas"] = draft.respuestas
            }
            if remote == nil || !remoteHasSameType || draft.wordBank != remote?.wordBank {
                if draft.wordBank.isEmpty { item.removeValue(forKey: "bancoPalabras") }
                else { item["bancoPalabras"] = draft.wordBank }
            }
        case .respuestaCorta:
            if remote == nil || !remoteHasSameType || draft.respuestaEsperada != remote?.respuestaEsperada {
                setPruebaOptionalString(draft.respuestaEsperada, key: "respuestaEsperada", in: &item)
            }
            if remote == nil || !remoteHasSameType || draft.lineasRespuesta != remote?.lineasRespuesta {
                item["lineasRespuesta"] = max(1, draft.lineasRespuesta)
            }
        case .desarrollo:
            if remote == nil || !remoteHasSameType || draft.lineasRespuesta != remote?.lineasRespuesta {
                item["lineasRespuesta"] = max(1, draft.lineasRespuesta)
            }
            if remote == nil || !remoteHasSameType || draft.pautaCorreccion != remote?.pautaCorreccion {
                setPruebaOptionalString(draft.pautaCorreccion, key: "pautaCorreccion", in: &item)
            }
            if remote == nil || !remoteHasSameType || draft.entriesA.map(\.contentFingerprint) != remote?.entriesA.map(\.contentFingerprint) {
                let criteria = try mergeOrEncodePruebaEntries(
                    draft.entriesA, remoteValue: item["criterios"],
                    remoteDrafts: remoteHasSameType ? remote?.entriesA ?? [] : [],
                    style: .criterion, path: "\(path)/criterios"
                )
                if criteria.isEmpty { item.removeValue(forKey: "criterios") }
                else { item["criterios"] = criteria }
            }
        }
    }

    private func encodePruebaBlocks(_ drafts: [GuiaBlockDraft]) throws -> [Any] {
        drafts.filter { !$0.isDeleted }.map(encodePruebaBlock)
    }

    private func encodePruebaBlock(_ draft: GuiaBlockDraft) -> [String: Any] {
        var data: [String: Any] = [:]
        switch draft.type {
        case "texto":
            data["html"] = draft.html
            data["estilo"] = draft.style
        case "imagen":
            data["url"] = draft.url
            setPruebaOptionalString(draft.storagePath, key: "storagePath", in: &data)
            setPruebaOptionalString(draft.alt, key: "alt", in: &data)
            setPruebaOptionalString(draft.caption, key: "caption", in: &data)
            data["ancho"] = draft.width
            data["alineacion"] = draft.alignment
        case "tabla":
            data["cabeceras"] = draft.headers
            data["filas"] = draft.rows
            data["primeraColumnaCabecera"] = draft.firstColumnHeader
        case "separador":
            data["estilo"] = draft.separatorStyle
        default:
            break
        }
        return ["id": draft.documentId, "tipo": draft.type, "data": data]
    }

    private func mergePruebaBlocks(
        _ drafts: [GuiaBlockDraft],
        remoteValue: Any?,
        remoteDrafts: [GuiaBlockDraft],
        path: String
    ) throws -> [Any] {
        let remoteValues = pruebaRawArray(remoteValue)
        var claimed = Set<Int>()
        var merged: [Any] = []
        for draft in drafts {
            if draft.isNew {
                if !draft.isDeleted { merged.append(encodePruebaBlock(draft)) }
                continue
            }
            let match = try pruebaMatch(
                sourceId: pruebaBlockSourceId(draft),
                originalIndex: draft.originalIndex,
                baselineFingerprint: draft.baselineFingerprint,
                remoteValues: remoteValues,
                remoteDrafts: remoteDrafts,
                claimed: claimed,
                remoteSourceId: pruebaBlockSourceId,
                remoteFingerprint: { $0.baselineFingerprint },
                path: "\(path)/\(draft.originalIndex.map { String($0) } ?? draft.documentId)"
            )
            claimed.insert(match.rawIndex)
            guard !draft.isDeleted else { continue }
            guard var block = remoteValues[match.rawIndex] as? [String: Any] else {
                throw EvaluacionesRepositoryError.editConflict(path: "\(path)/\(match.draftIndex)")
            }
            let remoteDraft = remoteDrafts[match.draftIndex]
            if draft.contentFingerprint == remoteDraft.contentFingerprint || draft.isUnknown {
                merged.append(block)
                continue
            }
            if draft.type != remoteDraft.type { block["tipo"] = draft.type }
            var data = (block["data"] as? [String: Any]) ?? [:]
            switch draft.type {
            case "texto":
                if draft.html != remoteDraft.html { data["html"] = draft.html }
                if draft.style != remoteDraft.style { data["estilo"] = draft.style }
            case "imagen":
                if draft.url != remoteDraft.url { data["url"] = draft.url }
                if draft.storagePath != remoteDraft.storagePath { setPruebaOptionalString(draft.storagePath, key: "storagePath", in: &data) }
                if draft.alt != remoteDraft.alt { setPruebaOptionalString(draft.alt, key: "alt", in: &data) }
                if draft.caption != remoteDraft.caption { setPruebaOptionalString(draft.caption, key: "caption", in: &data) }
                if draft.width != remoteDraft.width { data["ancho"] = draft.width }
                if draft.alignment != remoteDraft.alignment { data["alineacion"] = draft.alignment }
            case "tabla":
                if draft.headers != remoteDraft.headers { data["cabeceras"] = draft.headers }
                if draft.rows != remoteDraft.rows { data["filas"] = draft.rows }
                if draft.firstColumnHeader != remoteDraft.firstColumnHeader {
                    data["primeraColumnaCabecera"] = draft.firstColumnHeader
                }
            case "separador":
                if draft.separatorStyle != remoteDraft.separatorStyle { data["estilo"] = draft.separatorStyle }
            default:
                merged.append(block)
                continue
            }
            block["data"] = data
            merged.append(block)
        }
        for index in remoteValues.indices where !claimed.contains(index) { merged.append(remoteValues[index]) }
        return merged
    }

    private enum PruebaEntryStyle {
        case alternative
        case pairA
        case pairB
        case step
        case criterion
    }

    private func mergeOrEncodePruebaEntries(
        _ drafts: [PruebaItemEntryDraft],
        remoteValue: Any?,
        remoteDrafts: [PruebaItemEntryDraft],
        style: PruebaEntryStyle,
        path: String
    ) throws -> [Any] {
        let remoteValues = pruebaRawArray(remoteValue)
        if remoteDrafts.isEmpty {
            return drafts.filter { !$0.isDeleted }.map { encodePruebaEntry($0, style: style) } + remoteValues
        }
        var claimed = Set<Int>()
        var merged: [Any] = []
        for draft in drafts {
            if draft.isNew {
                if !draft.isDeleted { merged.append(encodePruebaEntry(draft, style: style)) }
                continue
            }
            let match = try pruebaMatch(
                sourceId: draft.sourceId,
                originalIndex: draft.originalIndex,
                baselineFingerprint: draft.baselineFingerprint,
                remoteValues: remoteValues,
                remoteDrafts: remoteDrafts,
                claimed: claimed,
                remoteSourceId: { $0.sourceId },
                remoteFingerprint: { $0.baselineFingerprint },
                path: "\(path)/\(draft.originalIndex.map { String($0) } ?? draft.documentId)"
            )
            claimed.insert(match.rawIndex)
            guard !draft.isDeleted else { continue }
            guard var entry = remoteValues[match.rawIndex] as? [String: Any] else {
                throw EvaluacionesRepositoryError.editConflict(path: "\(path)/\(match.draftIndex)")
            }
            let remoteDraft = remoteDrafts[match.draftIndex]
            if draft.contentFingerprint == remoteDraft.contentFingerprint {
                merged.append(entry)
                continue
            }
            if draft.text != remoteDraft.text { entry["texto"] = draft.text }
            switch style {
            case .alternative:
                if draft.correct != remoteDraft.correct {
                    setPruebaAlias(draft.correct, canonical: "esCorrecta", aliases: ["correcta"], in: &entry)
                }
                if draft.imageURL != remoteDraft.imageURL {
                    setPruebaOptionalString(draft.imageURL, key: "imagenUrl", in: &entry)
                }
                if draft.imageStoragePath != remoteDraft.imageStoragePath {
                    setPruebaOptionalString(draft.imageStoragePath, key: "imagenStoragePath", in: &entry)
                }
            case .pairA:
                if draft.imageURL != remoteDraft.imageURL {
                    setPruebaOptionalString(draft.imageURL, key: "imagenUrl", in: &entry)
                }
            case .pairB:
                if draft.linkedId != remoteDraft.linkedId {
                    setPruebaAlias(
                        draft.linkedId,
                        canonical: "correctaParaAId",
                        aliases: ["pareCon"],
                        in: &entry
                    )
                }
            case .step:
                break
            case .criterion:
                if draft.score != remoteDraft.score { entry["puntaje"] = max(0, draft.score) }
            }
            merged.append(entry)
        }
        for index in remoteValues.indices where !claimed.contains(index) { merged.append(remoteValues[index]) }
        return merged
    }

    private func encodePruebaEntry(_ draft: PruebaItemEntryDraft, style: PruebaEntryStyle) -> [String: Any] {
        var entry: [String: Any] = ["id": draft.documentId, "texto": draft.text]
        switch style {
        case .alternative:
            entry["esCorrecta"] = draft.correct
            setPruebaOptionalString(draft.imageURL, key: "imagenUrl", in: &entry)
            setPruebaOptionalString(draft.imageStoragePath, key: "imagenStoragePath", in: &entry)
        case .pairA:
            setPruebaOptionalString(draft.imageURL, key: "imagenUrl", in: &entry)
        case .pairB:
            entry["correctaParaAId"] = draft.linkedId
        case .step:
            break
        case .criterion:
            entry["puntaje"] = max(0, draft.score)
        }
        return entry
    }

    private func setPruebaAlias(
        _ value: Any,
        canonical: String,
        aliases: [String],
        in dictionary: inout [String: Any]
    ) {
        let keys = [canonical] + aliases
        let present = keys.filter { dictionary[$0] != nil }
        for key in present.isEmpty ? [canonical] : present { dictionary[key] = value }
    }

    // MARK: - Guias (lectura lossless)

    /// Evita `orderBy(createdAt)` para incluir guias heredadas sin ese campo.
    /// Igual que Pruebas, respeta exclusivamente el usuario y colegio activos.
    func cargarGuias(curso: String, scope: EvaluacionScope) async throws -> GuiasCargaResultado {
        try validate(scope: scope)
        let uid = try getUid()
        let snapshot = try await getDocuments(scopedCol(uid: uid, scope: scope, name: "guias"))
        let fromCache = snapshot.metadata.isFromCache
        var warnings = 0

        let guides = snapshot.documents.compactMap { document -> GuiaTemplate? in
            let guide = GuiaDocumentParser.guia(
                id: document.documentID,
                dictionary: document.data(),
                scope: scope,
                isFromCache: fromCache
            )
            guard Self.coincide(guide.curso, curso) else { return nil }
            if !guide.issues.isEmpty || guide.tieneContenidoDesconocido { warnings += 1 }
            return guide
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.fechaActualizacion ?? lhs.fechaCreacion ?? .distantPast
            let rhsDate = rhs.fechaActualizacion ?? rhs.fechaCreacion ?? .distantPast
            if lhsDate == rhsDate { return lhs.id > rhs.id }
            return lhsDate > rhsDate
        }

        return GuiasCargaResultado(guias: guides, isFromCache: fromCache, warningCount: warnings)
    }

    func cargarGuia(id: String, scope: EvaluacionScope) async throws -> GuiaTemplate? {
        try validate(scope: scope)
        let uid = try getUid()
        let snapshot = try await getDocument(scopedDoc(uid: uid, scope: scope, collection: "guias", id: id))
        guard snapshot.exists else { return nil }
        guard let dictionary = snapshot.data() else {
            throw EvaluacionesRepositoryError.invalidDocument(collection: "guias", id: id)
        }
        return GuiaDocumentParser.guia(
            id: snapshot.documentID,
            dictionary: dictionary,
            scope: scope,
            isFromCache: snapshot.metadata.isFromCache
        )
    }

    /// Guarda solo campos de cabecera editables. Las secciones, bloques, actividades,
    /// metadatos curriculares y campos futuros del documento quedan intactos.
    @discardableResult
    func guardarGuiaEditor(_ draft: GuiaEditorDraft, scope: EvaluacionScope) async throws -> String {
        try validate(scope: scope)
        let uid = try getUid()
        let isNew = draft.id == nil
        let id = draft.id ?? "guia_\(Self.normalizarClave(draft.asignatura))_\(Self.normalizarClave(draft.curso))_\(UUID().uuidString.lowercased())"
        let reference = scopedDoc(uid: uid, scope: scope, collection: "guias", id: id)

        var currentData: [String: Any] = [:]
        if !isNew {
            let current = try await getDocument(reference)
            guard current.exists else {
                throw EvaluacionesRepositoryError.invalidDocument(collection: "guias", id: id)
            }
            guard let data = current.data() else {
                throw EvaluacionesRepositoryError.invalidDocument(collection: "guias", id: id)
            }
            currentData = data
        }

        var payload: [String: Any] = [
            "nombre": draft.nombre.trimmingCharacters(in: .whitespacesAndNewlines),
            "asignatura": draft.asignatura.trimmingCharacters(in: .whitespacesAndNewlines),
            "curso": draft.curso.trimmingCharacters(in: .whitespacesAndNewlines),
            "tipoGuia": draft.tipoGuia,
            "tiempoMinutos": max(1, draft.tiempoMinutos),
            "objetivo": draft.objetivo,
            "instrucciones": draft.instrucciones.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            "estado": draft.estado,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        payload["secciones"] = mergedSections(draft.secciones, currentValue: currentData["secciones"])
        payload["cierre"] = mergedBlocks(draft.cierre, currentValue: currentData["cierre"])
        payload["puntajeMaximo"] = draft.secciones
            .flatMap(\.actividades)
            .filter { !$0.isDeleted }
            .compactMap(\.score)
            .reduce(0, +)
        if let oas = draft.oas {
            payload["oas"] = oas.compactMap { $0.dictionary }
            let metadata = ListaCotejoMetadatos.desde(oas: oas) ?? ListaCotejoMetadatos(
                objetivos: [], indicadores: [], objetivosTransversales: []
            )
            payload["metadatosCurriculares"] = metadata.dictionary ?? [
                "objetivos": [], "indicadores": [], "objetivosTransversales": []
            ]
        }
        payload["unidadId"] = nullableString(draft.unidadId)
        payload["unidadNombre"] = nullableString(draft.unidadNombre)
        payload["numeroGuia"] = nullableString(draft.numeroGuia)
        payload["docenteNombre"] = nullableString(draft.docenteNombre)
        if isNew {
            payload["createdAt"] = FieldValue.serverTimestamp()
            if draft.oas == nil {
                payload["metadatosCurriculares"] = [
                    "objetivos": [], "indicadores": [], "objetivosTransversales": []
                ]
            }
        }
        try await setData(payload, at: reference, merge: true)
        return id
    }

    /// Construye la misma representación canónica que se guardaría, sin escribir en Firestore.
    /// Permite exportar también cambios todavía no guardados desde el editor.
    func prepararGuiaParaExportar(
        _ draft: GuiaEditorDraft,
        scope: EvaluacionScope,
        base: GuiaTemplate?
    ) -> GuiaTemplate {
        var data = base?.raw ?? [:]
        let currentSections = data["secciones"]
        let currentClosing = data["cierre"]

        data["nombre"] = draft.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        data["asignatura"] = draft.asignatura.trimmingCharacters(in: .whitespacesAndNewlines)
        data["curso"] = draft.curso.trimmingCharacters(in: .whitespacesAndNewlines)
        data["tipoGuia"] = draft.tipoGuia
        data["tiempoMinutos"] = max(1, draft.tiempoMinutos)
        data["objetivo"] = draft.objetivo
        data["instrucciones"] = cleanStrings(draft.instrucciones)
        data["estado"] = draft.estado
        data["secciones"] = mergedSections(draft.secciones, currentValue: currentSections)
        data["cierre"] = mergedBlocks(draft.cierre, currentValue: currentClosing)
        data["puntajeMaximo"] = draft.secciones
            .flatMap(\.actividades)
            .filter { !$0.isDeleted }
            .compactMap(\.score)
            .reduce(0, +)

        setOptionalString(draft.unidadId, key: "unidadId", in: &data)
        setOptionalString(draft.unidadNombre, key: "unidadNombre", in: &data)
        setOptionalString(draft.numeroGuia, key: "numeroGuia", in: &data)
        setOptionalString(draft.docenteNombre, key: "docenteNombre", in: &data)

        if let oas = draft.oas {
            data["oas"] = oas.compactMap { $0.dictionary }
            let metadata = ListaCotejoMetadatos.desde(oas: oas) ?? ListaCotejoMetadatos(
                objetivos: [], indicadores: [], objetivosTransversales: []
            )
            data["metadatosCurriculares"] = metadata.dictionary ?? [
                "objetivos": [], "indicadores": [], "objetivosTransversales": []
            ]
        }

        return GuiaDocumentParser.guia(
            id: draft.id ?? "guia_preview",
            dictionary: data,
            scope: scope,
            isFromCache: false
        )
    }

    func eliminarGuia(id: String, scope: EvaluacionScope) async throws {
        try validate(scope: scope)
        let uid = try getUid()
        try await deleteDocument(scopedDoc(uid: uid, scope: scope, collection: "guias", id: id))
    }

    func duplicarGuia(_ guide: GuiaTemplate, cursoDestino: String, scope: EvaluacionScope) async throws -> String {
        try validate(scope: scope)
        let uid = try getUid()
        let id = "guia_\(Self.normalizarClave(guide.asignatura))_\(Self.normalizarClave(cursoDestino))_\(UUID().uuidString.lowercased())"
        var payload = guide.raw
        payload.removeValue(forKey: "id")
        payload["nombre"] = "\(guide.nombre.isEmpty ? "Guía" : guide.nombre) (copia)"
        payload["curso"] = cursoDestino
        payload["estado"] = "borrador"
        payload["createdAt"] = FieldValue.serverTimestamp()
        payload["updatedAt"] = FieldValue.serverTimestamp()
        payload["secciones"] = regeneratedSections(payload["secciones"])
        payload["cierre"] = regeneratedBlocks(payload["cierre"])
        try await setData(payload, at: scopedDoc(uid: uid, scope: scope, collection: "guias", id: id), merge: false)
        return id
    }

    private func nullableString(_ value: String) -> Any {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? FieldValue.delete() : clean
    }

    private func setOptionalString(_ value: String, key: String, in dictionary: inout [String: Any]) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { dictionary.removeValue(forKey: key) }
        else { dictionary[key] = clean }
    }

    private func regeneratedSections(_ value: Any?) -> [[String: Any]] {
        guard let sections = value as? [[String: Any]] else { return [] }
        return sections.map { section in
            var copy = section
            copy["id"] = "sec_\(UUID().uuidString.lowercased())"
            if let activities = section["actividades"] as? [[String: Any]] {
                copy["actividades"] = activities.map { activity in
                    var item = activity
                    let type = (activity["tipo"] as? String) ?? "actividad"
                    item["id"] = "\(type)_\(UUID().uuidString.lowercased())"
                    item["recursos"] = regeneratedBlocks(activity["recursos"])
                    return item
                }
            }
            copy["contenido"] = regeneratedBlocks(section["contenido"])
            return copy
        }
    }

    private func regeneratedBlocks(_ value: Any?) -> [[String: Any]] {
        guard let blocks = value as? [[String: Any]] else { return [] }
        return blocks.map { block in
            var copy = block
            copy["id"] = "bloque_\(UUID().uuidString.lowercased())"
            return copy
        }
    }

    private func mergedSections(_ drafts: [GuiaSectionDraft], currentValue: Any?) -> [[String: Any]] {
        let current = (currentValue as? [[String: Any]]) ?? []
        let idCounts = current.reduce(into: [String: Int]()) { result, section in
            guard let id = section["id"] as? String, !id.isEmpty else { return }
            result[id, default: 0] += 1
        }
        func currentIndex(for draft: GuiaSectionDraft) -> Int? {
            if idCounts[draft.documentId] == 1 {
                return current.firstIndex { ($0["id"] as? String) == draft.documentId }
            }
            return draft.originalIndex.flatMap { current.indices.contains($0) ? $0 : nil }
        }

        let claimedIndexes = Set(drafts.compactMap { currentIndex(for: $0) })
        var merged = drafts.enumerated().map { index, draft in
            var section = currentIndex(for: draft).map { current[$0] } ?? [:]
            section["id"] = draft.documentId
            section["orden"] = index + 1
            section["titulo"] = draft.titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Sección \(index + 1)" : draft.titulo
            if draft.descripcion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                section.removeValue(forKey: "descripcion")
            } else {
                section["descripcion"] = draft.descripcion
            }
            section["contenido"] = mergedBlocks(draft.bloques, currentValue: section["contenido"])
            section["actividades"] = mergedActivities(draft.actividades, currentValue: section["actividades"])
            return section
        }
        for (index, section) in current.enumerated() {
            guard !claimedIndexes.contains(index) else { continue }
            merged.append(section)
        }
        return merged
    }

    private func mergedBlocks(_ drafts: [GuiaBlockDraft], currentValue: Any?) -> [[String: Any]] {
        let current = (currentValue as? [[String: Any]]) ?? []
        let idCounts = current.reduce(into: [String: Int]()) { result, block in
            guard let id = block["id"] as? String, !id.isEmpty else { return }
            result[id, default: 0] += 1
        }
        func currentIndex(for draft: GuiaBlockDraft) -> Int? {
            if idCounts[draft.documentId] == 1 {
                return current.firstIndex { ($0["id"] as? String) == draft.documentId }
            }
            return draft.originalIndex.flatMap { current.indices.contains($0) ? $0 : nil }
        }

        let claimedIndexes = Set(drafts.compactMap { currentIndex(for: $0) })
        var merged = drafts.compactMap { draft -> [String: Any]? in
            if draft.isDeleted { return nil }
            let original = currentIndex(for: draft).map { current[$0] }
            if !draft.isNew, draft.contentFingerprint == draft.baselineFingerprint { return original }
            if draft.isUnknown { return original }
            var block = original ?? [:]
            var data = (block["data"] as? [String: Any]) ?? [:]
            block["id"] = draft.documentId
            block["tipo"] = draft.type
            switch draft.type {
            case "texto":
                data["html"] = draft.html
                data["estilo"] = draft.style
            case "imagen":
                data["url"] = draft.url
                if draft.storagePath.isEmpty { data.removeValue(forKey: "storagePath") } else { data["storagePath"] = draft.storagePath }
                if draft.alt.isEmpty { data.removeValue(forKey: "alt") } else { data["alt"] = draft.alt }
                if draft.caption.isEmpty { data.removeValue(forKey: "caption") } else { data["caption"] = draft.caption }
                data["ancho"] = draft.width
                data["alineacion"] = draft.alignment
            case "tabla":
                data["cabeceras"] = draft.headers
                data["filas"] = draft.rows.map { row in
                    Array(row.prefix(draft.headers.count)) + Array(repeating: "", count: max(0, draft.headers.count - row.count))
                }
                data["primeraColumnaCabecera"] = draft.firstColumnHeader
            case "separador":
                data["estilo"] = draft.separatorStyle
            default:
                return original
            }
            block["data"] = data
            return block
        }
        for (index, block) in current.enumerated() {
            guard !claimedIndexes.contains(index) else { continue }
            merged.append(block)
        }
        return merged
    }

    // MARK: - Sincronización con Calificaciones

    private func mergedActivities(_ drafts: [GuiaActivityDraft], currentValue: Any?) -> [[String: Any]] {
        let current = (currentValue as? [[String: Any]]) ?? []
        let idCounts = current.reduce(into: [String: Int]()) { result, activity in
            guard let id = activity["id"] as? String, !id.isEmpty else { return }
            result[id, default: 0] += 1
        }
        func currentIndex(for draft: GuiaActivityDraft) -> Int? {
            if idCounts[draft.documentId] == 1 {
                return current.firstIndex { ($0["id"] as? String) == draft.documentId }
            }
            return draft.originalIndex.flatMap { current.indices.contains($0) ? $0 : nil }
        }

        let claimedIndexes = Set(drafts.compactMap { currentIndex(for: $0) })
        var merged = drafts.filter { !$0.isDeleted }.enumerated().compactMap { number, draft -> [String: Any]? in
            let original = currentIndex(for: draft).map { current[$0] }
            if !draft.isNew, draft.contentFingerprint == draft.baselineFingerprint { return original }
            if draft.isUnknown { return original }
            var activity = original ?? [:]
            var data = (activity["datos"] as? [String: Any]) ?? [:]
            activity["id"] = draft.documentId
            activity["tipo"] = draft.type
            activity["numero"] = number + 1
            activity["enunciado"] = draft.prompt
            if let score = draft.score { activity["puntaje"] = max(0, score) } else { activity.removeValue(forKey: "puntaje") }
            activity["recursos"] = mergedBlocks(draft.resources, currentValue: activity["recursos"])
            if draft.linkedOA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                activity.removeValue(forKey: "oaVinculado")
            } else {
                activity["oaVinculado"] = draft.linkedOA
            }
            data["tipo"] = draft.type

            switch draft.type {
            case "seleccion_multiple":
                data["alternativas"] = mergedActivityEntries(draft.entriesA, currentValue: data["alternativas"], style: "option")
            case "encerrar", "marcar":
                data["opciones"] = mergedActivityEntries(draft.entriesA, currentValue: data["opciones"], style: "option")
            case "verdadero_falso":
                data["afirmaciones"] = mergedActivityEntries(draft.entriesA, currentValue: data["afirmaciones"], style: "affirmation")
            case "completar":
                data["texto"] = draft.text
                data["respuestas"] = cleanStrings(draft.answers)
                data["banco"] = cleanStrings(draft.wordBank)
            case "respuesta_corta":
                data["lineas"] = max(1, draft.lines)
                if draft.suggestedAnswer.isEmpty { data.removeValue(forKey: "respuestaSugerida") } else { data["respuestaSugerida"] = draft.suggestedAnswer }
            case "ordenar":
                data["pasos"] = mergedActivityEntries(draft.entriesA, currentValue: data["pasos"], style: "step")
            case "pareados":
                data["columnaA"] = mergedActivityEntries(draft.entriesA, currentValue: data["columnaA"], style: "pairA")
                data["columnaB"] = mergedActivityEntries(draft.entriesB, currentValue: data["columnaB"], style: "pairB")
            case "colorear":
                data["instruccion"] = draft.instruction
                if draft.imageUrl.isEmpty { data.removeValue(forKey: "imagenUrl") } else { data["imagenUrl"] = draft.imageUrl }
            case "dibujar":
                data["instruccion"] = draft.instruction
                data["alturaCm"] = max(1, draft.heightCm)
            case "investigar":
                data["instruccion"] = draft.instruction
                data["lineasRespuesta"] = max(1, draft.lines)
            case "sopa_letras":
                data["palabras"] = cleanStrings(draft.words)
                data["tamañoCuadro"] = min(20, max(4, draft.gridSize))
            case "abierta":
                data["lineasRespuesta"] = max(1, draft.lines)
            default:
                return original
            }
            activity["datos"] = data
            return activity
        }
        for (index, activity) in current.enumerated() where !claimedIndexes.contains(index) {
            merged.append(activity)
        }
        return merged
    }

    private func mergedActivityEntries(
        _ drafts: [GuiaActivityEntryDraft], currentValue: Any?, style: String
    ) -> [[String: Any]] {
        let current = (currentValue as? [[String: Any]]) ?? []
        let idCounts = current.reduce(into: [String: Int]()) { result, entry in
            guard let id = entry["id"] as? String, !id.isEmpty else { return }
            result[id, default: 0] += 1
        }
        func currentIndex(for draft: GuiaActivityEntryDraft) -> Int? {
            if idCounts[draft.documentId] == 1 {
                return current.firstIndex { ($0["id"] as? String) == draft.documentId }
            }
            return draft.originalIndex.flatMap { current.indices.contains($0) ? $0 : nil }
        }

        let claimedIndexes = Set(drafts.compactMap { currentIndex(for: $0) })
        var merged = drafts.filter { !$0.isDeleted }.enumerated().map { order, draft in
            let original = currentIndex(for: draft).map { current[$0] }
            if !draft.isNew, draft.contentFingerprint == draft.baselineFingerprint { return original ?? [:] }
            var entry = original ?? [:]
            entry["id"] = draft.documentId
            entry["texto"] = draft.text
            switch style {
            case "option":
                entry["correcta"] = draft.correct
                if draft.imageUrl.isEmpty { entry.removeValue(forKey: "imagenUrl") } else { entry["imagenUrl"] = draft.imageUrl }
            case "affirmation": entry["correcta"] = draft.correct
            case "step": entry["numeroCorrecto"] = max(1, draft.correctOrder)
            case "pairB":
                if draft.linkedId.isEmpty { entry.removeValue(forKey: "pareCon") } else { entry["pareCon"] = draft.linkedId }
            default: break
            }
            if style == "step", entry["numeroCorrecto"] == nil { entry["numeroCorrecto"] = order + 1 }
            return entry
        }
        for (index, entry) in current.enumerated() where !claimedIndexes.contains(index) { merged.append(entry) }
        return merged
    }

    private func cleanStrings(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func sincronizarPruebaConCalificaciones(
        prueba: PruebaTemplate,
        aplicacion: PruebaApplicationDraft,
        roster: [EstudiantePerfil],
        scope: EvaluacionScope,
        sobrescribir: Bool
    ) async throws -> SyncCalificacionesResultado {
        try validate(scope: scope)
        guard prueba.scope == scope,
              aplicacion.pruebaId == prueba.id else {
            throw EvaluacionesRepositoryError.mismatchedApplication(
                expected: prueba.id,
                actual: aplicacion.pruebaId
            )
        }

        let evaluacionId = "apl_\(prueba.id)"
        var calculatedNotes: [String: (nombre: String, nota: String)] = [:]
        var studentsWithoutNote = 0

        for storedResult in aplicacion.resultados {
            guard !storedResult.ausente else { continue }
            guard storedResult.hasAnyResponse || storedResult.completado else {
                studentsWithoutNote += 1
                continue
            }
            guard let studentId = storedResult.sourceId else { continue }
            var result = storedResult
            result.recalculate(with: prueba)
            calculatedNotes[studentId] = (
                result.nombre,
                String(format: "%.1f", result.nota ?? 1)
            )
        }

        var oaIds: [String] = []
        var seenOAIds = Set<String>()
        func appendOA(_ raw: String?) {
            guard let raw else { return }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seenOAIds.insert(value).inserted else { return }
            oaIds.append(value)
        }
        prueba.oas?.filter(\.seleccionado).forEach { appendOA($0.id) }
        prueba.secciones.forEach { section in
            section.items.forEach { appendOA($0.oaVinculado) }
        }

        let normalizedType = Self.normalizarClave(prueba.tipoEvaluacion)
        let gradeType: String
        switch normalizedType {
        case "formativa": gradeType = "formativa"
        case "diagnostica": gradeType = "diagnostica"
        default: gradeType = "sumativa"
        }

        return try await aplicarSincronizacion(
            asignatura: prueba.asignatura,
            curso: prueba.curso,
            evaluacionId: evaluacionId,
            label: prueba.nombre.isEmpty ? "Prueba" : prueba.nombre,
            unidadId: prueba.unidadId,
            oaIds: oaIds,
            notasCalculadas: calculatedNotes,
            estudiantesSinNota: studentsWithoutNote,
            roster: roster,
            sobrescribir: sobrescribir,
            scope: scope,
            tipo: gradeType,
            ponderacion: prueba.ponderacion
        )
    }

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
        sobrescribir: Bool,
        scope: EvaluacionScope = .principal,
        tipo: String = "sumativa",
        ponderacion: Double? = nil
    ) async throws -> SyncCalificacionesResultado {
        let calId = Self.buildCalificacionesId(asignatura: asignatura, curso: curso)
        try validate(scope: scope)
        let ref = scopedDoc(
            uid: try getUid(),
            scope: scope,
            collection: "calificaciones",
            id: calId
        )
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
            "tipo": tipo,
            "periodo": Self.periodoActual(),
            "oaIds": oaIds
        ]
        if let unidadId, !unidadId.isEmpty { evalEntry["unidadId"] = unidadId }
        if let ponderacion { evalEntry["ponderacion"] = ponderacion }

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
    case invalidDocument(collection: String, id: String)
    case mismatchedApplication(expected: String, actual: String)
    case invalidScope
    case editConflict(path: String)
    case applicationEditConflict(path: String)
    case appliedTestReadOnly

    var errorDescription: String? {
        switch self {
        case .encoding: return "No se pudo preparar el documento para guardar."
        case .invalidDocument(let collection, let id):
            return "El documento \(collection)/\(id) existe, pero no se pudo leer."
        case .mismatchedApplication(let expected, let actual):
            return "La aplicación pertenece a otra prueba (esperada \(expected), recibida \(actual))."
        case .invalidScope:
            return "El identificador del colegio activo no es válido."
        case .editConflict(let path):
            return "La prueba cambió en otro dispositivo o en EduPanel web (\(path)). Recárgala antes de guardar."
        case .applicationEditConflict(let path):
            return "Los resultados cambiaron en otro dispositivo o en EduPanel web (\(path)). Recárgalos antes de guardar."
        case .appliedTestReadOnly:
            return "Una prueba aplicada es de solo lectura. Duplica la prueba para crear una nueva versión."
        }
    }
}
