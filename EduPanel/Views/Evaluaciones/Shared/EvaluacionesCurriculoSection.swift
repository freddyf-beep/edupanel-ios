import SwiftUI

/// Sección compartida por los editores de Rúbrica y Lista: selector de unidad
/// curricular + editor de OAs reales del currículum. Carga unidades y OAs desde
/// la colección global `curriculo` reutilizando CurriculoRepository.
struct EvaluacionesCurriculoSection: View {
    let asignatura: String
    let curso: String
    let nivelMapping: [String: String]
    let subjectLevelMapping: [String: [String: String]]
    let catalogLevel: String?
    let autoResolveExistingUnit: Bool
    @Binding var unidadId: String?
    @Binding var unidadNombre: String?
    @Binding var oas: [OAEditado]?

    @State private var unidadesPlanificadas: [UnidadPlan] = []
    @State private var cargandoUnidades = false
    @State private var cargandoOAs = false
    @State private var aviso: String?
    @State private var loadGeneration = 0
    @State private var selectionGeneration = 0

    private let curriculoRepository = CurriculoRepository()
    private let planificacionRepository = PlanificacionRepository()

    init(
        asignatura: String,
        curso: String,
        nivelMapping: [String: String],
        subjectLevelMapping: [String: [String: String]] = [:],
        catalogLevel: String? = nil,
        autoResolveExistingUnit: Bool = true,
        unidadId: Binding<String?>,
        unidadNombre: Binding<String?>,
        oas: Binding<[OAEditado]?>
    ) {
        self.asignatura = asignatura
        self.curso = curso
        self.nivelMapping = nivelMapping
        self.subjectLevelMapping = subjectLevelMapping
        self.catalogLevel = catalogLevel
        self.autoResolveExistingUnit = autoResolveExistingUnit
        _unidadId = unidadId
        _unidadNombre = unidadNombre
        _oas = oas
    }

    private var nivel: String? {
        CurriculoNivel.resolver(
            curso: curso,
            asignatura: asignatura,
            catalogLevel: catalogLevel,
            mapping: nivelMapping,
            subjectMapping: subjectLevelMapping
        )
    }

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(
                    title: "Curr\u{00ED}culum",
                    subtitle: "Vincula una unidad y selecciona los OA que se eval\u{00FA}an.",
                    icon: "books.vertical"
                )

                unidadPicker

                if nivel == nil {
                    Text("La unidad se puede vincular, pero falta definir el nivel curricular de “\(curso)” para cargar sus OA oficiales.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let aviso {
                    Text(aviso)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.orange)
                }

                OAEditorView(oas: oasBinding, asignatura: asignatura, cargando: cargandoOAs)
            }
        }
        .task(id: cargaKey) {
            await cargarUnidades()
        }
    }

    private var cargaKey: String { "\(asignatura)|\(curso)|\(nivel ?? "")" }

    private var unidadPicker: some View {
        Menu {
            Button("Sin unidad") {
                clearUnitSelection()
            }
            ForEach(unidadesPlanificadas) { unidad in
                Button {
                    Task { await seleccionarUnidad(unidad) }
                } label: {
                    if unitMatchesSelection(unidad) {
                        Label(unidad.name, systemImage: "checkmark")
                    } else {
                        Text(unidad.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11, weight: .black))
                Text(unidadLabel)
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
                Spacer()
                if cargandoUnidades {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .black))
                }
            }
            .foregroundStyle(EPTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(EPTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(cargandoUnidades || unidadesPlanificadas.isEmpty)
    }

    private var unidadLabel: String {
        if let unidadNombre, !unidadNombre.isEmpty { return unidadNombre }
        if unidadesPlanificadas.isEmpty && !cargandoUnidades { return "Sin unidades planificadas" }
        return "Selecciona una unidad del curso"
    }

    private var oasBinding: Binding<[OAEditado]> {
        Binding(
            get: { oas ?? [] },
            set: { oas = $0 }
        )
    }

    private func cargarUnidades() async {
        loadGeneration += 1
        let generation = loadGeneration
        cargandoUnidades = true
        aviso = nil
        defer {
            if generation == loadGeneration {
                cargandoUnidades = false
            }
        }
        do {
            let plan = try await planificacionRepository.cargarPlanCurso(
                asignatura: asignatura,
                curso: curso
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            unidadesPlanificadas = plan?.units ?? []
            if unidadesPlanificadas.isEmpty {
                aviso = "Crea una unidad en Planificaciones antes de vincular este instrumento."
            } else if autoResolveExistingUnit, let unidadId,
                      let unidad = unidadesPlanificadas.first(where: {
                          String($0.id) == unidadId || $0.unidadCurricularId == unidadId
                      }) {
                await seleccionarUnidad(unidad)
            }
        } catch {
            guard generation == loadGeneration else { return }
            unidadesPlanificadas = []
            aviso = "No se pudieron cargar las unidades planificadas del curso."
        }
    }

    private func seleccionarUnidad(_ unidad: UnidadPlan) async {
        selectionGeneration += 1
        let generation = selectionGeneration
        let previousUnitID = unidadId
        let localUnitID = String(unidad.id)
        let isSameUnit = previousUnitID == localUnitID ||
            previousUnitID == unidad.unidadCurricularId
        let previousOAs = oas ?? []

        unidadId = localUnitID
        unidadNombre = unidad.name
        guard let nivel else {
            oas = isSameUnit ? previousOAs : previousOAs.filter { $0.esPropio == true }
            aviso = "Define el nivel curricular del curso para cargar los OA."
            return
        }
        guard let curriculumUnitID = unidad.unidadCurricularId,
              !curriculumUnitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            oas = isSameUnit ? previousOAs : previousOAs.filter { $0.esPropio == true }
            aviso = "Vincula esta unidad con el currículum desde Planificaciones para cargar sus OA."
            return
        }

        cargandoOAs = true
        defer {
            if generation == selectionGeneration {
                cargandoOAs = false
            }
        }
        do {
            guard let completa = try await curriculoRepository.getUnidadCompleta(
                asignatura: asignatura,
                nivel: nivel,
                unidadId: curriculumUnitID
            ) else {
                aviso = "La unidad no tiene OA en el curr\u{00ED}culum."
                return
            }
            let base = CurriculoOA.initOAs(unidad: completa, asignatura: asignatura)
            let verUnidadOAs = (try? await planificacionRepository.cargarVerUnidadConFallback(
                asignatura: asignatura,
                curso: curso,
                unidadId: localUnitID
            ))?.oas ?? []
            var merged = CurriculoOA.mergeOAs(base: base, saved: verUnidadOAs)
            let preserved = isSameUnit
                ? previousOAs
                : previousOAs.filter { $0.esPropio == true }
            if !preserved.isEmpty {
                merged = CurriculoOA.mergeOAs(base: merged, saved: preserved)
            }
            guard generation == selectionGeneration,
                  unidadId == localUnitID,
                  !Task.isCancelled else { return }
            oas = merged
            aviso = nil
        } catch {
            guard generation == selectionGeneration else { return }
            aviso = "No se pudieron cargar los OA de la unidad."
        }
    }

    private func clearUnitSelection() {
        selectionGeneration += 1
        unidadId = nil
        unidadNombre = nil
        oas = []
        aviso = nil
    }

    private func unitMatchesSelection(_ unit: UnidadPlan) -> Bool {
        unidadId == String(unit.id) || unidadId == unit.unidadCurricularId
    }
}
