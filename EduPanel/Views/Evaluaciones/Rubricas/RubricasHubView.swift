import SwiftUI

struct RubricasHubView: View {
    @Bindable var viewModel: EvaluacionesViewModel

    @State private var rubricaAEliminar: RubricaTemplate?
    @State private var rubricaADuplicar: RubricaTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                EPSectionHeader(
                    title: "R\u{00FA}bricas",
                    subtitle: "Criterios con 4 niveles de logro y nota autom\u{00E1}tica.",
                    icon: "square.grid.2x2"
                )

                NavigationLink(value: AppRoute.rubricaEditor(rubricaId: nil, curso: viewModel.selectedCurso, asignatura: viewModel.activeSubject)) {
                    Label("Nueva r\u{00FA}brica", systemImage: "plus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(EPTheme.primary, in: Capsule())
                }
            }

            if viewModel.isLoadingContenido {
                EvaluacionesLoadingCard(texto: "Cargando r\u{00FA}bricas...")
            } else if viewModel.rubricas.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "square.grid.2x2",
                        title: "No hay r\u{00FA}bricas para este curso",
                        message: "Crea una nueva r\u{00FA}brica con partes, criterios y niveles de logro."
                    )
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.rubricas) { rubrica in
                        RubricaCardView(
                            rubrica: rubrica,
                            onEliminar: { rubricaAEliminar = rubrica },
                            onDuplicar: { rubricaADuplicar = rubrica }
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "\u{00BF}Eliminar esta r\u{00FA}brica?",
            isPresented: Binding(
                get: { rubricaAEliminar != nil },
                set: { if !$0 { rubricaAEliminar = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let rubrica = rubricaAEliminar {
                    Task { await viewModel.eliminarRubrica(rubrica) }
                }
                rubricaAEliminar = nil
            }
            Button("Cancelar", role: .cancel) { rubricaAEliminar = nil }
        } message: {
            Text("Se eliminar\u{00E1} tambi\u{00E9}n la evaluaci\u{00F3}n asociada.")
        }
        .confirmationDialog(
            "Duplicar r\u{00FA}brica en...",
            isPresented: Binding(
                get: { rubricaADuplicar != nil },
                set: { if !$0 { rubricaADuplicar = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(viewModel.cursos, id: \.self) { curso in
                Button(curso) {
                    if let rubrica = rubricaADuplicar {
                        Task { await viewModel.duplicarRubrica(rubrica, cursoDestino: curso) }
                    }
                    rubricaADuplicar = nil
                }
            }
            Button("Cancelar", role: .cancel) { rubricaADuplicar = nil }
        }
    }
}

struct RubricaCardView: View {
    let rubrica: RubricaTemplate
    let onEliminar: () -> Void
    let onDuplicar: () -> Void

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(EPTheme.fuchsia)
                        .frame(width: 32, height: 32)
                        .background(EPTheme.fuchsia.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(rubrica.nombre.isEmpty ? "R\u{00FA}brica" : rubrica.nombre)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(rubrica.curso) \u{00B7} \(rubrica.criteriosTotales.count) criterios \u{00B7} \(Int(rubrica.puntajeMaximo)) pts")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Menu {
                        Button("Duplicar", systemImage: "doc.on.doc", action: onDuplicar)
                        Button("Eliminar", systemImage: "trash", role: .destructive, action: onEliminar)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray6), in: Circle())
                    }
                }

                if let fecha = rubrica.fechaActualizacion {
                    EPStatusPill(
                        text: fecha.formatted(date: .abbreviated, time: .omitted),
                        icon: "clock",
                        tint: .secondary
                    )
                }

                HStack(spacing: 8) {
                    NavigationLink(value: AppRoute.rubricaEditor(rubricaId: rubrica.id, curso: rubrica.curso, asignatura: rubrica.asignatura)) {
                        ListaAccionLabel(titulo: "Editar", icono: "pencil", relleno: false)
                    }
                    NavigationLink(value: AppRoute.rubricaEvaluacion(rubricaId: rubrica.id)) {
                        ListaAccionLabel(titulo: "Evaluar", icono: "checkmark.circle.fill", relleno: true)
                    }
                    NavigationLink(value: AppRoute.rubricaResultados(rubricaId: rubrica.id)) {
                        ListaAccionLabel(titulo: "Resultados", icono: "chart.bar.fill", relleno: false)
                    }
                }
            }
        }
    }
}
