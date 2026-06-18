import SwiftUI
import Charts

struct NotaBin: Identifiable {
    let rango: String
    let cantidad: Int
    let aprobado: Bool

    var id: String { rango }

    /// Reparte las notas (1.0–7.0) en los 6 tramos clásicos del histograma.
    static func bins(notas: [Double]) -> [NotaBin] {
        let rangos = ["1.0\u{2013}1.9", "2.0\u{2013}2.9", "3.0\u{2013}3.9", "4.0\u{2013}4.9", "5.0\u{2013}5.9", "6.0\u{2013}7.0"]
        var conteos = Array(repeating: 0, count: 6)
        for nota in notas {
            let index = min(max(Int(nota) - 1, 0), 5)
            conteos[index] += 1
        }
        return rangos.enumerated().map { index, rango in
            NotaBin(rango: rango, cantidad: conteos[index], aprobado: index >= 3)
        }
    }
}

struct HistogramaNotasView: View {
    let bins: [NotaBin]

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Distribuci\u{00F3}n de notas", icon: "chart.bar.fill")

                Chart(bins) { bin in
                    BarMark(
                        x: .value("Rango", bin.rango),
                        y: .value("Estudiantes", bin.cantidad)
                    )
                    .foregroundStyle(bin.aprobado ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        if bin.cantidad > 0 {
                            Text("\(bin.cantidad)")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let rango = value.as(String.self) {
                                Text(rango).font(.system(size: 8.5, weight: .bold))
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
        }
    }
}
