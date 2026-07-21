import Foundation
import Observation

@MainActor
@Observable
final class EvaluacionesViewModel {
    var snapshot: DashboardSnapshot?
    var listas: [ListaCotejoTemplate] = []
    var rubricas: [RubricaTemplate] = []
    var pruebas: [PruebaTemplate] = []
    var guias: [GuiaTemplate] = []
    var isLoading = false
    var isLoadingContenido = false
    var errorMessage: String?
    var listasErrorMessage: String?
    var rubricasErrorMessage: String?
    var pruebasErrorMessage: String?
    var guiasErrorMessage: String?
    var pruebasConAdvertencias = 0
    var pruebasDesdeCache = false
    var guiasConAdvertencias = 0
    var guiasDesdeCache = false
    var selectedCurso: String = ""
    var selectedSubject: String?
    var selectedCourseID: String?
    var selectedSubjectID: String?

    private let dashboardRepository: DashboardRepository
    private let evaluacionesRepository: EvaluacionesRepository
    private static let defaultSubject = "M\u{00FA}sica"
    @ObservationIgnored private var contentLoadGeneration = 0

    init(dashboardRepository: DashboardRepository, evaluacionesRepository: EvaluacionesRepository = EvaluacionesRepository()) {
        self.dashboardRepository = dashboardRepository
        self.evaluacionesRepository = evaluacionesRepository
    }

    var activeSubject: String {
        if let selectedSubject, !selectedSubject.isEmpty { return selectedSubject }
        if let delCurso = asignaturasDelCurso(selectedCurso).first { return delCurso }
        if let habilitada = asignaturasHabilitadas.first { return habilitada }
        let especialidad = snapshot?.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return especialidad.isEmpty ? Self.defaultSubject : especialidad
    }

    /// Asignaturas para el selector: las del curso elegido, las habilitadas en perfil y la especialidad.
    /// Esto da una escotilla de escape: aunque la asignatura guardada no coincida con la derivada,
    /// el docente puede cambiarla a mano y recuperar sus evaluaciones.
    var availableSubjects: [String] {
        var resultado: [String] = []
        var vistos = Set<String>()
        func agregar(_ valor: String) {
            let limpio = valor.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty, !vistos.contains(limpio) else { return }
            vistos.insert(limpio)
            resultado.append(limpio)
        }
        asignaturasDelCurso(selectedCurso).forEach(agregar)
        asignaturasHabilitadas.forEach(agregar)
        agregar(snapshot?.profile.especialidad ?? "")
        if resultado.isEmpty { agregar(Self.defaultSubject) }
        return resultado
    }

