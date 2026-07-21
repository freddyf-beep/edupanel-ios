import SwiftUI

struct CronogramaListaView: View {
    let viewModel: CronogramaViewModel
    var onEdit: (ActividadCronograma) -> Void

    @State private var actividadAEliminar: ActividadCronograma?

    private var ordenadasPorSemana: [(semana: Int, actividades: [ActividadCronograma])] {
        let grouped = Dictionary(grouping: viewModel.actividadesFiltradas) { $0.semana }
        return grouped.map { (semana: $0.key, actividades: $0.value.sorted { lhs, rhs in
            let diaIzq = CronoDateHelpers.diasIndice[lhs.dia] ?? 0
            let diaDer = CronoDateHelpers.diasIndice[rhs.dia] ?? 0
            if diaIzq != diaDer { return diaIzq < diaDer }
            return lhs.hora < rhs.hora
        }) }
        .sorted { $0.semana < $1.semana }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if ordenadasPorSemana.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "list.bullet.rectangle",
                        title: "Sin actividades",
                        message: "No hay actividades registradas en esta selección. Créalas desde la vista Semana."
                    )
                }
            } else {
                ForEach(ordenadasPorSemana, id: \.semana) { grupo in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SEMANA \(grupo.semana)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            ForEach(grupo.actividades) { actividad in
                                fila(actividad)

                                if actividad.id != grupo.actividades.last?.id {
                                    Divider()
                                        .padding(.leading, 26)
                                }
                            }
                        }
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .alert("¿Eliminar actividad?", isPresented: Binding(
            get: { actividadAEliminar != nil },
            set: { if !$0 { actividadAEliminar = nil } }
        ), presenting: actividadAEliminar) { actividad in
            Button("Eliminar", role: .destructive) {
                viewModel.eliminar(id: actividad.id)
                actividadAEliminar = nil
            }
            Button("Cancelar", role: .cancel) {
                actividadAEliminar = nil
            }
        } message: { actividad in
            Text("Se quitará \"\(actividad.nombre)\" del cronograma.")
        }
    }

    private func fila(_ actividad: ActividadCronograma) -> some View {
        let fecha = viewModel.fecha(de: actividad)
        let dia = Calendar.current.component(.day, from: fecha)
        let mes = Calendar.current.component(.month, from: fecha)

        return HStack(spacing: 12) {
            Capsule()
                .fill(EPTheme.color(hex: viewModel.colorUnidad(actividad.unidad)))
                .frame(width: 4, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(actividad.nombre)
                        .font(.footnote.weight(.black))
                        .lineLimit(1)
                    if let curso = actividad.cursoOrigen, !curso.isEmpty {
                        Text(curso)
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(EPTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(EPTheme.primary.opacity(0.08), in: Capsule())
                            .lineLimit(1)
                    }
                }
                Text("\(actividad.dia) \(dia)/\(mes) · \(actividad.hora) (\(actividad.duracion))\(actividad.unidad.isEmpty ? "" : " · \(viewModel.nombreUnidad(actividad.unidad))")")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    onEdit(actividad)
                } label: {
                    Label("Editar actividad", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    actividadAEliminar = actividad
                } label: {
                    Label("Eliminar", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
