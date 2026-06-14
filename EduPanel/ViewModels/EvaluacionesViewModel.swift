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
        selectedSubject ?? availableSubjects.first ?? Self.defaultSubject
    }

    var availableSubjects: [String] {
        let habilitadas = snapshot?.preferences.asignaturasHabilitadas
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        if !habilitadas.isEmpty { return habilitadas }
        let especialidad = snapshot?.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [especialidad.isEmpty ? Self.defaultSubject : especialidad]
    }

    var cursos: [String] {
        snapshot?.courses ?? []
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
            async let listasCargadas = evaluacionesRepository.cargarListasCotejo(asignatura: activeSubject, curso: selectedCurso)
            async let rubricasCargadas = evaluacionesRepository.cargarRubricas(asignatura: activeSubject, curso: selectedCurso)
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
