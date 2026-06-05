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
    
    var activeSubject = "Música"
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
    
    func load(curso: String, unidadId: String) async {
        self.curso = curso
        self.unidadId = unidadId
        self.isLoading = true
        self.saveStatus = ""
        
        do {
            let snap = try await dashboardRepository.fetchDashboard()
            self.snapshot = snap
            self.activeSubject = snap.preferences.asignaturasHabilitadas.first ?? "Música"
            
            // 1. Load Pedagogical info
            if let saved = try await planificacionRepository.cargarVerUnidad(asignatura: activeSubject, curso: curso, unidadId: unidadId) {
                self.verUnidad = saved
            } else {
                // Initialize default unit
                self.verUnidad = await initDefaultUnit()
            }
            
            // 2. Load Cronograma (Class list and dates)
            if let savedCrono = try await planificacionRepository.cargarCronogramaUnidad(asignatura: activeSubject, curso: curso, unidadId: unidadId) {
                self.cronograma = savedCrono
            } else {
                // Initialize default 8-class cronograma
                let defaultClases = (1...8).map { n in
                    ClaseCronograma(numero: n, fecha: "", oaIds: n == 1 ? ["OA1"] : n == 4 ? ["OA4"] : [])
                }
                self.cronograma = CronogramaUnidadData(asignatura: activeSubject, curso: curso, unidadId: unidadId, totalClases: 8, clases: defaultClases)
            }
            
            // 3. Load all class detail plans
            await loadAllClasses()
            
        } catch {
            print("Error loading ver-unidad: \(error)")
            self.saveStatus = "Error al cargar"
        }
        self.isLoading = false
    }
    
    func loadAllClasses() async {
        guard let total = cronograma?.totalClases else { return }
        clasesActividades.removeAll()
        
        for n in 1...total {
            if let act = try? await planificacionRepository.cargarActividadClase(curso: curso, unidadId: unidadId, numeroClase: n, asignatura: activeSubject) {
                clasesActividades[n] = act
            } else {
                // Initialize default empty activity
                let actId = PlanificacionRepository.buildActividadClaseId(curso: curso, unidadId: unidadId, numeroClase: n, asignatura: activeSubject)
                let dateStr = cronograma?.clases.first(where: { $0.numero == n })?.fecha ?? ""
                let oas = cronograma?.clases.first(where: { $0.numero == n })?.oaIds ?? []
                
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
            let weekdays = Array(Set(academicClasses.map(\.dia))) // e.g. ["Lunes", "Miércoles"]
            
            if weekdays.isEmpty {
                return
            }
            
            // Generate sequence of next weekdays starting from today
            let calendar = Calendar.current
            var matchingDates: [String] = []
            var checkDate = Date()
            
            let weekdayMap = [
                "Domingo": 1, "Lunes": 2, "Martes": 3, "Miércoles": 4, "Jueves": 5, "Viernes": 6, "Sábado": 7
            ]
            
            let targetWeekdayInts = weekdays.compactMap { weekdayMap[$0] }
            
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
            descripcion: "Explorar las cualidades del sonido en el entorno y crear paisajes sonoros y patrones rítmicos...",
            contextoDocente: "Se requiere enfoque activo con dinámicas corporales y material lúdico.",
            objetivoDocente: "Lograr que los estudiantes identifiquen y combinen al menos 3 fuentes sonoras.",
            horas: 16,
            clases: 8,
            oas: defaultOAs,
            habilidades: defaultHabilidades,
            conocimientos: defaultConocimientos,
            actitudes: defaultActitudes,
            conocimientosPrevios: "Sonidos del entorno familiar, figuras musicales simples.",
            recursosMaterialesUnidad: ["Celular para grabar", "Instrumentos de percusión", "Tarjetas visuales"],
            estrategiasEvaluacion: [
                EstrategiaEvaluacionUnidad(id: "eval_1", nombre: "Entrega de boceto sonoro", instrumento: "Rúbrica", ponderacion: 40.0),
                EstrategiaEvaluacionUnidad(id: "eval_2", nombre: "Participación en coro rítmico", instrumento: "Lista de cotejo", ponderacion: 60.0)
            ]
        )
    }
}
