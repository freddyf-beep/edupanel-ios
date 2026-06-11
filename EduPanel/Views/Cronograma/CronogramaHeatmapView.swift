import SwiftUI

struct CronogramaHeatmapView: View {
    let viewModel: CronogramaViewModel

    private let columnas = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let diasHeader = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
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

                leyenda

                HStack {
                    ForEach(diasHeader, id: \.self) { dia in
                        Text(dia)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                let conteos = conteoPorFecha
                let maximo = max(1, conteos.values.max() ?? 1)

                LazyVGrid(columns: columnas, spacing: 5) {
                    ForEach(Array(diasDelMes.enumerated()), id: \.offset) { item in
                        celda(item.element, conteos: conteos, maximo: maximo)
                    }
                }

                Text("Pinta más oscuro los días con más actividades. Útil para detectar semanas sobrecargadas.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var leyenda: some View {
        HStack(spacing: 6) {
            Text("Menos")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { opacidad in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(opacidad == 0 ? AnyShapeStyle(Color(.systemGray5)) : AnyShapeStyle(EPTheme.primary.opacity(opacidad)))
                        .frame(width: 18, height: 12)
                }
            }
            Text("Más")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var conteoPorFecha: [String: Int] {
        var resultado: [String: Int] = [:]
        for actividad in viewModel.actividadesFiltradas {
            let fecha = viewModel.fecha(de: actividad)
            resultado[DateHelpers.dateKey(for: fecha), default: 0] += 1
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
    private func celda(_ date: Date?, conteos: [String: Int], maximo: Int) -> some View {
        if let date {
            let cantidad = conteos[DateHelpers.dateKey(for: date)] ?? 0
            let intensidad = Double(cantidad) / Double(maximo)
            let fondo = cantidad == 0
                ? AnyShapeStyle(Color(.tertiarySystemGroupedBackground))
                : AnyShapeStyle(EPTheme.primary.opacity(0.15 + intensidad * 0.85))

            VStack {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(intensidad > 0.55 ? .white : .primary)
                Spacer(minLength: 0)
                if cantidad > 0 {
                    Text("\(cantidad)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(intensidad > 0.55 ? .white : EPTheme.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            .background(fondo, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color(.separator).opacity(0.12), lineWidth: 1)
            )
        } else {
            Color.clear
                .frame(minHeight: 48)
        }
    }
}
