import SwiftUI

struct CronogramaSemanaView: View {
    let viewModel: CronogramaViewModel
    var onEdit: (ActividadCronograma) -> Void
    var onCreate: (String, String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(CronoDateHelpers.diasSemana, id: \.self) { dia in
                    columnaDia(dia)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func columnaDia(_ dia: String) -> some View {
        let fecha = CronoDateHelpers.fechaReal(lunes: viewModel.lunesActual, dia: dia)
        let esHoy = Calendar.current.isDateInToday(fecha)
        let actividades = viewModel.actividadesFiltradas
            .filter { $0.semana == viewModel.semanaActual && $0.dia == dia }
            .sorted { $0.hora < $1.hora }
        let bloques = viewModel.horarioVisible
            .filter { $0.dia == dia }
            .sorted { $0.horaInicio < $1.horaInicio }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(dia.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(esHoy ? EPTheme.primary : .secondary)
                    Text("\(Calendar.current.component(.day, from: fecha))")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(esHoy ? EPTheme.primary : .primary)
                }
                Spacer()
                Button {
                    onCreate(dia, "08:30")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(EPTheme.primary)
                        .frame(width: 26, height: 26)
                        .background(EPTheme.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 11)
            .padding(.top, 11)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(bloques) { bloque in
                    VStack(alignment: .leading, spacing: 2) {
                        Label("\(bloque.horaInicio)–\(bloque.horaFin)", systemImage: "clock")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(bloque.resumen)
                            .font(.system(size: 11, weight: .black))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                ForEach(actividades) { actividad in
                    tarjetaActividad(actividad)
                }

                if actividades.isEmpty && bloques.isEmpty {
                    Text("Sin actividades")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 11)
        }
        .frame(width: 178, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(esHoy ? EPTheme.primary : Color(.separator).opacity(0.1), lineWidth: esHoy ? 1.8 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func tarjetaActividad(_ actividad: ActividadCronograma) -> some View {
        Button {
            onEdit(actividad)
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(EPTheme.color(hex: viewModel.colorUnidad(actividad.unidad)))
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(actividad.hora) · \(actividad.duracion)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.secondary)
                    Text(actividad.nombre)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let curso = actividad.cursoOrigen, !curso.isEmpty {
                        Text(curso)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(EPTheme.primary)
                            .lineLimit(1)
                    }
                    if !actividad.unidad.isEmpty {
                        Text(viewModel.nombreUnidad(actividad.unidad))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(8)

                Spacer(minLength: 0)
            }
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
