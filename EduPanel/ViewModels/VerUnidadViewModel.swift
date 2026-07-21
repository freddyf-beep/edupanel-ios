import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

@MainActor
@Observable
final class VerUnidadViewModel {
    var verUnidad: VerUnidadGuardada? = nil
    var cronograma: CronogramaUnidadData? = nil
    var clasesActividades: [Int: ActividadClase] = [:] // key: numeroClase
    var snapshot: DashboardSnapshot? = nil
    
    var activeSubject = "M\u{00FA}sica"
    var curso = ""
    var unidadId = ""
    var courseID: String?
    var subjectID: String?
    
    var isLoading = false
    var isReloadingActivities = false
    var isSaving = false
    var saveStatus = ""
    var activitySyncStatus = ""
    var loadErrorMessage: String?
    
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository
    private let curriculoRepository = CurriculoRepository()
    @ObservationIgnored private var activitySaveTokens: [Int: UUID] = [:]
    @ObservationIgnored private var persistedActivityClassNumbers = Set<Int>()
    @ObservationIgnored private var pendingActivityClassNumbers = Set<Int>()
    @ObservationIgnored private var activitySyncErrorClassNumbers = Set<Int>()
    @ObservationIgnored private var activityLoadErrorClassNumbers = Set<Int>()
    @ObservationIgnored private var saveAllOperationToken: UUID?
    @ObservationIgnored private var saveAllPendingAcknowledgements = 0
    @ObservationIgnored private var saveAllHadError = false
    @ObservationIgnored private var requestedCurso = ""
    @ObservationIgnored private var requestedUnidadId = ""
    @ObservationIgnored private var requestedAsignatura: String?

    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
    }
    
    func load(curso: String, unidadId: String, asignatura: String? = nil) async {
        guard !isLoading else { return }
        requestedCurso = curso
        requestedUnidadId = unidadId
        requestedAsignatura = asignatura
        self.curso = curso
        self.unidadId = unidadId
        self.isLoading = true
        self.saveStatus = ""
        self.activitySyncStatus = ""
        self.loadErrorMessage = nil
        
        do {
            let snap = try await dashboardRepository.fetchDashboard()
            self.snapshot = snap
            self.courseID = snap.course(id: nil, named: curso)?.courseID
            let providedSubject = asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let subjectCandidates: [String]
            if !providedSubject.isEmpty {
                subjectCandidates = [providedSubject]
                self.activeSubject = providedSubject
            } else {
                var candidates = snap.course(id: self.courseID, named: curso)?.subjects.map(\.label) ?? []
                if candidates.isEmpty { candidates = snap.preferences.asignaturasHabilitadas }
                candidates = candidates
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if let allPlans = try? await planificacionRepository.listarTodosPlanesCurso() {
                    candidates.append(contentsOf: allPlans.filter { $0.curso == curso }.map(\.asignatura))
                }
                candidates = uniqueSubjects(candidates)
                if candidates.isEmpty {
                    candidates = ["M\u{00FA}sica"]
                }
                subjectCandidates = candidates
                self.activeSubject = candidates.first ?? "M\u{00FA}sica"
            }
            self.subjectID = snap.course(id: self.courseID, named: curso)?.subjects.first { $0.label == self.activeSubject }?.id
            
            // 1. Load Pedagogical info
            var loadedVerUnidad: VerUnidadGuardada?
            for subject in subjectCandidates {
                if let saved = try await planificacionRepository.cargarVerUnidadConFallback(asignatura: subject, curso: curso, unidadId: unidadId) {
                    self.activeSubject = subject
                    loadedVerUnidad = saved
                    break
                }
            }

            if let saved = loadedVerUnidad {
                self.verUnidad = saved
                if !saved.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.unidadId = saved.unidadId
                }
            } else {
                // Initialize default unit
                self.verUnidad = await initDefaultUnit()
            }
            
            // 2. Load Cronograma (Class list and dates)
            let candidates = PlanificacionRepository.unidadIdCandidates(raw: self.unidadId)
            var loadedCronograma: CronogramaUnidadData?
            for subject in subjectCandidates where loadedCronograma == nil {
                if let savedCrono = try await planificacionRepository.cargarCronogramaUnidadConFallback(asignatura: subject, curso: curso, unidadIds: candidates) {
                    self.activeSubject = subject
                    loadedCronograma = savedCrono
                }
            }

            if let savedCrono = loadedCronograma {
                self.cronograma = savedCrono
                if (self.verUnidad?.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                   !savedCrono.unidadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.unidadId = savedCrono.unidadId
                }
            } else {
                // Initialize default 8-class cronograma
                let total = max(self.verUnidad?.clases ?? 8, 1)
                let defaultClases = (1...total).map { n in
                    ClaseCronograma(numero: n, fecha: "", oaIds: n == 1 ? ["OA1"] : n == 4 ? ["OA4"] : [])
                }
                self.cronograma = CronogramaUnidadData(asignatura: activeSubject, curso: curso, unidadId: self.unidadId, totalClases: total, clases: defaultClases)
            }

            self.verUnidad?.asignatura = self.activeSubject
            self.cronograma?.asignatura = self.activeSubject
            self.verUnidad?.unidadId = self.unidadId
            self.cronograma?.unidadId = self.unidadId
            
            // 3. Load all class detail plans
            await loadAllClasses()
            
        } catch {
            print("Error loading ver-unidad: \(error)")
            self.verUnidad = nil
            self.cronograma = nil
            self.clasesActividades.removeAll()
            self.activitySaveTokens.removeAll()
            self.persistedActivityClassNumbers.removeAll()
            self.pendingActivityClassNumbers.removeAll()
            self.activitySyncErrorClassNumbers.removeAll()
            self.activityLoadErrorClassNumbers.removeAll()
            self.loadErrorMessage = "No pudimos cargar la unidad y su cronograma. Reintenta antes de editar para proteger los datos existentes."
            self.saveStatus = "Error al cargar unidad"
        }
        self.isLoading = false
    }

    func retryLoad() async {
        guard !isLoading, !isSaving else { return }
        let curso = requestedCurso.isEmpty ? self.curso : requestedCurso
        let unidadId = requestedUnidadId.isEmpty ? self.unidadId : requestedUnidadId
        await load(curso: curso, unidadId: unidadId, asignatura: requestedAsignatura)
    }
    
    func loadAllClasses() async {
        guard let cronograma, !isReloadingActivities else { return }
        isReloadingActivities = true
        defer { isReloadingActivities = false }

        let total = max(cronograma.totalClases, cronograma.clases.map(\.numero).max() ?? 0)
        guard total > 0 else { return }
        clasesActividades.removeAll()
        activitySaveTokens.removeAll()
        persistedActivityClassNumbers.removeAll()
        pendingActivityClassNumbers.removeAll()
        activitySyncErrorClassNumbers.removeAll()
        activityLoadErrorClassNumbers.removeAll()
        
        for n in 1...total {
            var baseActivity = activityTemplate(for: n)
            var loadFailed = false

            do {
                if let activity = try await planificacionRepository.cargarActividadClaseConFallback(
                    curso: curso,
                    unidadId: unidadId,
                    numeroClase: n,
                    asignatura: activeSubject
                ) {
                    baseActivity = normalizedActivity(activity, classNum: n)
                    persistedActivityClassNumbers.insert(n)
                }
            } catch {
                loadFailed = true
                print("Error loading class \(n): \(error)")
            }

            if let pending = ActivityClassDraftStore.load(id: baseActivity.id) {
                persistedActivityClassNumbers.insert(n)
                pendingActivityClassNumbers.insert(n)
                let pendingOriginal = normalizedActivity(pending.original, classNum: n)
                let pendingUpdated = normalizedActivity(pending.updated, classNum: n)
                if loadFailed {
                    baseActivity = pendingOriginal
                }
                clasesActividades[n] = mergingPendingChanges(
                    original: pendingOriginal,
                    updated: pendingUpdated,
                    into: baseActivity
                )
                try? enqueueActivityPatch(
                    original: pendingOriginal,
                    updated: pendingUpdated,
                    classNumber: n,
                    includeMetadata: pending.includeMetadata
                )
            } else {
                if loadFailed {
                    activityLoadErrorClassNumbers.insert(n)
                }
                clasesActividades[n] = baseActivity
            }
        }

        refreshActivitySyncStatus()
    }

    func canEditActivity(_ classNumber: Int) -> Bool {
        loadErrorMessage == nil &&
        !isReloadingActivities &&
        !activityLoadErrorClassNumbers.contains(classNumber)
    }

    func retryActivityLoads() async {
        guard !isSaving, !isReloadingActivities else { return }
        if loadErrorMessage != nil {
            await retryLoad()
            return
        }
        activitySyncStatus = "Reintentando carga de clases..."
        await loadAllClasses()
    }

    func activityTemplate(for classNum: Int) -> ActividadClase {
        let actId = PlanificacionRepository.buildActividadClaseId(
            curso: curso,
            unidadId: unidadId,
            numeroClase: classNum,
            asignatura: activeSubject
        )
        let cronoClass = cronograma?.clases.first(where: { $0.numero == classNum })

        return ActividadClase(
            id: actId,
            asignatura: activeSubject,
            curso: curso,
            unidadId: unidadId,
            numeroClase: classNum,
            fecha: cronoClass?.fecha ?? "",
            oaIds: cronoClass?.oaIds ?? [],
            objetivo: "",
            inicio: "",
            desarrollo: "",
            cierre: "",
            adecuacion: "",
            habilidades: [],
            actitudes: [],
            materiales: [],
            tics: [],
            estado: "no_planificada",
            sincronizada: false
        )
    }

    func ensureActivity(for classNum: Int) {
        if let existing = clasesActividades[classNum] {
            clasesActividades[classNum] = normalizedActivity(existing, classNum: classNum)
        } else {
            clasesActividades[classNum] = activityTemplate(for: classNum)
        }
    }

    private func normalizedActivity(_ activity: ActividadClase, classNum: Int) -> ActividadClase {
        var result = activity
        let cronoClass = cronograma?.clases.first(where: { $0.numero == classNum })
        result.id = PlanificacionRepository.buildActividadClaseId(
            curso: curso,
            unidadId: unidadId,
            numeroClase: classNum,
            asignatura: activeSubject
        )
        result.asignatura = activeSubject
        result.curso = curso
        result.unidadId = unidadId
        result.numeroClase = classNum
        result.fecha = cronoClass?.fecha ?? result.fecha
        result.oaIds = cronoClass?.oaIds ?? result.oaIds
        if result.estado.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.estado = "no_planificada"
        }
        return result
    }

    private func mergingPendingChanges(
        original: ActividadClase,
        updated: ActividadClase,
        into remote: ActividadClase
    ) -> ActividadClase {
        var merged = remote
        if original.objetivo != updated.objetivo { merged.objetivo = updated.objetivo }
        if original.inicio != updated.inicio { merged.inicio = updated.inicio }
        if original.desarrollo != updated.desarrollo { merged.desarrollo = updated.desarrollo }
        if original.cierre != updated.cierre { merged.cierre = updated.cierre }
        if original.adecuacion != updated.adecuacion { merged.adecuacion = updated.adecuacion }
        if original.habilidades != updated.habilidades { merged.habilidades = updated.habilidades }
        if original.actitudes != updated.actitudes { merged.actitudes = updated.actitudes }
        if original.materiales != updated.materiales { merged.materiales = updated.materiales }
        if original.tics != updated.tics { merged.tics = updated.tics }
        if original.estado != updated.estado { merged.estado = updated.estado }
        if original.sincronizada != updated.sincronizada { merged.sincronizada = updated.sincronizada }
        if original.contextoProfesor != updated.contextoProfesor {
            merged.contextoProfesor = updated.contextoProfesor
        }
        if original.indicadoresPorOa != updated.indicadoresPorOa {
            merged.indicadoresPorOa = updated.indicadoresPorOa
        }
        return merged
    }
    
    // Save unit, cronograma and class routing metadata. Class content uses its dedicated editor.
    func saveAll() async {
        guard loadErrorMessage == nil,
              let verUnidad,
              let cronograma,
              !isSaving,
              !isReloadingActivities else { return }
        isSaving = true
        saveStatus = "Guardando localmente..."
        defer { isSaving = false }

        let operationToken = UUID()
        saveAllOperationToken = operationToken
        saveAllHadError = false

        let activities = persistedActivityClassNumbers.sorted().compactMap { classNumber -> ActividadClase? in
            guard let activity = clasesActividades[classNumber] else { return nil }
            let updated = normalizedActivity(activity, classNum: classNumber)
            clasesActividades[classNumber] = updated
            return updated
        }
        saveAllPendingAcknowledgements = 2 + activities.count

        do {
            saveStatus = "Unidad guardada localmente"

            try planificacionRepository.encolarVerUnidad(
                asignatura: activeSubject,
                curso: curso,
                unidadId: unidadId,
                data: verUnidad
            ) { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleSaveAllAcknowledgement(token: operationToken, error: error)
                }
            }

            try planificacionRepository.encolarCronogramaUnidad(
                asignatura: activeSubject,
                curso: curso,
                unidadId: unidadId,
                totalClases: cronograma.totalClases,
                clases: cronograma.clases
            ) { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleSaveAllAcknowledgement(token: operationToken, error: error)
                }
            }

            for activity in activities {
                try planificacionRepository.encolarMetadatosActividadClase(activity) { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleSaveAllAcknowledgement(token: operationToken, error: error)
                    }
                }
            }
        } catch {
            saveAllOperationToken = nil
            saveAllPendingAcknowledgements = 0
            saveAllHadError = true
            print("Error saving: \(error)")
            saveStatus = "Error al guardar unidad"
        }
    }

    private func handleSaveAllAcknowledgement(token: UUID, error: Error?) {
        guard saveAllOperationToken == token else { return }

        if error != nil {
            saveAllHadError = true
            saveStatus = "Error al sincronizar unidad"
        }
        saveAllPendingAcknowledgements = max(saveAllPendingAcknowledgements - 1, 0)
        guard saveAllPendingAcknowledgements == 0 else { return }

        saveAllOperationToken = nil
        guard !saveAllHadError else { return }

        let syncedStatus = "Unidad sincronizada"
        saveStatus = syncedStatus
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, self?.saveStatus == syncedStatus else { return }
            self?.saveStatus = ""
        }
    }

    func saveActivity(original: ActividadClase, updated: ActividadClase) throws {
        guard !isReloadingActivities else {
            throw VerUnidadViewModelError.activityLoadInProgress
        }
        guard canEditActivity(updated.numeroClase) else {
            throw VerUnidadViewModelError.activityLoadUnavailable
        }
        guard !isSaving else { throw VerUnidadViewModelError.saveInProgress }
        isSaving = true
        activitySyncStatus = "Guardando clase \(updated.numeroClase)..."
        defer { isSaving = false }

        do {
            let classNumber = updated.numeroClase
            let normalizedOriginal = normalizedActivity(original, classNum: classNumber)
            let normalizedUpdated = normalizedActivity(updated, classNum: classNumber)
            let existingDraft = ActivityClassDraftStore.load(id: normalizedUpdated.id)
            let patchOriginal = existingDraft
                .map { normalizedActivity($0.original, classNum: classNumber) } ?? normalizedOriginal
            let includeMetadata = existingDraft?.includeMetadata
                ?? !persistedActivityClassNumbers.contains(classNumber)

            try ActivityClassDraftStore.save(
                original: patchOriginal,
                updated: normalizedUpdated,
                includeMetadata: includeMetadata
            )
            try enqueueActivityPatch(
                original: patchOriginal,
                updated: normalizedUpdated,
                classNumber: classNumber,
                includeMetadata: includeMetadata
            )
            persistedActivityClassNumbers.insert(classNumber)
            clasesActividades[classNumber] = normalizedUpdated
            refreshActivitySyncStatus()
        } catch {
            activitySaveTokens[updated.numeroClase] = nil
            activitySyncStatus = "Error al guardar clase"
            throw error
        }
    }

    private func enqueueActivityPatch(
        original: ActividadClase,
        updated: ActividadClase,
        classNumber: Int,
        includeMetadata: Bool
    ) throws {
        let operationToken = UUID()
        let pendingDraftID = updated.id
        activitySaveTokens[classNumber] = operationToken
        pendingActivityClassNumbers.insert(classNumber)
        activitySyncErrorClassNumbers.remove(classNumber)

        do {
            try planificacionRepository.encolarCambiosActividadClase(
                original: original,
                updated: updated,
                includeMetadata: includeMetadata
            ) { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.activitySaveTokens[classNumber] == operationToken else { return }
                    self.activitySaveTokens[classNumber] = nil

                    if error != nil {
                        self.activitySyncErrorClassNumbers.insert(classNumber)
                        self.refreshActivitySyncStatus()
                    } else {
                        ActivityClassDraftStore.remove(id: pendingDraftID)
                        self.pendingActivityClassNumbers.remove(classNumber)
                        self.activitySyncErrorClassNumbers.remove(classNumber)
                        self.refreshActivitySyncStatus(lastSyncedClass: classNumber)
                    }
                }
            }
        } catch {
            activitySaveTokens[classNumber] = nil
            activitySyncErrorClassNumbers.insert(classNumber)
            refreshActivitySyncStatus()
            throw error
        }
    }

    private func refreshActivitySyncStatus(lastSyncedClass: Int? = nil) {
        if !activityLoadErrorClassNumbers.isEmpty {
            let count = activityLoadErrorClassNumbers.count
            activitySyncStatus = count == 1
                ? "Error al cargar la planificación de 1 clase"
                : "Error al cargar la planificación de \(count) clases"
            return
        }

        if !activitySyncErrorClassNumbers.isEmpty {
            let count = activitySyncErrorClassNumbers.count
            activitySyncStatus = count == 1
                ? "Error de sincronización · 1 clase pendiente"
                : "Error de sincronización · \(count) clases pendientes"
            return
        }

        if !pendingActivityClassNumbers.isEmpty {
            let count = pendingActivityClassNumbers.count
            activitySyncStatus = count == 1
                ? "1 clase guardada localmente"
                : "\(count) clases guardadas localmente"
            return
        }

        guard let lastSyncedClass else {
            activitySyncStatus = ""
            return
        }

        let syncedStatus = "Clase \(lastSyncedClass) sincronizada"
        activitySyncStatus = syncedStatus
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, self?.activitySyncStatus == syncedStatus else { return }
            self?.activitySyncStatus = ""
        }
    }

    // Auto-calculate dates based on schedule blocks
    func calculateDatesFromSchedule() async {
        guard var cronograma else { return }
        
        // Find weekday matches from schedule
        do {
            let snap = try await dashboardRepository.fetchDashboard()
            let academicClasses = snap.horario.filter(\.isAcademic)
            let weekdays = Array(Set(academicClasses.map(\.dia)))
            
            if weekdays.isEmpty {
                return
            }
            
            // Generate sequence of next weekdays starting from today
            let calendar = Calendar.current
            var matchingDates: [String] = []
            var checkDate = Date()
            
            let weekdayMap = [
                "domingo": 1,
                "lunes": 2,
                "martes": 3,
                "miercoles": 4,
                "jueves": 5,
                "viernes": 6,
                "sabado": 7
            ]
            
            let targetWeekdayInts = weekdays.compactMap { day in
                weekdayMap[day.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL")).lowercased()]
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            
            while matchingDates.count < cronograma.totalClases {
                let wk = calendar.component(.weekday, from: checkDate)
                if targetWeekdayInts.contains(wk) {
                    matchingDates.append(formatter.string(from: checkDate))
                }
                checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate) ?? checkDate
            }
            
            // Update cronograma classes dates
            for i in 0..<cronograma.clases.count {
                if i < matchingDates.count {
                    cronograma.clases[i].fecha = matchingDates[i]
                }
            }
            
            self.cronograma = cronograma
            await saveAll()
            
        } catch {
            print("Error calculating dates: \(error)")
        }
    }

    private func cargarOAsCurriculares() async -> [OAEditado]? {
        guard let nivel = CurriculoNivel.resolver(curso: curso, mapping: snapshot?.nivelMapping ?? [:]) else {
            return nil
        }

        for candidato in PlanificacionRepository.unidadIdCandidates(raw: unidadId) {
            if let unidad = try? await curriculoRepository.getUnidadCompleta(
                asignatura: activeSubject,
                nivel: nivel,
                unidadId: candidato
            ) {
                return CurriculoOA.initOAs(unidad: unidad, asignatura: activeSubject)
            }
        }

        return nil
    }

    // Curricular Fallback setup for local premium preview
    private func initDefaultUnit() async -> VerUnidadGuardada {
        if let oasCurriculares = await cargarOAsCurriculares() {
            return VerUnidadGuardada(
                asignatura: activeSubject,
                curso: curso,
                unidadId: unidadId,
                descripcion: "<p>Explorar las cualidades del sonido en el entorno y crear paisajes sonoros y patrones rítmicos.</p>",
                contextoDocente: "<p>Se requiere enfoque activo con dinámicas corporales y material lúdico.</p>",
                objetivoDocente: "<p>Lograr que los estudiantes identifiquen y combinen al menos 3 fuentes sonoras.</p>",
                horas: 16,
                clases: 8,
                oas: oasCurriculares,
                habilidades: [],
                conocimientos: [],
                actitudes: [],
                recursosMaterialesUnidad: [],
                estrategiasEvaluacion: []
            )
        }

        let defaultOAs: [OAEditado] = []

        let defaultHabilidades = [
            ElementoCurricular(id: "hab_1", texto: "Escuchar de forma atenta y reflexiva.", seleccionado: true),
            ElementoCurricular(id: "hab_2", texto: "Crear patrones e improvisaciones rítmicas.", seleccionado: true),
            ElementoCurricular(id: "hab_3", texto: "Expresar ideas y emociones por medio del sonido.", seleccionado: true)
        ]

        let defaultConocimientos = [
            ElementoCurricular(id: "con_1", texto: "Cualidades del sonido (timbre, altura, intensidad, duración).", seleccionado: true),
            ElementoCurricular(id: "con_2", texto: "Paisaje sonoro y fuentes sonoras.", seleccionado: true),
            ElementoCurricular(id: "con_3", texto: "Ritmo, pulso, acento y figuras rítmicas básicas.", seleccionado: true)
        ]

        let defaultActitudes = [
            ElementoCurricular(id: "act_1", texto: "Demostrar disposición a comunicar sus ideas.", seleccionado: true),
            ElementoCurricular(id: "act_2", texto: "Valorar el trabajo en equipo y el respeto mutuo.", seleccionado: true)
        ]

        return VerUnidadGuardada(
            asignatura: activeSubject,
            curso: curso,
            unidadId: unidadId,
            descripcion: "<p>Explorar las cualidades del sonido en el entorno y crear paisajes sonoros y patrones rítmicos.</p>",
            contextoDocente: "<p>Se requiere enfoque activo con dinámicas corporales y material lúdico.</p>",
            objetivoDocente: "<p>Lograr que los estudiantes identifiquen y combinen al menos 3 fuentes sonoras.</p>",
            horas: 16,
            clases: 8,
            oas: defaultOAs,
            habilidades: defaultHabilidades,
            conocimientos: defaultConocimientos,
            actitudes: defaultActitudes,
            conocimientosPrevios: "<p>Sonidos del entorno familiar, figuras musicales simples.</p>",
            recursosMaterialesUnidad: ["Celular para grabar", "Instrumentos de percusión", "Tarjetas visuales"],
            estrategiasEvaluacion: [
                EstrategiaEvaluacionUnidad(id: "eval_1", nombre: "Entrega de boceto sonoro", instrumento: "Rúbrica", ponderacion: 40.0),
                EstrategiaEvaluacionUnidad(id: "eval_2", nombre: "Participación en coro rítmico", instrumento: "Lista de cotejo", ponderacion: 60.0)
            ]
        )
    }

    private func uniqueSubjects(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let key = clean.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL")).lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(clean)
        }
        return result
    }
}

