import SwiftUI

struct ListasHubView: View {
    @Bindable var viewModel: EvaluacionesViewModel

    @State private var listaAEliminar: ListaCotejoTemplate?
    @State private var listaADuplicar: ListaCotejoTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                EPSectionHeader(
                    title: "Listas de cotejo",
                    subtitle: "Indicadores observables con registro S\u{00ED}/No por estudiante.",
                    icon: "checklist"
                )

                NavigationLink(value: AppRoute.listaCotejoEditor(listaId: nil, curso: viewModel.selectedCurso, asignatura: viewModel.activeSubject)) {
                    Label("Nueva lista", systemImage: "plus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(EPTheme.primary, in: Capsule())
                }
            }

            if viewModel.isLoadingContenido {
                EvaluacionesLoadingCard(texto: "Cargando listas...")
            } else if let error = viewModel.listasErrorMessage {
                EvaluacionesRetryCard(
                    title: "No se pudieron cargar las listas",
                    message: error,
                    isLoading: viewModel.isLoadingContenido
                ) {
                    Task { await viewModel.loadContenido() }
                }
            } else if viewModel.listas.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "checklist",
                        title: "No hay listas de cotejo para este curso",
                        message: "Crea una nueva lista con indicadores y escala S\u{00ED}/No."
                    )
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.listas) { lista in
                        ListaCotejoCardView(
                            lista: lista,
                            onEliminar: { listaAEliminar = lista },
                            onDuplicar: { listaADuplicar = lista }
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "\u{00BF}Eliminar esta lista de cotejo?",
            isPresented: Binding(
                get: { listaAEliminar != nil },
                set: { if !$0 { listaAEliminar = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let lista = listaAEliminar {
                    Task { await viewModel.eliminarLista(lista) }
                }
                listaAEliminar = nil
            }
            Button("Cancelar", role: .cancel) { listaAEliminar = nil }
        } message: {
            Text("Se eliminar\u{00E1} tambi\u{00E9}n la evaluaci\u{00F3}n asociada.")
        }
        .confirmationDialog(
            "Duplicar lista en...",
            isPresented: Binding(
                get: { listaADuplicar != nil },
                set: { if !$0 { listaADuplicar = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(viewModel.cursos, id: \.self) { curso in
                Button(curso) {
                    if let lista = listaADuplicar {
                        Task { await viewModel.duplicarLista(lista, cursoDestino: curso) }
                    }
                    listaADuplicar = nil
                }
            }
            Button("Cancelar", role: .cancel) { listaADuplicar = nil }
        }
    }
}

struct ListaCotejoCardView: View {
    let lista: ListaCotejoTemplate
    let onEliminar: () -> Void
    let onDuplicar: () -> Void

    private var totalIndicadores: Int {
        lista.indicadoresTotales.count
    }

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(EPTheme.primary)
                        .frame(width: 32, height: 32)
                        .background(EPTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        EPStatusPill(text: lista.asignatura.isEmpty ? "Sin asignatura" : lista.asignatura, icon: "book.closed.fill", tint: EPTheme.primary)
                        Text(lista.nombre.isEmpty ? "Lista de cotejo" : lista.nombre)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(lista.curso) \u{00B7} \(totalIndicadores) indicadores \u{00B7} \(Int(lista.puntajeMaximo)) pts")
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

                if let fecha = lista.fechaActualizacion {
                    EPStatusPill(
                        text: fecha.formatted(date: .abbreviated, time: .omitted),
                        icon: "clock",
                        tint: .secondary
                    )
                }

                HStack(spacing: 8) {
                    NavigationLink(value: AppRoute.listaCotejoEditor(listaId: lista.id, curso: lista.curso, asignatura: lista.asignatura)) {
                        ListaAccionLabel(titulo: "Editar", icono: "pencil", relleno: false)
                    }
                    NavigationLink(value: AppRoute.listaEvaluacion(listaId: lista.id)) {
                        ListaAccionLabel(titulo: "Evaluar", icono: "checkmark.circle.fill", relleno: true)
                    }
                    NavigationLink(value: AppRoute.listaResultados(listaId: lista.id)) {
                        ListaAccionLabel(titulo: "Resultados", icono: "chart.bar.fill", relleno: false)
                    }
                }
            }
        }
    }
}

struct ListaAccionLabel: View {
    let titulo: String
    let icono: String
    let relleno: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icono)
                .font(.system(size: 10, weight: .black))
            Text(titulo)
                .font(.system(size: 11.5, weight: .black))
        }
        .foregroundStyle(relleno ? .white : EPTheme.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            relleno ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(EPTheme.primary.opacity(0.1)),
            in: Capsule()
        )
    }
}
