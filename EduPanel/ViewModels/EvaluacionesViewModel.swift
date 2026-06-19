import Foundation
import Observation

@MainActor
@Observable
final class EvaluacionesViewModel {
    var snapshot: DashboardSnapshot?
    var listas: [ListaCotejoTemplate] = []
    var rubricas: [RubricaTemplate] = []
    var isLoading = false
    var isLoadingContenido = false
    var errorMessage: String?
    var selectedCurso: String = ""
    var selectedSubject: String?

    private let dashboardRepository: DashboardRepository
    private let evaluacionesRepository: EvaluacionesRepository
    private static let defaultSubject = "M\u{00FA}sica"

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
        (snapshot?.preferences.asignaturasHabilitadas ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Asignaturas que el docente enseña en un curso, leídas de los bloques del horario.
    func asignaturasDelCurso(_ curso: String) -> [String] {
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

    /// Cambia de curso reseteando la asignatura elegida para que se re-derive del nuevo curso.
    func seleccionarCurso(_ curso: String) async {
        selectedCurso = curso
        selectedSubject = nil
        await loadContenido()
    }

    func seleccionarAsignatura(_ asignatura: String) async {
        selectedSubject = asignatura
        await loadContenido()
    }

    func estudiantes(curso: String) -> [EstudiantePerfil] {
        (snapshot?.studentsByCourse[curso] ?? []).sorted { $0.orden < $1.orden }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snap = try await dashboardRepository.fetchDashboard()
            snapshot = snap
            if selectedCurso.isEmpty || !snap.courses.contains(selectedCurso) {
                selectedCurso = snap.courses.first ?? ""
            }
            await loadContenido()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadContenido() async {
        guard !selectedCurso.isEmpty else {
            listas = []
            rubricas = []
            return
        }

        isLoadingContenido = true
        defer { isLoadingContenido = false }

        do {
            // Mostramos TODAS las asignaturas del curso (cada tarjeta indica la suya);
            // el selector de asignatura solo define con qué asignatura se crea una nueva.
            async let listasCargadas = evaluacionesRepository.cargarListasCotejo(asignatura: nil, curso: selectedCurso)
            async let rubricasCargadas = evaluacionesRepository.cargarRubricas(asignatura: nil, curso: selectedCurso)
            listas = try await listasCargadas
            rubricas = try await rubricasCargadas
            errorMessage = nil
        } catch {
            listas = []
            rubricas = []
            errorMessage = "No se pudieron cargar las evaluaciones de este curso."
        }
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
}