private enum VerUnidadViewModelError: LocalizedError {
    case saveInProgress
    case activityLoadInProgress
    case activityLoadUnavailable

    var errorDescription: String? {
        switch self {
        case .saveInProgress:
            return "Ya hay un guardado en curso. Espera un momento e intenta nuevamente."
        case .activityLoadInProgress:
            return "Las clases se están cargando. Espera un momento antes de guardar."
        case .activityLoadUnavailable:
            return "No pudimos cargar esta clase. Reintenta antes de editar para proteger los datos que ya existen."
        }
    }
}

private enum ActivityClassDraftStore {
    private static let keyPrefix = "cl.edupanel.pending-activity"

    static func save(
        original: ActividadClase,
        updated: ActividadClase,
        includeMetadata: Bool
    ) throws {
        guard let key = storageKey(id: updated.id) else {
            throw DashboardRepositoryError.missingUser
        }
        let draft = PendingActivityClassDraft(
            original: original,
            updated: updated,
            includeMetadata: includeMetadata
        )
        UserDefaults.standard.set(try JSONEncoder().encode(draft), forKey: key)
    }

    static func load(id: String) -> PendingActivityClassDraft? {
        guard let key = storageKey(id: id),
              let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let draft = try? JSONDecoder().decode(PendingActivityClassDraft.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return draft
    }

    static func remove(id: String) {
        guard let key = storageKey(id: id) else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func storageKey(id: String) -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return "\(keyPrefix).\(uid).\(id)"
    }
}

private struct PendingActivityClassDraft: Codable {
    let original: ActividadClase
    let updated: ActividadClase
    let includeMetadata: Bool

    private enum CodingKeys: String, CodingKey {
        case original, updated, includeMetadata
    }

    init(original: ActividadClase, updated: ActividadClase, includeMetadata: Bool) {
        self.original = original
        self.updated = updated
        self.includeMetadata = includeMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        original = try container.decode(ActividadClase.self, forKey: .original)
        updated = try container.decode(ActividadClase.self, forKey: .updated)
        includeMetadata = try container.decodeIfPresent(Bool.self, forKey: .includeMetadata) ?? true
    }
}
