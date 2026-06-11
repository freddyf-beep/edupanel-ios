import SwiftUI

struct CronogramaMesView: View {
    let viewModel: CronogramaViewModel
    var onSelectDay: (Date) -> Void

    private let columnas = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let diasHeader = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                navegacionMes

                HStack {
                    ForEach(diasHeader, id: \.self) { dia in
                        Text(dia)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                let porFecha = actividadesPorFecha

                LazyVGrid(columns: columnas, spacing: 5) {
                    ForEach(Array(diasDelMes.enumerated()), id: \.offset) { item in
                        celda(item.element, porFecha: porFecha)
                    }
                }

                Text("Toca un día para abrir la vista Día.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var navegacionMes: some View {
        HStack {
            Button {
                viewModel.cambiarMes(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.black))
                    .padding(8)
                    .background(Color(.systemGray6), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(CronoDateHelpers.tituloMes(viewModel.currentDate))
                .font(.headline.weight(.black))

            Spacer()

            Button {
                viewModel.cambiarMes(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .padding(8)
                    .background(Color(.systemGray6), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var actividadesPorFecha: [String: [ActividadCronograma]] {
        var resultado: [String: [ActividadCronograma]] = [:]
        for actividad in viewModel.actividadesFiltradas {
            let fecha = viewModel.fecha(de: actividad)
            resultado[DateHelpers.dateKey(for: fecha), default: []].append(actividad)
        }
        return resultado
    }

    private var diasDelMes: [Date?] {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: viewModel.currentDate)
        comps.day = 1
        guard let primerDia = calendar.date(from: comps),
              let rango = calendar.range(of: .day, in: .month, for: primerDia) else { return [] }

        let weekday = calendar.component(.weekday, from: primerDia)
        let offset = (weekday + 5) % 7
        var resultado: [Date?] = Array(repeating: nil, count: offset)
        for dia in rango {
            comps.day = dia
            resultado.append(calendar.date(from: comps))
        }
        while resultado.count % 7 != 0 {
            resultado.append(nil)
        }
        return resultado
    }

    @ViewBuilder
    private func celda(_ date: Date?, porFecha: [String: [ActividadCronograma]]) -> some View {
        if let date {
            let calendar = Calendar.current
            let esHoy = calendar.isDateInToday(date)
            let weekday = calendar.component(.weekday, from: date)
            let esFinDeSemana = weekday == 1 || weekday == 7
            let actividades = (porFecha[DateHelpers.dateKey(for: date)] ?? []).sorted { $0.hora < $1.hora }

            Button {
                onSelectDay(date)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 11, weight: esHoy ? .black : .bold))
                        .foregroundStyle(esHoy ? EPTheme.primary : .primary)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(actividades.prefix(2))) { actividad in
                            Text(actividad.nombre)
                                .font(.system(size: 7.5, weight: .black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    EPTheme.color(hex: viewModel.colorUnidad(actividad.unidad)),
                                    in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                                )
                        }
                        if actividades.count > 2 {
                            Text("+\(actividades.count - 2)")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                .background(
                    esHoy ? EPTheme.primary.opacity(0.1) : Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    if esHoy {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(EPTheme.primary, lineWidth: 1.5)
                    }
                }
                .opacity(esFinDeSemana ? 0.55 : 1)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(minHeight: 62)
        }
    }
}
