import SwiftUI

struct VerUnidadBaseView: View {
    var viewModel: VerUnidadViewModel

    @State private var newHabilidad = ""
    @State private var newConocimiento = ""
    @State private var newActitud = ""
    @State private var newResource = ""

    var body: some View {
        if let verUnidad = viewModel.verUnidad {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    planUnidadCard(verUnidad)
                    curriculoCard(verUnidad)
                    rutaTrabajoCard(verUnidad)
                    actividadesUnidadCard(verUnidad)
                    estadoUnidadCard(verUnidad)
                    recursosEvaluacionCard(verUnidad)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func planUnidadCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Plan de unidad", subtitle: "Propósito, contexto y meta docente compatibles con HTML web.", icon: "doc.text.fill")

                RichTextEditor(
                    title: "Propósito de la unidad",
                    placeholder: "Describe qué aprenderán y producirán los estudiantes...",
                    html: Binding(
                        get: { viewModel.verUnidad?.descripcion ?? verUnidad.descripcion },
                        set: { viewModel.verUnidad?.descripcion = $0 }
                    ),
                    minHeight: 112
                )

                RichTextEditor(
                    title: "Contexto docente",
                    placeholder: "Particularidades del curso, apoyos necesarios, clima, antecedentes...",
                    html: Binding(
                        get: { viewModel.verUnidad?.contextoDocente ?? verUnidad.contextoDocente },
                        set: { viewModel.verUnidad?.contextoDocente = $0 }
                    ),
                    minHeight: 96
                )

                RichTextEditor(
                    title: "Meta docente",
                    placeholder: "Define qué evidencia esperas lograr al cierre de la unidad...",
                    html: Binding(
                        get: { viewModel.verUnidad?.objetivoDocente ?? verUnidad.objetivoDocente },
                        set: { viewModel.verUnidad?.objetivoDocente = $0 }
                    ),
                    minHeight: 96
                )
            }
        }
    }

    private func curriculoCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Currículo seleccionado", subtitle: "\(verUnidad.oas.filter(\.seleccionado).count) objetivos priorizados.", icon: "checklist.checked")

                if verUnidad.oas.isEmpty {
                    Text("No hay objetivos asociados a esta unidad.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(verUnidad.oas.enumerated()), id: \.element.id) { oIdx, oa in
                        oaCard(oa: oa, oIdx: oIdx)
                    }
                }
            }
        }
    }

    private func oaCard(oa: OAEditado, oIdx: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(EPTheme.spring) {
                    viewModel.verUnidad?.oas[oIdx].seleccionado.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: oa.seleccionado ? "checkmark.square.fill" : "square")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(oa.seleccionado ? EPTheme.primary : .secondary)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(.primary)
                            if oa.esPropio == true {
                                EPStatusPill(text: "Propio", icon: "pencil", tint: .purple)
                            }
                        }
                        Text(oa.descripcion)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .buttonStyle(.plain)

            if oa.seleccionado {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Indicadores de evaluación")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    ForEach(Array(oa.indicadores.enumerated()), id: \.element.id) { iIdx, indicador in
                        Button {
                            viewModel.verUnidad?.oas[oIdx].indicadores[iIdx].seleccionado.toggle()
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: indicador.seleccionado ? "checkmark.circle.fill" : "circle")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(indicador.seleccionado ? EPTheme.primary : .secondary)
                                Text(indicador.texto)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(indicador.seleccionado ? .primary : .secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(13)
        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(oa.seleccionado ? EPTheme.primary.opacity(0.25) : Color.clear, lineWidth: 1.5)
        )
    }

    private func rutaTrabajoCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Ruta de trabajo", subtitle: "Habilidades, conocimientos, actitudes y aprendizajes previos.", icon: "point.topleft.down.curvedto.point.bottomright.up")

                curriculumCategorySection(
                    title: "Habilidades",
                    items: verUnidad.habilidades,
                    newItemText: $newHabilidad,
                    onAdd: {
                        addCurriculumItem(text: newHabilidad, prefix: "hab") { item in
                            viewModel.verUnidad?.habilidades.append(item)
                            newHabilidad = ""
                        }
                    },
                    onToggle: { idx in
                        viewModel.verUnidad?.habilidades[idx].seleccionado.toggle()
                    }
                )

                curriculumCategorySection(
                    title: "Conocimientos",
                    items: verUnidad.conocimientos,
                    newItemText: $newConocimiento,
                    onAdd: {
                        addCurriculumItem(text: newConocimiento, prefix: "con") { item in
                            viewModel.verUnidad?.conocimientos.append(item)
                            newConocimiento = ""
                        }
                    },
                    onToggle: { idx in
                        viewModel.verUnidad?.conocimientos[idx].seleccionado.toggle()
                    }
                )

                curriculumCategorySection(
                    title: "Actitudes",
                    items: verUnidad.actitudes,
                    newItemText: $newActitud,
                    onAdd: {
                        addCurriculumItem(text: newActitud, prefix: "act") { item in
                            viewModel.verUnidad?.actitudes.append(item)
                            newActitud = ""
                        }
                    },
                    onToggle: { idx in
                        viewModel.verUnidad?.actitudes[idx].seleccionado.toggle()
                    }
                )

                RichTextEditor(
                    title: "Conocimientos previos",
                    placeholder: "Registra antecedentes o aprendizajes previos del curso...",
                    html: Binding(
                        get: { viewModel.verUnidad?.conocimientosPrevios ?? "" },
                        set: { viewModel.verUnidad?.conocimientosPrevios = $0 }
                    ),
                    minHeight: 86
                )
            }
        }
    }

    private func estadoUnidadCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Estado de unidad", subtitle: "Resumen de carga y selección curricular.", icon: "gauge.with.dots.needle.67percent")

                let selectedOAs = verUnidad.oas.filter(\.seleccionado).count
                let selectedIndicators = verUnidad.oas.flatMap(\.indicadores).filter(\.seleccionado).count

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    EPKPIBox(title: "OA", value: "\(selectedOAs)", subtitle: "seleccionados", icon: "checkmark.square.fill", tint: EPTheme.primary)
                    EPKPIBox(title: "Indicadores", value: "\(selectedIndicators)", subtitle: "activos", icon: "list.bullet.clipboard", tint: .green)
                }

                HStack(spacing: 10) {
                    stepperCard(titulo: "Horas de la unidad", valor: verUnidad.horas) { nuevo in
                        viewModel.verUnidad?.horas = nuevo
                    }
                    stepperCard(titulo: "Clases estimadas", valor: verUnidad.clases) { nuevo in
                        viewModel.verUnidad?.clases = nuevo
                        if var crono = viewModel.cronograma {
                            let minimo = crono.clases.map(\.numero).max() ?? 0
                            crono.totalClases = max(nuevo, minimo)
                            viewModel.cronograma = crono
                        }
                    }
                }
            }
        }
    }

    private func stepperCard(titulo: String, valor: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Stepper(value: Binding(get: { valor }, set: onChange), in: 1...60) {
                Text("\(valor)")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.increase, trigger: valor)
    }

    private func actividadesUnidadCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Actividades de la unidad", subtitle: "Datos guardados en la web para la ruta de trabajo.", icon: "figure.walk.motion")

                let actividades = verUnidad.actividades ?? []
                if actividades.isEmpty {
                    Text("Sin actividades de unidad registradas.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(actividades) { actividad in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 7) {
                                Text(actividad.titulo)
                                    .font(.footnote.weight(.black))
                                Spacer()
                                if let estado = actividad.estado, !estado.isEmpty {
                                    EPStatusPill(text: estado, icon: "circle.fill", tint: estado == "completada" ? .green : .orange)
                                }
                                if let fecha = actividad.fecha, !fecha.isEmpty {
                                    EPStatusPill(text: fecha, icon: "calendar", tint: .blue)
                                }
                                if let momento = actividad.momento, !momento.isEmpty {
                                    EPStatusPill(text: momento, icon: "clock", tint: .blue)
                                }
                                if let duracion = actividad.duracion {
                                    EPStatusPill(text: "\(duracion) min", icon: "timer", tint: .purple)
                                } else if let duracionTexto = actividad.duracionTexto, !duracionTexto.isEmpty {
                                    EPStatusPill(text: duracionTexto, icon: "timer", tint: .purple)
                                }
                            }
                            if let descripcion = actividad.descripcion, !descripcion.isEmpty {
                                RichTextRenderer(html: descripcion)
                            }
                            if let recursos = actividad.recursos, !recursos.isEmpty {
                                ReplicaFlowLayout(spacing: 6) {
                                    ForEach(recursos, id: \.self) { recurso in
                                        Text(recurso)
                                            .font(.caption2.weight(.black))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(.blue.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private func recursosEvaluacionCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 16) {
                EPSectionHeader(title: "Recursos y estrategias", subtitle: "Estructura nativa equivalente al sidebar web.", icon: "tray.full.fill")

                VStack(alignment: .leading, spacing: 9) {
                    Text("Recursos materiales")
                        .font(.caption.weight(.black))
                    ReplicaFlowLayout(spacing: 7) {
                        ForEach(verUnidad.recursosMaterialesUnidad ?? [], id: \.self) { recurso in
                            Text(recurso)
                                .font(.caption.weight(.black))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.blue.opacity(0.11), in: Capsule())
                                .onLongPressGesture {
                                    viewModel.verUnidad?.recursosMaterialesUnidad?.removeAll { $0 == recurso }
                                }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Agregar recurso...", text: $newResource)
                            .font(.caption.weight(.semibold))
                            .textFieldStyle(.roundedBorder)
                        Button {
                            let value = newResource.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty else { return }
                            if viewModel.verUnidad?.recursosMaterialesUnidad == nil {
                                viewModel.verUnidad?.recursosMaterialesUnidad = []
                            }
                            viewModel.verUnidad?.recursosMaterialesUnidad?.append(value)
                            newResource = ""
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Estrategias de evaluación")
                        .font(.caption.weight(.black))
                    if let estrategias = verUnidad.estrategiasEvaluacion, !estrategias.isEmpty {
                        ForEach(estrategias) { estrategia in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(EPTheme.primary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(estrategia.nombre)
                                        .font(.footnote.weight(.black))
                                    Text("\(estrategia.instrumento)\(estrategia.ponderacion != nil ? " · \(Int(estrategia.ponderacion!))%" : "")")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    } else {
                        Text("Sin estrategias registradas todavía.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let archivos = verUnidad.recursosMaterialesUnidadArchivos, !archivos.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Archivos adjuntos")
                            .font(.caption.weight(.black))
                        ForEach(archivos) { archivo in
                            Label(archivo.nombre, systemImage: "paperclip")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func curriculumCategorySection(
        title: String,
        items: [ElementoCurricular],
        newItemText: Binding<String>,
        onAdd: @escaping () -> Void,
        onToggle: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.black))

            ReplicaFlowLayout(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        onToggle(idx)
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.texto)
                                .font(.caption.weight(.black))
                                .lineLimit(2)
                            if item.seleccionado {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .black))
                            }
                        }
                        .foregroundStyle(item.seleccionado ? .white : EPTheme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(item.seleccionado ? EPTheme.primary : Color(.systemGray5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Agregar propio...", text: newItemText)
                    .font(.caption.weight(.semibold))
                    .textFieldStyle(.roundedBorder)

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newItemText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(13)
        .background(Color(.systemGray6).opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func addCurriculumItem(text: String, prefix: String, append: (ElementoCurricular) -> Void) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        append(ElementoCurricular(
            id: "\(prefix)_custom_\(Int(Date().timeIntervalSince1970))",
            texto: value,
            seleccionado: true,
            esPropio: true
        ))
    }
}
