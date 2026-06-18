import SwiftUI

/// Sección compartida por los editores de Rúbrica y Lista: selector de unidad
/// curricular + editor de OAs reales del currículum. Carga unidades y OAs desde
/// la colección global `curriculo` reutilizando CurriculoRepository.
struct EvaluacionesCurriculoSection: View {
    let asignatura: String
    let curso: String
    let nivelMapping: [String: String]
    @Binding var unidadId: String?
    @Binding var unidadNombre: String?
    @Binding var oas: [OAEditado]?

    @State private var unidades: [UnidadCurricular] = []
    @State private var cargandoUnidades = false
    @State private var cargandoOAs = false
    @State private var aviso: String?

    private let curriculoRepository = CurriculoRepository()
    private let planificacionRepository = PlanificacionRepository()

    private var nivel: String? {
        CurriculoNivel.resolver(curso: curso, mapping: nivelMapping)
    }

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(
                    title: "Curr\u{00ED}culum",
                    subtitle: "Vincula una unidad y selecciona los OA que se eval\u{00FA}an.",
                    icon: "books.vertical"
                )

                if nivel == nil {
                    Text("Configura el nivel curricular de \u{201C}\(curso)\u{201D} en Mi Perfil para cargar las unidades del curr\u{00ED}culum.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    unidadPicker

                    if let aviso {
                        Text(aviso)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.orange)
                    }

                    OAEditorView(oas: oasBinding, asignatura: asignatura, cargando: cargandoOAs)
                }
            }
        }
        .task(id: cargaKey) {
            await cargarUnidades()
        }
    }

    private var cargaKey: String { "\(asignatura)|\(curso)|\(nivel ?? "")" }

    private var unidadPicker: some View {
        Menu {
            if !unidades.isEmpty {
                Button("Sin unidad") {
                    unidadId = nil
                    unidadNombre = nil
                }
            }
            ForEach(unidades) { unidad in
                Button {
                    Task { await seleccionarUnidad(unidad) }
                } label: {
                    if unidad.id == unidadId {
                        Label("U\(unidad.numeroUnidad) \u{00B7} \(unidad.nombreUnidad)", systemImage: "checkmark")
                    } else {
                        Text("U\(unidad.numeroUnidad) \u{00B7} \(unidad.nombreUnidad)")
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
        .disabled(cargandoUnidades || unidades.isEmpty)
    }

    private var unidadLabel: String {
        if let unidadNombre, !unidadNombre.isEmpty { return unidadNombre }
        if unidades.isEmpty && !cargandoUnidades { return "Sin unidades en el curr\u{00ED}culum" }
        return "Selecciona una unidad"
    }

    private var oasBinding: Binding<[OAEditado]> {
        Binding(
            get: { oas ?? [] },
            set: { oas = $0 }
        )
    }

    private func cargarUnidades() async {
        guard let nivel else {
            unidades = []
            return
        }
        cargandoUnidades = true
        aviso = nil
        defer { cargandoUnidades = false }
        do {
            unidades = try await curriculoRepository.getUnidades(asignatura: asignatura, nivel: nivel)
            if unidades.isEmpty {
                aviso = "No hay unidades en el curr\u{00ED}culum para \(asignatura) \u{00B7} \(nivel)."
            } else if let unidadId, (oas ?? []).isEmpty,
                      let unidad = unidades.first(where: { $0.id == unidadId }) {
                await seleccionarUnidad(unidad)
            }
        } catch {
            aviso = "No se pudo cargar el curr\u{00ED}culum."
        }
    }

    private func seleccionarUnidad(_ unidad: UnidadCurricular) async {
        guard let nivel else { return }
        unidadId = unidad.id
        unidadNombre = unidad.nombreUnidad
        cargandoOAs = true
        defer { cargandoOAs = false }
        do {
            guard let completa = try await curriculoRepository.getUnidadCompleta(asignatura: asignatura, nivel: nivel, unidadId: unidad.id) else {
                aviso = "La unidad no tiene OA en el curr\u{00ED}culum."
                return
            }
            let base = CurriculoOA.initOAs(unidad: completa, asignatura: asignatura)
            let verUnidadOAs = (try? await planificacionRepository.cargarVerUnidadConFallback(asignatura: asignatura, curso: curso, unidadId: unidad.id))?.oas ?? []
            var merged = CurriculoOA.mergeOAs(base: base, saved: verUnidadOAs)
            if let existentes = oas, !existentes.isEmpty {
                merged = CurriculoOA.mergeOAs(base: merged, saved: existentes)
            }
            oas = merged
            aviso = nil
        } catch {
            aviso = "No se pudieron cargar los OA de la unidad."
        }
    }
}
