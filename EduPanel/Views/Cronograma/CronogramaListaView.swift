import SwiftUI

struct CronogramaListaView: View {
    let viewModel: CronogramaViewModel
    var onEdit: (ActividadCronograma) -> Void

    @State private var actividadAEliminar: ActividadCronograma?

    private var ordenadas: [ActividadCronograma] {
        viewModel.actividadesFiltradas.sorted { lhs, rhs in
            if lhs.semana != rhs.semana { return lhs.semana < rhs.semana }
            let diaIzq = CronoDateHelpers.diasIndice[lhs.dia] ?? 0
            let diaDer = CronoDateHelpers.diasIndice[rhs.dia] ?? 0
            if diaIzq != diaDer { return diaIzq < diaDer }
            return lhs.hora < rhs.hora
        }
    }

    var body: some View {
        EPWebCard(padding: 12) {
            if ordenadas.isEmpty {
                EPEmptyState(
                    icon: "list.bullet.rectangle",
                    title: "Sin actividades",
                    message: "No hay actividades en este filtro. Créalas desde la vista Semana."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(ordenadas) { actividad in
                        fila(actividad)
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

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(EPTheme.color(hex: viewModel.colorUnidad(actividad.unidad)))
                .frame(width: 4, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(actividad.nombre)
                        .font(.footnote.weight(.black))
                        .lineLimit(1)
                    if let curso = actividad.cursoOrigen, !curso.isEmpty {
                        Text(curso)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(EPTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(EPTheme.primary.opacity(0.1), in: Capsule())
                    }
                }
                Text("Sem \(actividad.semana) · \(actividad.dia) \(dia)/\(mes) · \(actividad.hora) · \(actividad.duracion)\(actividad.unidad.isEmpty ? "" : " · \(viewModel.nombreUnidad(actividad.unidad))")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Button {
                onEdit(actividad)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.systemGray5), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                actividadAEliminar = actividad
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .background(.red.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
