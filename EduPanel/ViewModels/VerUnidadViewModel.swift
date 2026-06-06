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
    
    var isLoading = false
    var isSaving = false
    var saveStatus = ""
    
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
    }
    
    func load(curso: String, unidadId: String, asignatura: String? = nil) async {
        self.curso = curso
        self.unidadId = unidadId
        self.isLoading = true
        self.saveStatus = ""
        
        do {
            let snap = try await dashboardRepository.fetchDashboard()
            self.snapshot = snap
            let providedSubject = asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var subjectCandidates = snap.preferences.asignaturasHabilitadas
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let allPlans = try? await planificacionRepository.listarTodosPlanesCurso() {
                subjectCandidates.append(contentsOf: allPlans.filter { $0.curso == curso }.map(\.asignatura))
            }
            if !providedSubject.isEmpty {
                subjectCandidates.insert(providedSubject, at: 0)
            }
            subjectCandidates = uniqueSubjects(subjectCandidates)
            if subjectCandidates.isEmpty {
                subjectCandidates = ["M\u{00FA}sica"]
            }
            self.activeSubject = subjectCandidates.first ?? "M\u{00FA}sica"
            
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
            self.saveStatus = "Error al cargar"
        }
        self.isLoading = false
    }
    
    func loadAllClasses() async {
        guard let cronograma else { return }
        let total = max(cronograma.totalClases, cronograma.clases.map(\.numero).max() ?? 0)
        guard total > 0 else { return }
        clasesActividades.removeAll()
        
        for n in 1...total {
            if let act = try? await planificacionRepository.cargarActividadClaseConFallback(curso: curso, unidadId: unidadId, numeroClase: n, asignatura: activeSubject) {
                clasesActividades[n] = act
            } else {
                // Initialize default empty activity
                let actId = PlanificacionRepository.buildActividadClaseId(curso: curso, unidadId: unidadId, numeroClase: n, asignatura: activeSubject)
                let dateStr = cronograma.clases.first(where: { $0.numero == n })?.fecha ?? ""
                let oas = cronograma.clases.first(where: { $0.numero == n })?.oaIds ?? []
                
                clasesActividades[n] = ActividadClase(
                    id: actId,
                    asignatura: activeSubject,
                    curso: curso,
                    unidadId: unidadId,
                    numeroClase: n,
                    fecha: dateStr,
                    oaIds: oas,
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
        }
    }
    
    // Save everything (Unidad details + Cronograma + Classes)
    func saveAll() async {
        guard let verUnidad, let cronograma else { return }
        isSaving = true
        saveStatus = "Guardando..."
        
        do {
            // 1. Save ver unidad
            try await planificacionRepository.guardarVerUnidad(asignatura: activeSubject, curso: curso, unidadId: unidadId, data: verUnidad)
            
            // 2. Save cronograma
            try await planificacionRepository.guardarCronogramaUnidad(
                asignatura: activeSubject,
                curso: curso,
                unidadId: unidadId,
                totalClases: cronograma.totalClases,
                clases: cronograma.clases
            )
            
            // 3. Save modified classes
            for (_, act) in clasesActividades {
                // Update dates / OAs to match cronograma if changed
                var cleanAct = act
                cleanAct.unidadId = unidadId
                cleanAct.curso = curso
                cleanAct.asignatura = activeSubject
                if let cronoClase = cronograma.clases.first(where: { $0.numero == act.numeroClase }) {
                    cleanAct.fecha = cronoClase.fecha
                    cleanAct.oaIds = cronoClase.oaIds
                }
                try await planificacionRepository.guardarActividadClase(data: cleanAct)
            }
            
            saveStatus = "Guardado"
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if saveStatus == "Guardado" {
                saveStatus = ""
            }
        } catch {
            print("Error saving: \(error)")
            saveStatus = "Error al guardar"
        }
        isSaving = false
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

    // Curricular Fallback setup for local premium preview
    private func initDefaultUnit() async -> VerUnidadGuardada {
        let defaultOAs = [
            OAEditado(
                id: "OA1",
                numero: 1,
                tipo: "oa",
                descripcion: "Escuchar cualidades del sonido y describirlas usando vocabulario musical.",
                seleccionado: true,
                indicadores: [
                    IndicadorEditado(id: "OA1_IND1", texto: "Describen cualidades del sonido en el entorno.", seleccionado: true),
                    IndicadorEditado(id: "OA1_IND2", texto: "Identifican fuentes sonoras directas.", seleccionado: true)
                ]
            ),
            OAEditado(
                id: "OA2",
                numero: 2,
                tipo: "oa",
                descripcion: "Interpretar y crear patrones rítmicos con voz, cuerpo e instrumentos.",
                seleccionado: true,
                indicadores: [
                    IndicadorEditado(id: "OA2_IND1", texto: "Ejecutan ritmos corporales de forma grupal.", seleccionado: true),
                    IndicadorEditado(id: "OA2_IND2", texto: "Crean secuencias rítmicas de 4 pulsos.", seleccionado: true)
                ]
            ),
            OAEditado(
                id: "OA4",
                numero: 4,
                tipo: "oa",
                descripcion: "Expresar ideas musicales mediante recursos sonoros diversos.",
                seleccionado: true,
                indicadores: [
                    IndicadorEditado(id: "OA4_IND1", texto: "Diseñan bocetos de paisajes sonoros.", seleccionado: true),
                    IndicadorEditado(id: "OA4_IND2", texto: "Graban y reproducen creaciones sonoras.", seleccionado: true)
                ]
            )
        ]

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