    private var asignaturasHabilitadas: [String] {
        let catalog = snapshot?.activeCourses.flatMap(\.subjects).map(\.label) ?? []
        if !catalog.isEmpty { return Array(Set(catalog)).sorted() }
        return (snapshot?.preferences.asignaturasHabilitadas ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Asignaturas que el docente enseña en un curso, leídas de los bloques del horario.
    func asignaturasDelCurso(_ curso: String) -> [String] {
        if let configured = snapshot?.course(id: nil, named: curso)?.subjects.map(\.label), !configured.isEmpty {
            return configured
        }
        guard !curso.isEmpty, let horario = snapshot?.horario else { return [] }
        var resultado: [String] = []
        var vistos = Set<String>()
        for clase in horario where clase.resumen == curso {
            guard let asignatura = clase.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !asignatura.isEmpty, !vistos.contains(asignatura) else { continue }
            vistos.insert(asignatura)
            resultado.append(asignatura)
        }
        return resultado
    }

    var cursos: [String] {
        snapshot?.courses ?? []
    }

    var evaluacionScope: EvaluacionScope {
        EvaluacionScope.resolve(snapshot?.preferences.colegioActivoId)
    }

    /// Cambia de curso reseteando la asignatura elegida para que se re-derive del nuevo curso.
    func seleccionarCurso(_ curso: String) async {
        selectedCurso = curso
        selectedCourseID = snapshot?.course(id: nil, named: curso)?.courseID
        selectedSubject = nil
        await loadContenido()
    }

    func seleccionarAsignatura(_ asignatura: String) async {
        selectedSubject = asignatura
        selectedSubjectID = snapshot?.course(id: selectedCourseID, named: selectedCurso)?.subjects.first { $0.label == asignatura }?.id
        await loadContenido()
    }

    func estudiantes(curso: String) -> [EstudiantePerfil] {
        guard let snapshot else { return [] }
        return snapshot.students(forCourseID: snapshot.course(id: nil, named: curso)?.courseID, name: curso).sorted { $0.orden < $1.orden }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snap = try await dashboardRepository.fetchDashboard()
            snapshot = snap
            if selectedCurso.isEmpty || !snap.courses.contains(selectedCurso) {
                selectedCurso = snap.courses.first ?? ""
            }
            selectedCourseID = snap.course(id: nil, named: selectedCurso)?.courseID
            await loadContenido()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadContenido() async {
        contentLoadGeneration += 1
        let generation = contentLoadGeneration

        guard !selectedCurso.isEmpty else {
            isLoadingContenido = false
            listas = []
            rubricas = []
            pruebas = []
            guias = []
            listasErrorMessage = nil
            rubricasErrorMessage = nil
            pruebasErrorMessage = nil
            guiasErrorMessage = nil
            return
        }

        errorMessage = nil
        isLoadingContenido = true
        defer {
            if generation == contentLoadGeneration {
                isLoadingContenido = false
            }
        }

        let course = selectedCurso
        let scope = evaluacionScope

        async let listasTask = evaluacionesRepository.cargarListasCotejo(asignatura: nil, curso: course)
        async let rubricasTask = evaluacionesRepository.cargarRubricas(asignatura: nil, curso: course)
        async let pruebasTask = evaluacionesRepository.cargarPruebas(curso: course, scope: scope)
        async let guiasTask = evaluacionesRepository.cargarGuias(curso: course, scope: scope)

        let loadedListas: [ListaCotejoTemplate]?
        let listasError: String?
        do {
            loadedListas = try await listasTask
            listasError = nil
        } catch {
            loadedListas = nil
            listasError = "No se pudieron cargar las listas de cotejo."
        }

        let loadedRubricas: [RubricaTemplate]?
        let rubricasError: String?
        do {
            loadedRubricas = try await rubricasTask
            rubricasError = nil
        } catch {
            loadedRubricas = nil
            rubricasError = "No se pudieron cargar las rúbricas."
        }

        let loadedPruebas: PruebasCargaResultado?
        let pruebasError: String?
        do {
            loadedPruebas = try await pruebasTask
            pruebasError = nil
        } catch {
            loadedPruebas = nil
            pruebasError = "No se pudieron cargar las pruebas de este curso."
        }

        let loadedGuias: GuiasCargaResultado?
        let guiasError: String?
        do {
            loadedGuias = try await guiasTask
            guiasError = nil
        } catch {
            loadedGuias = nil
            guiasError = "No se pudieron cargar las guías de este curso."
        }

        guard generation == contentLoadGeneration, course == selectedCurso else { return }
        if let loadedListas { listas = loadedListas }
        if let loadedRubricas { rubricas = loadedRubricas }
        if let loadedPruebas {
            pruebas = loadedPruebas.pruebas
            pruebasConAdvertencias = loadedPruebas.documentosConAdvertencias
            pruebasDesdeCache = loadedPruebas.isFromCache
        }
        if let loadedGuias {
            guias = loadedGuias.guias
            guiasConAdvertencias = loadedGuias.warningCount
            guiasDesdeCache = loadedGuias.isFromCache
        }
        listasErrorMessage = listasError
        rubricasErrorMessage = rubricasError
        pruebasErrorMessage = pruebasError
        guiasErrorMessage = guiasError
    }

    func eliminarLista(_ lista: ListaCotejoTemplate) async {
        do {
            try await evaluacionesRepository.eliminarListaCotejo(id: lista.id)
            listas.removeAll { $0.id == lista.id }
        } catch {
            errorMessage = "No se pudo eliminar la lista."
        }
    }

    func eliminarRubrica(_ rubrica: RubricaTemplate) async {
        do {
            try await evaluacionesRepository.eliminarRubrica(id: rubrica.id)
            rubricas.removeAll { $0.id == rubrica.id }
        } catch {
            errorMessage = "No se pudo eliminar la r\u{00FA}brica."
        }
    }

    func duplicarLista(_ lista: ListaCotejoTemplate, cursoDestino: String) async {
        var copia = lista
        copia.id = EvaluacionesIDs.buildListaCotejoId(asignatura: lista.asignatura, curso: cursoDestino)
        copia.curso = cursoDestino
        copia.fechaActualizacion = nil
        if !copia.nombre.hasSuffix("(copia)") {
            copia.nombre = "\(copia.nombre.isEmpty ? "Lista de cotejo" : copia.nombre) (copia)"
        }
        do {
            try await evaluacionesRepository.guardarListaCotejo(copia)
            if cursoDestino == selectedCurso {
                await loadContenido()
            }
        } catch {
            errorMessage = "No se pudo duplicar la lista."
        }
    }

    func duplicarRubrica(_ rubrica: RubricaTemplate, cursoDestino: String) async {
        var copia = rubrica
        copia.id = EvaluacionesIDs.buildRubricaId(asignatura: rubrica.asignatura, curso: cursoDestino)
        copia.curso = cursoDestino
        copia.fechaActualizacion = nil
        if !copia.nombre.hasSuffix("(copia)") {
            copia.nombre = "\(copia.nombre.isEmpty ? "R\u{00FA}brica" : copia.nombre) (copia)"
        }
        do {
            try await evaluacionesRepository.guardarRubrica(copia)
            if cursoDestino == selectedCurso {
                await loadContenido()
            }
        } catch {
            errorMessage = "No se pudo duplicar la r\u{00FA}brica."
        }
    }

    func eliminarPrueba(_ test: PruebaTemplate) async {
        do {
            try await evaluacionesRepository.eliminarPrueba(id: test.id, scope: test.scope)
            pruebas.removeAll { $0.id == test.id }
        } catch {
            pruebasErrorMessage = "No se pudo eliminar la prueba."
        }
    }

    func duplicarPrueba(_ test: PruebaTemplate, cursoDestino: String) async {
        do {
            _ = try await evaluacionesRepository.duplicarPrueba(test, cursoDestino: cursoDestino, scope: test.scope)
            if cursoDestino == selectedCurso { await loadContenido() }
        } catch {
            pruebasErrorMessage = "No se pudo duplicar la prueba."
        }
    }

    func eliminarGuia(_ guide: GuiaTemplate) async {
        do {
            try await evaluacionesRepository.eliminarGuia(id: guide.id, scope: guide.scope)
            guias.removeAll { $0.id == guide.id }
        } catch {
            guiasErrorMessage = "No se pudo eliminar la guía."
        }
    }

    func duplicarGuia(_ guide: GuiaTemplate, cursoDestino: String) async {
        do {
            _ = try await evaluacionesRepository.duplicarGuia(guide, cursoDestino: cursoDestino, scope: guide.scope)
            if cursoDestino == selectedCurso { await loadContenido() }
        } catch {
            guiasErrorMessage = "No se pudo duplicar la guía."
        }
    }
}
