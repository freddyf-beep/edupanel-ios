import SwiftUI

struct CronogramaDiaView: View {
    let viewModel: CronogramaViewModel
    var onEdit: (ActividadCronograma) -> Void

    var body: some View {
        if let diaNombre = CronoDateHelpers.nombreDia(viewModel.currentDate) {
            contenido(diaNombre)
        } else {
            EPWebCard {
                EPEmptyState(
                    icon: "moon.zzz.fill",
                    title: "Fin de semana",
                    message: "Sábado y domingo no tienen clases programadas. Usa el scrubber para ir a un día laboral."
                )
            }
        }
    }

    private func contenido(_ diaNombre: String) -> some View {
        let semana = viewModel.semanaActual
        let actividades = viewModel.actividadesFiltradas
            .filter { $0.dia == diaNombre && $0.semana == semana }
            .sorted { $0.hora < $1.hora }
        let bloques = viewModel.horarioVisible
            .filter { $0.dia == diaNombre }
            .sorted { $0.horaInicio < $1.horaInicio }

        return VStack(alignment: .leading, spacing: 12) {
            EPWebCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(diaNombre) \(Calendar.current.component(.day, from: viewModel.currentDate)) · \(CronoDateHelpers.tituloMes(viewModel.currentDate))")
                        .font(.headline.weight(.black))
                    Text("Semana \(semana) · \(actividades.count) actividad\(actividades.count == 1 ? "" : "es") · \(bloques.count) bloque\(bloques.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !bloques.isEmpty {
                EPWebCard {
                    VStack(alignment: .leading, spacing: 10) {
                        EPSectionHeader(title: "Bloques del horario", subtitle: nil, icon: "clock.fill")
                        ForEach(bloques) { bloque in
                            HStack(spacing: 11) {
                                Text(bloque.horaInicio)
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 36)
                                    .background(EPTheme.color(hex: bloque.colorHex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bloque.resumen)
                                        .font(.footnote.weight(.black))
                                        .lineLimit(1)
                                    Text("\(bloque.horaInicio) – \(bloque.horaFin)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                EPStatusPill(text: "Horario", tint: .gray)
                            }
                            .padding(9)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }
                }
            }

            EPWebCard {
                VStack(alignment: .leading, spacing: 10) {
                    EPSectionHeader(title: "Actividades del cronograma", subtitle: nil, icon: "sparkles")

                    if actividades.isEmpty {
                        Text("Sin actividades planificadas para este día.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(actividades) { actividad in
                            Button {
                                onEdit(actividad)
                            } label: {
                                HStack(spacing: 11) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(EPTheme.color(hex: viewModel.colorUnidad(actividad.unidad)))
                                        .frame(width: 4, height: 40)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(actividad.nombre)
                                            .font(.footnote.weight(.black))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text("\(actividad.hora) · \(actividad.duracion) · \(viewModel.nombreUnidad(actividad.unidad))")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
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
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
