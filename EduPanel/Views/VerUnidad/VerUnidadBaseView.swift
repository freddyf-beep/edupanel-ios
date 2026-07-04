import SwiftUI

/// Tab "Unidad" replicando el layout de la web (ver-unidad v2):
/// Formato anual (checklist + %), Fechas y carga, Base pedagógica,
/// y resúmenes compactos de OA / Habilidades / Conocimientos / Actitudes
/// con "Ver detalles" para editar.
struct VerUnidadBaseView: View {
    var viewModel: VerUnidadViewModel
    @Binding var selectedTab: String

    @State private var newHabilidad = ""
    @State private var newConocimiento = ""
    @State private var newActitud = ""
    @State private var newResource = ""
    @State private var detalleOAs = false
    @State private var detalleHabilidades = false
    @State private var detalleConocimientos = false
    @State private var detalleActitudes = false
    @State private var expandirOAs = false

    private let unitColors: [Color] = [
        Color(hex6: 0xF59E0B), Color(hex6: 0x3B82F6), Color(hex6: 0xEF4444),
        Color(hex6: 0x22C55E), Color(hex6: 0x8B5CF6), Color(hex6: 0xF97316),
        Color(hex6: 0x06B6D4), Color(hex6: 0xD97706), Color(hex6: 0xEC4899),
        Color(hex6: 0x10B981)
    ]

