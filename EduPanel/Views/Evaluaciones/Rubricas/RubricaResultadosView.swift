import SwiftUI

struct RubricaResultadosView: View {
    let rubricaId: String

    @State private var rubrica: RubricaTemplate?
    @State private var evaluacion: EvaluacionRubrica?
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
                } else if rubrica != nil {
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
                    Text(rubrica?.nombre.isEmpty == false ? rubrica!.nombre : "R\u{00FA}brica")
                        .font(.system(size: 17, weight: .black))
                    if evaluacion?.bloqueada == true {
                        EPStatusPill(text: "Finalizada", icon: "lock.fill", tint: .orange)
                    }
                }
                Text("\(rubrica?.curso ?? "") \u{00B7} \(Int(rubrica?.puntajeMaximo ?? 0)) pts m\u{00E1}x.")
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
            histogramaCard
            criteriosCard
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

    private var histogramaCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Distribuci\u{00F3}n de notas", icon: "chart.bar.fill")

                let bins = histograma
                let maximo = max(bins.map(\.cantidad).max() ?? 1, 1)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(bins, id: \.rango) { bin in
                        VStack(spacing: 5) {
                            Text(bin.cantidad > 0 ? "\(bin.cantidad)" : "")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(bin.aprobado ? Color.green.opacity(0.75) : Color.red.opacity(0.65))
                                .frame(height: max(CGFloat(bin.cantidad) / CGFloat(maximo) * 90, bin.cantidad > 0 ? 8 : 3))
                            Text(bin.rango)
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 130, alignment: .bottom)
            }
        }
    }

    private var criteriosCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Promedio por criterio",
                    subtitle: "Escala 1 a 4 \u{00B7} identifica los criterios m\u{00E1}s descendidos.",
                    icon: "slider.horizontal.3"
                )

                ForEach(promediosPorCriterio, id: \.id) { stat in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(stat.nombre)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(2)
                            Spacer()
                            Text(String(format: "%.1f", stat.promedio))
                                .font(.system(size: 12.5, weight: .black, design: .rounded))
                                .foregroundStyle(stat.promedio >= 3 ? .green : (stat.promedio >= 2 ? .orange : .red))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray5))
                                Capsule()
                                    .fill(stat.promedio >= 3 ? Color.green : (stat.promedio >= 2 ? Color.orange : Color.red))
                                    .frame(width: geo.size.width * min(stat.promedio / 4, 1))
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
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
                            Text("\(Int(rubrica?.calcularPuntaje(puntajes: est.puntajes) ?? 0)) pts \u{00B7} \(est.puntajes.count)/\(rubrica?.criteriosTotales.count ?? 0) criterios")
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

    private struct BinHistograma {
        let rango: String
        let cantidad: Int
        let aprobado: Bool
    }

    private struct CriterioStat {
        let id: String
        let nombre: String
        let promedio: Double
    }

    private var todos: [EstudianteRubrica] {
        evaluacion?.todosLosEstudiantes ?? []
    }

    private var ausentes: [EstudianteRubrica] {
        evaluacion?.estudiantesAusentes ?? []
    }

    private var activos: [EstudianteRubrica] {
        incluirAusentes
            ? todos
            : todos.filter { est in !ausentes.contains { $0.estudianteId == est.estudianteId } }
    }

    private var estudiantesConDatos: [EstudianteRubrica] {
        todos.filter { !$0.puntajes.isEmpty }
    }

    private var ordenados: [EstudianteRubrica] {
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

    private var histograma: [BinHistograma] {
        let rangos = ["1.0\u{2013}1.9", "2.0\u{2013}2.9", "3.0\u{2013}3.9", "4.0\u{2013}4.9", "5.0\u{2013}5.9", "6.0\u{2013}7.0"]
        var conteos = Array(repeating: 0, count: 6)
        for est in activos {
            guard let nota = est.nota else { continue }
            let index = min(max(Int(nota) - 1, 0), 5)
            conteos[index] += 1
        }
        return rangos.enumerated().map { index, rango in
            BinHistograma(rango: rango, cantidad: conteos[index], aprobado: index >= 3)
        }
    }

    private var promediosPorCriterio: [CriterioStat] {
        guard let rubrica else { return [] }
        return rubrica.partes.flatMap { parte in
            parte.criterios.map { criterio in
                let valores = activos.compactMap { $0.puntajes[criterio.id] }
                let promedio = valores.isEmpty ? 0 : valores.reduce(0, +) / Double(valores.count)
                return CriterioStat(
                    id: criterio.id,
                    nombre: criterio.nombre.isEmpty ? "Criterio \(criterio.orden)" : criterio.nombre,
                    promedio: promedio
                )
            }
        }
    }

    private func cargar() async {
        defer { isLoading = false }
        do {
            guard let rubricaCargada = try await repository.cargarRubrica(id: rubricaId) else {
                errorMessage = "R\u{00FA}brica no encontrada."
                return
            }
            rubrica = rubricaCargada

            if var evaluacionCargada = try await repository.cargarEvaluacionRubrica(rubricaId: rubricaId) {
                for grupoIndex in evaluacionCargada.grupos.indices {
                    for estIndex in evaluacionCargada.grupos[grupoIndex].estudiantes.indices {
                        evaluacionCargada.grupos[grupoIndex].estudiantes[estIndex].recalcular(con: rubricaCargada)
                    }
                }
                evaluacion = evaluacionCargada
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
