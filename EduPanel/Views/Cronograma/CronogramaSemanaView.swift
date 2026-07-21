import SwiftUI

struct CronogramaSemanaView: View {
    let viewModel: CronogramaViewModel
    var onEdit: (ActividadCronograma) -> Void
    var onCreate: (String, String) -> Void

    @State private var selectedDayName: String = CronoDateHelpers.nombreDia(Date()) ?? "Lunes"

    var body: some View {
        VStack(spacing: 12) {
            daySelectorHeader
            selectedDayColumn(selectedDayName)
        }
    }

    // MARK: - Selector de Día

    private var daySelectorHeader: some View {
        HStack(spacing: 6) {
            ForEach(CronoDateHelpers.diasSemana, id: \.self) { dia in
                let fecha = CronoDateHelpers.fechaReal(lunes: viewModel.lunesActual, dia: dia)
                let esHoy = Calendar.current.isDateInToday(fecha)
                let numDia = Calendar.current.component(.day, from: fecha)
                let isSelected = selectedDayName == dia

                Button {
                    withAnimation(EPTheme.spring) {
                        selectedDayName = dia
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(String(dia.prefix(3)).uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(isSelected ? .white : (esHoy ? EPTheme.primary : .secondary))
                        
                        Text("\(numDia)")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(isSelected ? .white : (esHoy ? EPTheme.primary : .primary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isSelected ? EPTheme.primary : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .shadow(color: isSelected ? EPTheme.primary.opacity(0.3) : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Columna del Día Seleccionado

    private func selectedDayColumn(_ dia: String) -> some View {
        let fecha = CronoDateHelpers.fechaReal(lunes: viewModel.lunesActual, dia: dia)
        let actividades = viewModel.actividadesFiltradas
            .filter { $0.semana == viewModel.semanaActual && $0.dia == dia }
            .sorted { $0.hora < $1.hora }
        let bloques = viewModel.horarioVisible
            .filter { $0.dia == dia }
            .sorted { $0.horaInicio < $1.horaInicio }

        return VStack(alignment: .leading, spacing: 12) {
            // Encabezado del día
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dia) \(Calendar.current.component(.day, from: fecha)) · \(CronoDateHelpers.tituloMes(fecha))")
                        .font(.headline.weight(.black))
                    Text("\(actividades.count) actividad\(actividades.count == 1 ? "" : "es") · \(bloques.count) bloque\(bloques.count == 1 ? "" : "s") de clase")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onCreate(dia, "08:30")
                } label: {
                    Label("Nueva actividad", systemImage: "plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(EPTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Contenido del día
            if bloques.isEmpty && actividades.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "sun.max.fill",
                        title: "Sin actividades en \(dia)",
                        message: "Toca \"Nueva actividad\" para programar una clase o evaluación en este día."
                    )
                }
            } else {
                if !bloques.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BLOQUES DE HORARIO")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            ForEach(bloques) { bloque in
                                HStack(spacing: 12) {
                                    Text(bloque.horaInicio)
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(.white)
                                        .frame(width: 54, height: 38)
                                        .background(Color(profileHex: bloque.colorHex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bloque.resumen)
                                            .font(.footnote.weight(.black))
                                            .lineLimit(1)
                                        Text("\(bloque.horaInicio) – \(bloque.horaFin)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(10)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }

                if !actividades.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVIDADES DEL CRONOGRAMA")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            ForEach(actividades) { actividad in
                                tarjetaActividad(actividad)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tarjeta de Actividad

    private func tarjetaActividad(_ actividad: ActividadCronograma) -> some View {
        Button {
            onEdit(actividad)
        } label: {
            HStack(spacing: 12) {
                Capsule()
                    .fill(EPTheme.color(hex: viewModel.colorUnidad(actividad.unidad)))
                    .frame(width: 4, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(actividad.nombre)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let curso = actividad.cursoOrigen, !curso.isEmpty {
                            Text(curso)
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(EPTheme.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EPTheme.primary.opacity(0.1), in: Capsule())
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("\(actividad.hora) · \(actividad.duracion)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        if !actividad.unidad.isEmpty {
                            Text("· \(viewModel.nombreUnidad(actividad.unidad))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "pencil")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.systemGray5), in: Circle())
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
