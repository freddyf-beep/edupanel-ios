import SwiftUI

struct ListaResultadosView: View {
    let listaId: String

    @State private var lista: ListaCotejoTemplate?
    @State private var evaluacion: ListaCotejoEvaluacion?
    @State private var incluirAusentes = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let repository = EvaluacionesRepository()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    EvaluacionesLoadingCard(texto: "Cargando resultados...")
                } else if let errorMessage {
                    EvaluacionesErrorBanner(message: errorMessage)
                } else if lista != nil {
                    contenido
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Resultados")
        .task { await cargar() }
    }

    @ViewBuilder
    private var contenido: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(lista?.nombre.isEmpty == false ? lista!.nombre : "Lista de cotejo")
                        .font(.system(size: 17, weight: .black))
                    if evaluacion?.bloqueada == true {
                        EPStatusPill(text: "Finalizada", icon: "lock.fill", tint: .orange)
                    }
                }
                Text("\(lista?.curso ?? "") \u{00B7} \(Int(lista?.puntajeMaximo ?? 0)) pts m\u{00E1}x.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if estudiantesConDatos.isEmpty {
            EPWebCard {
                EPEmptyState(
                    icon: "chart.bar",
                    title: "Sin registros a\u{00FA}n",
                    message: "Eval\u{00FA}a a tus estudiantes para ver los resultados aqu\u{00ED}."
                )
            }
        } else {
            if !ausentes.isEmpty {
                BannerAusentes(
                    cantidad: ausentes.count,
                    incluidos: incluirAusentes,
                    onToggle: { withAnimation(EPTheme.spring) { incluirAusentes.toggle() } }
                )
            }

            kpis
            tablaResultados
        }
    }

    private var kpis: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            EPKPIBox(title: "Evaluados", value: "\(activos.count)", subtitle: "Estudiantes considerados", icon: "person.2.fill")
            EPKPIBox(
                title: "Promedio",
                value: NotaChilena.formato(promedio),
                subtitle: "Nota promedio del curso",
                icon: "chart.line.uptrend.xyaxis",
                tint: (promedio ?? 1) >= 4 ? .green : .red
            )
            EPKPIBox(title: "Aprobados", value: "\(aprobados)", subtitle: "Nota 4.0 o superior", icon: "checkmark.seal.fill", tint: .green)
            EPKPIBox(title: "Reprobados", value: "\(activos.count - aprobados)", subtitle: "Bajo nota 4.0", icon: "xmark.seal.fill", tint: .red)
        }
    }

    private var tablaResultados: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 0) {
                EPSectionHeader(title: "Detalle por estudiante", icon: "list.bullet.rectangle")
                    .padding(.bottom, 12)

                ForEach(Array(ordenados.enumerated()), id: \.element.estudianteId) { index, est in
                    let esAusente = ausentes.contains { $0.estudianteId == est.estudianteId }
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(est.nombre)
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                                if esAusente {
                                    Text("Ausente")
                                        .font(.system(size: 8.5, weight: .black))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                                if est.hasPie {
                                    Text("PIE")
                                        .font(.system(size: 8.5, weight: .black))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.purple)
                                }
                            }
                            Text("\(Int(est.puntaje ?? 0)) pts \u{00B7} \(Int(est.porcentaje ?? 0))% logro")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(NotaChilena.formato(est.nota))
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle((est.nota ?? 1) >= 4 ? .green : .red)
                    }
                    .padding(.vertical, 9)

                    if index < ordenados.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Estadísticas

    private var todos: [EstudianteListaCotejo] {
        evaluacion?.todosLosEstudiantes ?? []
    }

    private var ausentes: [EstudianteListaCotejo] {
        evaluacion?.estudiantesAusentes ?? []
    }

    private var activos: [EstudianteListaCotejo] {
        incluirAusentes
            ? todos
            : todos.filter { est in !ausentes.contains { $0.estudianteId == est.estudianteId } }
    }

    private var estudiantesConDatos: [EstudianteListaCotejo] {
        todos.filter { !$0.respuestas.isEmpty }
    }

    private var ordenados: [EstudianteListaCotejo] {
        activos.sorted { ($0.nota ?? 0) > ($1.nota ?? 0) }
    }

    private var aprobados: Int {
        activos.filter { ($0.nota ?? 0) >= 4.0 }.count
    }

    private var promedio: Double? {
        guard !activos.isEmpty else { return nil }
        let suma = activos.reduce(0.0) { $0 + ($1.nota ?? 1.0) }
        return suma / Double(activos.count)
    }

    private func cargar() async {
        defer { isLoading = false }
        do {
            guard let listaCargada = try await repository.cargarListaCotejo(id: listaId) else {
                errorMessage = "Lista de cotejo no encontrada."
                return
            }
            lista = listaCargada

            if var evaluacionCargada = try await repository.cargarEvaluacionLista(listaId: listaId) {
                for grupoIndex in evaluacionCargada.grupos.indices {
                    for estIndex in evaluacionCargada.grupos[grupoIndex].estudiantes.indices {
                        evaluacionCargada.grupos[grupoIndex].estudiantes[estIndex].recalcular(con: listaCargada)
                    }
                }
                evaluacion = evaluacionCargada
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BannerAusentes: View {
    let cantidad: Int
    let incluidos: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
            Text("\(cantidad) estudiante\(cantidad == 1 ? "" : "s") ausente\(cantidad == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .black))

            Spacer()

            Button(action: onToggle) {
                Text(incluidos ? "Incluidos en estad\u{00ED}sticas" : "Excluidos de estad\u{00ED}sticas")
                    .font(.system(size: 11, weight: .black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(incluidos ? 0.9 : 0.4), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.orange)
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
