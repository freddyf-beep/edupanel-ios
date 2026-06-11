import SwiftUI

struct CronogramaGanttView: View {
    let viewModel: CronogramaViewModel

    private struct RangoUnidad: Identifiable {
        let unidadId: String
        let nombre: String
        let colorHex: String
        let semanaMin: Int
        let semanaMax: Int
        let cantidad: Int

        var id: String { unidadId }
    }

    private let labelWidth: CGFloat = 110
    private let trackWidth: CGFloat = 560

    private var rangos: [RangoUnidad] {
        var mapa: [String: (min: Int, max: Int, count: Int)] = [:]
        for actividad in viewModel.actividadesFiltradas {
            let clave = actividad.unidad.isEmpty ? "(sin unidad)" : actividad.unidad
            if var actual = mapa[clave] {
                actual.min = min(actual.min, actividad.semana)
                actual.max = max(actual.max, actividad.semana)
                actual.count += 1
                mapa[clave] = actual
            } else {
                mapa[clave] = (actividad.semana, actividad.semana, 1)
            }
        }
        return mapa.map { clave, rango in
            RangoUnidad(
                unidadId: clave,
                nombre: clave == "(sin unidad)" ? "Sin unidad" : viewModel.nombreUnidad(clave),
                colorHex: clave == "(sin unidad)" ? "#9CA3AF" : viewModel.colorUnidad(clave),
                semanaMin: rango.min,
                semanaMax: rango.max,
                cantidad: rango.count
            )
        }
        .sorted { $0.semanaMin < $1.semanaMin }
    }

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(
                    title: "Distribución de unidades en el año",
                    subtitle: "Cada barra muestra el rango de semanas con actividades planificadas.",
                    icon: "chart.bar.doc.horizontal.fill"
                )

                if rangos.isEmpty {
                    EPEmptyState(
                        icon: "chart.bar.doc.horizontal",
                        title: "Sin datos para el Gantt",
                        message: "Crea actividades con unidad asignada para visualizar su distribución."
                    )
                } else {
                    gantt
                }
            }
        }
    }

    private var gantt: some View {
        let semanaMin = max(1, rangos.map(\.semanaMin).min() ?? 1)
        let semanaMax = min(53, max(rangos.map(\.semanaMax).max() ?? 52, semanaMin + 3))
        let totalSemanas = semanaMax - semanaMin + 1

        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Unidad")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)

                    ZStack(alignment: .leading) {
                        ForEach(0..<totalSemanas, id: \.self) { indice in
                            let semana = semanaMin + indice
                            if semana % 4 == 0 || indice == 0 || indice == totalSemanas - 1 {
                                Text("\(semana)")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .offset(x: trackWidth * CGFloat(indice) / CGFloat(totalSemanas))
                            }
                        }
                    }
                    .frame(width: trackWidth, height: 14, alignment: .leading)
                }

                ForEach(rangos) { rango in
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(EPTheme.color(hex: rango.colorHex))
                                .frame(width: 9, height: 9)
                            Text(rango.nombre)
                                .font(.system(size: 11, weight: .black))
                                .lineLimit(1)
                        }
                        .frame(width: labelWidth, alignment: .leading)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(.systemGray6))
                                .frame(width: trackWidth, height: 28)

                            let inicio = trackWidth * CGFloat(rango.semanaMin - semanaMin) / CGFloat(totalSemanas)
                            let ancho = max(44, trackWidth * CGFloat(rango.semanaMax - rango.semanaMin + 1) / CGFloat(totalSemanas))

                            Text("Sem \(rango.semanaMin)–\(rango.semanaMax) · \(rango.cantidad) act")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(width: min(ancho, trackWidth - inicio), height: 22, alignment: .center)
                                .background(EPTheme.color(hex: rango.colorHex), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .offset(x: inicio)
                        }
                        .frame(width: trackWidth, height: 28)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
}