    var body: some View {
        if let verUnidad = viewModel.verUnidad {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    formatoAnualCard(verUnidad)
                    fechasCargaCard(verUnidad)
                    basePedagogicaCard(verUnidad)
                    oasCard(verUnidad)
                    habilidadesCard(verUnidad)
                    conocimientosCard(verUnidad)
                    actitudesCard(verUnidad)
                    camposFaltantesCard(verUnidad)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Formato anual (checklist)

    private struct ChecklistItem: Identifiable {
        let label: String
        let done: Bool
        var id: String { label }
    }

    private func checklist(_ verUnidad: VerUnidadGuardada) -> [ChecklistItem] {
        let fechas = fechasUnidad()
        let consSel = verUnidad.conocimientos.filter(\.seleccionado)
        let habsSel = verUnidad.habilidades.filter(\.seleccionado)
        let actsSel = verUnidad.actitudes.filter(\.seleccionado)
        let oasSel = verUnidad.oas.filter(\.seleccionado)
        let indicadoresSel = oasSel.flatMap(\.indicadores).filter(\.seleccionado).count
        let estrategiaOk = (verUnidad.estrategiasEvaluacion ?? []).contains {
            !$0.nombre.trimmingCharacters(in: .whitespaces).isEmpty && !$0.instrumento.trimmingCharacters(in: .whitespaces).isEmpty
        }

        return [
            ChecklistItem(label: "Fechas", done: fechas != nil),
            ChecklistItem(label: "Propósito", done: !RichTextHTML.plainText(from: verUnidad.descripcion).isEmpty),
            ChecklistItem(label: "Conocimientos previos", done: !RichTextHTML.plainText(from: verUnidad.conocimientosPrevios ?? "").isEmpty),
            ChecklistItem(label: "Conocimientos a desarrollar", done: !consSel.isEmpty),
            ChecklistItem(label: "Habilidades", done: !habsSel.isEmpty),
            ChecklistItem(label: "Actitudes / OAT", done: !actsSel.isEmpty),
            ChecklistItem(label: "OA e indicadores", done: !oasSel.isEmpty && indicadoresSel > 0),
            ChecklistItem(label: "Estrategia evaluativa", done: estrategiaOk),
            ChecklistItem(label: "Recursos / materiales", done: !(verUnidad.recursosMaterialesUnidad ?? []).isEmpty)
        ]
    }

    private func formatoAnualCard(_ verUnidad: VerUnidadGuardada) -> some View {
        let items = checklist(verUnidad)
        let completados = items.filter(\.done).count
        let progreso = items.isEmpty ? 0 : Int((Double(completados) / Double(items.count) * 100).rounded())

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Formato anual")
                            .font(.system(size: 14, weight: .black))
                        Text("\(completados)/\(items.count) completo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: CGFloat(progreso) / 100)
                            .stroke(EPTheme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(progreso)%")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(EPTheme.primary)
                    }
                    .frame(width: 48, height: 48)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5))
                        Capsule()
                            .fill(EPTheme.primary)
                            .frame(width: geo.size.width * CGFloat(progreso) / 100)
                    }
                }
                .frame(height: 7)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(item.done ? .green : Color(.systemGray3))
                            Text(item.label)
                                .font(.system(size: 12, weight: item.done ? .bold : .medium))
                                .foregroundStyle(item.done ? .primary : .secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Fechas y carga

    private func fechasUnidad() -> (start: String, end: String)? {
        let fechas = (viewModel.cronograma?.clases ?? [])
            .map(\.fecha)
            .compactMap(Self.parseFecha)
            .sorted()
        guard let inicio = fechas.first, let fin = fechas.last else { return nil }
        return (Self.formatFecha(inicio), Self.formatFecha(fin))
    }

    private func fechasCargaCard(_ verUnidad: VerUnidadGuardada) -> some View {
        let fechas = fechasUnidad()
        let clasesCrono = viewModel.cronograma?.clases ?? []
        let conFecha = clasesCrono.filter { Self.parseFecha($0.fecha) != nil }.count
        let totalClases = max(viewModel.cronograma?.totalClases ?? verUnidad.clases, clasesCrono.map(\.numero).max() ?? 0)

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fechas y carga")
                    .font(.system(size: 14, weight: .black))

                HStack(spacing: 10) {
                    fechaBox(titulo: "Inicio", valor: fechas?.start ?? "Sin fecha")
                    fechaBox(titulo: "Término", valor: fechas?.end ?? "Sin fecha")
                }

                HStack(spacing: 10) {
                    stepperBox(titulo: "Clases", valor: verUnidad.clases) { nuevo in
                        viewModel.verUnidad?.clases = nuevo
                        if var crono = viewModel.cronograma {
                            let minimo = crono.clases.map(\.numero).max() ?? 0
                            crono.totalClases = max(nuevo, minimo)
                            viewModel.cronograma = crono
                        }
                    }
                    stepperBox(titulo: "Horas", valor: verUnidad.horas) { nuevo in
                        viewModel.verUnidad?.horas = nuevo
                    }
                }

                if conFecha > 0 {
                    Text("\(conFecha)/\(totalClases) clases tienen fecha en el cronograma.")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Label("El cronograma aún no tiene fechas. Ábrelo para que esta carga se arme sola.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Button {
                        withAnimation(EPTheme.spring) { selectedTab = "cronograma" }
                    } label: {
                        Label("Ir a Cronograma", systemImage: "arrow.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(EPTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(EPTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func fechaBox(titulo: String, valor: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(titulo, systemImage: "calendar")
                .font(.system(size: 10.5, weight: .black))
                .foregroundStyle(.secondary)
            Text(valor)
                .font(.system(size: 13, weight: .black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stepperBox(titulo: String, valor: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Stepper(value: Binding(get: { valor }, set: onChange), in: 1...60) {
                Text("\(valor)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sensoryFeedback(.increase, trigger: valor)
    }

    private static func parseFecha(_ valor: String) -> Date? {
        let limpio = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.date(from: limpio)
    }

    private static func formatFecha(_ fecha: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: fecha)
    }

    // MARK: - Base pedagógica

    private func basePedagogicaCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Base pedagógica de la unidad")
                        .font(.system(size: 14, weight: .black))
                    Text("Esta información orienta la planificación y alimenta el formato anual.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("PROPÓSITO")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Group {
                        if RichTextHTML.plainText(from: verUnidad.descripcion).isEmpty {
                            Text("Sin propósito definido.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            RichTextRenderer(html: verUnidad.descripcion)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                RichTextEditor(
                    title: "Contexto docente",
                    placeholder: "Foco real del curso, necesidades, ritmos, intereses...",
                    html: Binding(
                        get: { viewModel.verUnidad?.contextoDocente ?? verUnidad.contextoDocente },
                        set: { viewModel.verUnidad?.contextoDocente = $0 }
                    ),
                    minHeight: 84
                )

                RichTextEditor(
                    title: "Objetivo docente",
                    placeholder: "Meta pedagógica propia para esta unidad...",
                    html: Binding(
                        get: { viewModel.verUnidad?.objetivoDocente ?? verUnidad.objetivoDocente },
                        set: { viewModel.verUnidad?.objetivoDocente = $0 }
                    ),
                    minHeight: 84
                )
            }
        }
    }

    // MARK: - Objetivos de Aprendizaje (resumen web + detalle editable)

    private func oasCard(_ verUnidad: VerUnidadGuardada) -> some View {
        let seleccionados = verUnidad.oas.filter(\.seleccionado)
        let visibles = expandirOAs ? seleccionados : Array(seleccionados.prefix(3))

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                resumenHeader(titulo: "Objetivos de Aprendizaje", icono: "target", tint: EPTheme.primary, contador: seleccionados.count, detalle: $detalleOAs)

                if detalleOAs {
                    ForEach(Array(verUnidad.oas.enumerated()), id: \.element.id) { oIdx, oa in
                        oaDetalleRow(oa: oa, oIdx: oIdx)
                    }
                } else {
                    if seleccionados.isEmpty {
                        Text("Sin OA seleccionados.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(visibles.enumerated()), id: \.element.id) { index, oa in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(unitColors[index % unitColors.count])
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                Text("\(oa.tipo == "oat" ? "OAT" : (oa.numero != nil ? "OA \(oa.numero!)" : "OA")): ")
                                    .font(.system(size: 12, weight: .black))
                                + Text(oa.descripcion)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }

                        if !expandirOAs && seleccionados.count > 3 {
                            Button {
                                withAnimation(EPTheme.spring) { expandirOAs = true }
                            } label: {
                                Text("+ \(seleccionados.count - 3) más...")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(EPTheme.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func oaDetalleRow(oa: OAEditado, oIdx: Int) -> some View {
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

            if oa.seleccionado && !oa.indicadores.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
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
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Habilidades / Conocimientos / Actitudes

    private func habilidadesCard(_ verUnidad: VerUnidadGuardada) -> some View {
        let seleccionadas = verUnidad.habilidades.filter(\.seleccionado)

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                resumenHeader(titulo: "Habilidades", icono: "square.stack.3d.up.fill", tint: .blue, contador: seleccionadas.count, detalle: $detalleHabilidades)

                if detalleHabilidades {
                    curriculumCategorySection(
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
                } else if seleccionadas.isEmpty {
                    Text("Sin habilidades seleccionadas.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ReplicaFlowLayout(spacing: 7) {
                        ForEach(Array(seleccionadas.prefix(6).enumerated()), id: \.element.id) { index, hab in
                            Text(Self.compact(hab.texto, max: 48))
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(unitColors[index % unitColors.count], in: Capsule())
                        }
                    }
                    if seleccionadas.count > 6 {
                        Text("+ \(seleccionadas.count - 6) más en Ver detalles")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(EPTheme.primary)
                    }
                }
            }
        }
    }

    private func conocimientosCard(_ verUnidad: VerUnidadGuardada) -> some View {
        bulletsCard(
            titulo: "Conocimientos",
            icono: "doc.text.fill",
            tint: Color(hex6: 0xF59E0B),
            items: verUnidad.conocimientos,
            detalle: $detalleConocimientos,
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
    }

    private func actitudesCard(_ verUnidad: VerUnidadGuardada) -> some View {
        bulletsCard(
            titulo: "Actitudes",
            icono: "heart.fill",
            tint: Color(hex6: 0xEF4444),
            items: verUnidad.actitudes,
            detalle: $detalleActitudes,
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
    }

    private func bulletsCard(
        titulo: String,
        icono: String,
        tint: Color,
        items: [ElementoCurricular],
        detalle: Binding<Bool>,
        newItemText: Binding<String>,
        onAdd: @escaping () -> Void,
        onToggle: @escaping (Int) -> Void
    ) -> some View {
        let seleccionados = items.filter(\.seleccionado)

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                resumenHeader(titulo: titulo, icono: icono, tint: tint, contador: seleccionados.count, detalle: detalle)

                if detalle.wrappedValue {
                    curriculumCategorySection(
                        items: items,
                        newItemText: newItemText,
                        onAdd: onAdd,
                        onToggle: onToggle
                    )
                } else if seleccionados.isEmpty {
                    Text("Sin \(titulo.lowercased()) seleccionados.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(seleccionados.prefix(4)) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(tint)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(item.texto)
                                    .font(.system(size: 12, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if seleccionados.count > 4 {
                            Text("+ \(seleccionados.count - 4) más en Ver detalles")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(EPTheme.primary)
                        }
                    }
                }
            }
        }
    }

    private func resumenHeader(titulo: String, icono: String, tint: Color, contador: Int, detalle: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icono)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(titulo)
                .font(.system(size: 14, weight: .black))
            Text("\(contador)")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(.systemGray6), in: Capsule())

            Spacer(minLength: 8)

            Button {
                withAnimation(EPTheme.spring) { detalle.wrappedValue.toggle() }
            } label: {
                Label(detalle.wrappedValue ? "Cerrar" : "Ver detalles", systemImage: detalle.wrappedValue ? "xmark" : "eye")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(EPTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().stroke(EPTheme.primary.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Campos faltantes

    private func camposFaltantesCard(_ verUnidad: VerUnidadGuardada) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(EPTheme.primary)
                    Text("Campos faltantes")
                        .font(.system(size: 14, weight: .black))
                }

                RichTextEditor(
                    title: "Conocimientos previos",
                    placeholder: "Lo que el curso debe manejar antes de iniciar...",
                    html: Binding(
                        get: { viewModel.verUnidad?.conocimientosPrevios ?? "" },
                        set: { viewModel.verUnidad?.conocimientosPrevios = $0 }
                    ),
                    minHeight: 76
                )

                VStack(alignment: .leading, spacing: 9) {
                    Text("RECURSOS / MATERIALES")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Ej: parlante, cuaderno, guía...", text: $newResource)
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

                    ReplicaFlowLayout(spacing: 7) {
                        ForEach(verUnidad.recursosMaterialesUnidad ?? [], id: \.self) { recurso in
                            Text(recurso)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.blue.opacity(0.11), in: Capsule())
                                .onLongPressGesture {
                                    viewModel.verUnidad?.recursosMaterialesUnidad?.removeAll { $0 == recurso }
                                }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("ESTRATEGIAS DE EVALUACIÓN")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
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
                            .background(Color(.systemGray6).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    } else {
                        Text("Sin estrategias registradas todavía.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func compact(_ texto: String, max: Int) -> String {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limpio.count > max else { return limpio }
        return String(limpio.prefix(max)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func curriculumCategorySection(
        items: [ElementoCurricular],
        newItemText: Binding<String>,
        onAdd: @escaping () -> Void,
        onToggle: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
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
