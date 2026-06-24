import SwiftUI

struct VerUnidadClasesView: View {
    var viewModel: VerUnidadViewModel

    @State private var selectedClassNum = 1
    @State private var showingLiveMode = false
    @State private var newMaterial = ""
    @State private var newTic = ""

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        VStack(spacing: 0) {
            classSelectorRail

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    classHeaderCard
                    objectivesCard
                    editorFields
                    curriculumTransversalCard
                    resourcesSection
                    if !displayMode.isSimple {
                        externalPedagogyCard
                        placeholdersCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            normalizeSelectedClass()
        }
        .onChange(of: classNumbers) { _, _ in
            normalizeSelectedClass()
        }
        .sheet(isPresented: $showingLiveMode) {
            if let act = viewModel.clasesActividades[selectedClassNum] {
                LiveClassModeView(
                    actividad: act,
                    students: getStudents(),
                    dashboardRepository: viewModel.planificacionRepository
                )
            }
        }
    }

    private var classSelectorRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(classNumbers, id: \.self) { cNum in
                    let isSelected = selectedClassNum == cNum
                    let hasData = isClassPlanificable(classNum: cNum)
                    let cronoClass = cronogramaClass(for: cNum)
                    Button {
                        withAnimation(EPTheme.spring) {
                            selectClass(cNum)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text("Clase \(cNum)")
                                    .font(.caption.weight(.black))
                                if hasData {
                                    Circle()
                                        .fill(isSelected ? .white : .green)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            if let cronoClass, !cronoClass.fecha.isEmpty {
                                Text(cronoClass.fecha)
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                            }
                            if let cronoClass, !cronoClass.oaIds.isEmpty {
                                Text("\(cronoClass.oaIds.count) OA")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(isSelected ? .white.opacity(0.82) : EPTheme.primary)
                            }
                        }
                        .foregroundStyle(isSelected ? .white : EPTheme.ink)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            isSelected ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(Color(.systemGray6)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .shadow(color: isSelected ? EPTheme.primary.opacity(0.3) : .clear, radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.12))
                .frame(height: 1)
        }
        .sensoryFeedback(.selection, trigger: selectedClassNum)
    }

    private var classHeaderCard: some View {
        let act = activeActivity
        let cronoClass = cronogramaClass(for: selectedClassNum)
        let dateLabel = act.fecha.isEmpty ? "Fecha no programada" : "Programada: \(act.fecha)"

        return EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("DETALLE DE LA JORNADA")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(EPTheme.primary)
                        Text("Clase \(selectedClassNum): Plan de aula")
                            .font(.headline.weight(.black))
                        Text(dateLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker("Estado", selection: activeActivityBinding.estado) {
                            Text("No planificada").tag("no_planificada")
                            Text("Planificada").tag("planificada")
                            Text("Realizada").tag("realizada")
                        }
                        .pickerStyle(.menu)
                        .font(.caption.weight(.black))
                    }

                    Spacer(minLength: 8)

                    Button {
                        ensureActivityExists(for: selectedClassNum)
                        showingLiveMode = true
                    } label: {
                        Label("Clase en vivo", systemImage: "play.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(EPTheme.heroGradient, in: Capsule())
                            .shadow(color: EPTheme.primary.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .medium), trigger: showingLiveMode)
                }

                HStack(spacing: 7) {
                    EPStatusPill(text: cronoClass?.fecha.isEmpty == false ? cronoClass?.fecha ?? "Sin fecha" : "Sin fecha", icon: "calendar", tint: .blue)
                    EPStatusPill(text: "\(linkedOAs.count) OA", icon: "tag.fill", tint: linkedOAs.isEmpty ? .orange : .green)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var objectivesCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Objetivos vinculados", subtitle: "Vienen de la matriz del cronograma.", icon: "tag.fill")

                let linked = linkedOAs
                if linked.isEmpty {
                    Label("Esta clase todavía no tiene OA asignados.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(linked, id: \.id) { oa in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                .font(.subheadline.weight(.black))
                            Text(oa.descripcion)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            let selectedIndicators = indicatorsForClass(oa)
                            if !selectedIndicators.isEmpty {
                                Text("Indicadores seleccionados")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                ReplicaFlowLayout(spacing: 6) {
                                    ForEach(selectedIndicators) { indicador in
                                        Text(indicador.texto)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(EPTheme.primary)
                                            .lineLimit(2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(EPTheme.primary.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }
                        .padding(11)
                        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
        }
    }

    private var curriculumTransversalCard: some View {
        EPCollapsibleSection(title: "Currículo transversal", subtitle: "Habilidades y actitudes de la clase.", icon: "layers.fill") {
            VStack(alignment: .leading, spacing: 16) {
                curriculumToggleSection(
                    title: "Habilidades",
                    icon: "target",
                    available: selectedUnitSkills,
                    selected: activeActivity.habilidades,
                    tint: EPTheme.primary
                ) { value in
                    toggleString(value, keyPath: \.habilidades)
                }

                curriculumToggleSection(
                    title: "Actitudes",
                    icon: "heart.fill",
                    available: selectedUnitAttitudes,
                    selected: activeActivity.actitudes,
                    tint: .orange
                ) { value in
                    toggleString(value, keyPath: \.actitudes)
                }
            }
        }
    }

    private var editorFields: some View {
        let binding = activeActivityBinding

        return EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Planificación diaria", subtitle: "Campos rich text compatibles con Quill/HTML simple.", icon: "square.and.pencil")

                RichTextEditor(
                    title: "Objetivo de aprendizaje de la clase",
                    placeholder: "Crear un primer boceto de paisaje sonoro...",
                    html: binding.objetivo,
                    minHeight: 84
                )

                RichTextEditor(
                    title: "Contexto de la clase",
                    placeholder: "Notas pedagógicas, agrupamientos, apoyos o alertas...",
                    html: binding.contextoProfesor.toNonOptional(),
                    minHeight: 76
                )

                Divider()

                RichTextEditor(
                    title: "Momento 1: Inicio",
                    placeholder: "Activación de conocimientos, pregunta inicial, motivación...",
                    html: binding.inicio,
                    minHeight: 92
                )

                RichTextEditor(
                    title: "Momento 2: Desarrollo",
                    placeholder: "Actividad principal, pasos, agrupamientos y mediación docente...",
                    html: binding.desarrollo,
                    minHeight: 118
                )

                RichTextEditor(
                    title: "Momento 3: Cierre",
                    placeholder: "Metacognición, evidencia final o ticket de salida...",
                    html: binding.cierre,
                    minHeight: 92
                )

                Divider()

                RichTextEditor(
                    title: "Adecuación curricular",
                    placeholder: "Estrategias PIE / DUA, apoyos, multinivel o ajustes...",
                    html: binding.adecuacion,
                    minHeight: 92
                )
            }
        }
    }

    private var resourcesSection: some View {
        let binding = activeActivityBinding

        return EPCollapsibleSection(title: "Recursos y materiales", subtitle: "Materiales, TIC y archivos.", icon: "tray.full.fill") {
            VStack(alignment: .leading, spacing: 16) {
                chipEditor(
                    title: "Materiales físicos",
                    placeholder: "Añadir material...",
                    text: $newMaterial,
                    items: binding.wrappedValue.materiales,
                    tint: .blue,
                    onAdd: { value in
                        viewModel.clasesActividades[selectedClassNum]?.materiales.append(value)
                    },
                    onRemove: { value in
                        viewModel.clasesActividades[selectedClassNum]?.materiales.removeAll { $0 == value }
                    }
                )

                chipEditor(
                    title: "Herramientas TIC",
                    placeholder: "Añadir TIC...",
                    text: $newTic,
                    items: binding.wrappedValue.tics,
                    tint: .purple,
                    onAdd: { value in
                        viewModel.clasesActividades[selectedClassNum]?.tics.append(value)
                    },
                    onRemove: { value in
                        viewModel.clasesActividades[selectedClassNum]?.tics.removeAll { $0 == value }
                    }
                )

                if let archivos = binding.wrappedValue.archivos, !archivos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archivos")
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

    private var externalPedagogyCard: some View {
        let act = activeActivity

        return EPCollapsibleSection(title: "Datos pedagógicos avanzados", subtitle: "Multinivel, Bloom y evaluación.", icon: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 14) {
                if !hasExternalPedagogyData(act) {
                    Text("Sin datos avanzados registrados para esta clase.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    if let objetivoMultinivel = act.objetivoMultinivel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Objetivo multinivel")
                                .font(.caption.weight(.black))
                            externalTextRow("Básico", objetivoMultinivel.basico, tint: .green)
                            externalTextRow("Intermedio", objetivoMultinivel.intermedio, tint: .blue)
                            externalTextRow("Avanzado", objetivoMultinivel.avanzado, tint: .purple)
                            externalTextRow("Recomendado", objetivoMultinivel.recomendado, tint: EPTheme.primary)
                        }
                    }

                    if let analisisBloom = act.analisisBloom, !analisisBloom.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Análisis Bloom")
                                .font(.caption.weight(.black))
                            ForEach(analisisBloom) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        EPStatusPill(text: item.oaId ?? "OA", icon: "tag.fill", tint: .blue)
                                        EPStatusPill(text: item.categoria ?? "Categoría", icon: "chart.bar.fill", tint: EPTheme.primary)
                                        EPStatusPill(text: item.nivel ?? "Nivel", icon: "gauge.with.dots.needle.67percent", tint: .purple)
                                    }
                                    if let justificacion = item.justificacion, !justificacion.isEmpty {
                                        Text(justificacion)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    if let verbos = item.verbosSugeridos, !verbos.isEmpty {
                                        ReplicaFlowLayout(spacing: 6) {
                                            ForEach(verbos, id: \.self) { verbo in
                                                Text(verbo)
                                                    .font(.caption2.weight(.black))
                                                    .foregroundStyle(.green)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 5)
                                                    .background(.green.opacity(0.1), in: Capsule())
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    if let indicadores = act.indicadoresEvaluacion, !indicadores.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Indicadores de evaluación")
                                .font(.caption.weight(.black))
                            ForEach(indicadores) { indicador in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: indicador.seleccionado == false ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(indicador.seleccionado == false ? .secondary : EPTheme.primary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(indicador.texto)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 6) {
                                            if let dimension = indicador.dimension, !dimension.isEmpty {
                                                EPStatusPill(text: dimension, tint: .blue)
                                            }
                                            if let nivelBloom = indicador.nivelBloom, !nivelBloom.isEmpty {
                                                EPStatusPill(text: nivelBloom, tint: .purple)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    if let actividadEvaluacion = act.actividadEvaluacion,
                       [actividadEvaluacion.tipo, actividadEvaluacion.descripcion, actividadEvaluacion.instrumento].contains(where: { ($0 ?? "").isEmpty == false }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Actividad de evaluación")
                                .font(.caption.weight(.black))
                            externalTextRow("Tipo", actividadEvaluacion.tipo, tint: .orange)
                            externalTextRow("Instrumento", actividadEvaluacion.instrumento, tint: .purple)
                            if let descripcion = actividadEvaluacion.descripcion, !descripcion.isEmpty {
                                RichTextRenderer(html: descripcion)
                                    .padding(10)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            if let criterios = actividadEvaluacion.criterios, !criterios.isEmpty {
                                labeledChipList("Criterios", criterios, tint: .green)
                            }
                            if let alineacion = actividadEvaluacion.alineacionMBE, !alineacion.isEmpty {
                                labeledChipList("Alineación MBE", alineacion, tint: .blue)
                            }
                        }
                    }

                    if let desarrolloFormal = act.desarrolloFormal,
                       [desarrolloFormal.inicio, desarrolloFormal.desarrollo, desarrolloFormal.cierre].contains(where: { ($0 ?? "").isEmpty == false }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Desarrollo formal")
                                .font(.caption.weight(.black))
                            externalTextRow("Inicio", desarrolloFormal.inicio, tint: .blue)
                            externalTextRow("Desarrollo", desarrolloFormal.desarrollo, tint: .green)
                            externalTextRow("Cierre", desarrolloFormal.cierre, tint: .purple)
                        }
                    }
                }
            }
        }
    }

    private var placeholdersCard: some View {
        EPCollapsibleSection(title: "Apoyos IA y Drive", subtitle: "Acciones rápidas.", icon: "sparkles") {
            HStack(spacing: 8) {
                EPPlaceholderActionButton(title: "Sugerir mejoras", icon: "wand.and.stars", message: "La asistencia IA se conectará después de cerrar la réplica base.")
                EPPlaceholderActionButton(title: "Adjuntar Drive", icon: "externaldrive.fill", message: "El selector Drive queda pendiente de conexión nativa.")
            }
        }
    }

    private func chipEditor(
        title: String,
        placeholder: String,
        text: Binding<String>,
        items: [String],
        tint: Color,
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))

            if items.isEmpty {
                Text("Sin elementos agregados.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ReplicaFlowLayout(spacing: 7) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.black))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.11), in: Capsule())
                            .onLongPressGesture {
                                onRemove(item)
                            }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .font(.caption.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
                Button {
                    let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    onAdd(value)
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var classNumbers: [Int] {
        guard let crono = viewModel.cronograma else { return [1] }
        let maxNumber = max(crono.totalClases, crono.clases.map(\.numero).max() ?? 0)
        return maxNumber > 0 ? Array(1...maxNumber) : [1]
    }

    private func cronogramaClass(for classNum: Int) -> ClaseCronograma? {
        viewModel.cronograma?.clases.first { $0.numero == classNum }
    }

    private var linkedOAs: [OAEditado] {
        guard let verUnidad = viewModel.verUnidad else { return [] }
        let ids = activeActivity.oaIds
        return verUnidad.oas.filter { oa in
            ids.contains { matchesOAId($0, oa: oa) }
        }
    }

    private var selectedUnitSkills: [String] {
        viewModel.verUnidad?.habilidades
            .filter(\.seleccionado)
            .map(\.texto)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    private var selectedUnitAttitudes: [String] {
        viewModel.verUnidad?.actitudes
            .filter(\.seleccionado)
            .map(\.texto)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    private var activeActivity: ActividadClase {
        viewModel.clasesActividades[selectedClassNum] ?? viewModel.activityTemplate(for: selectedClassNum)
    }

    private var activeActivityBinding: Binding<ActividadClase> {
        Binding(
            get: {
                activeActivity
            },
            set: { newValue in
                viewModel.clasesActividades[selectedClassNum] = newValue
            }
        )
    }

    private func selectClass(_ classNum: Int) {
        selectedClassNum = classNum
        ensureActivityExists(for: classNum)
    }

    private func normalizeSelectedClass() {
        if !classNumbers.contains(selectedClassNum) {
            selectedClassNum = classNumbers.first ?? 1
        }
        ensureActivityExists(for: selectedClassNum)
    }

    private func ensureActivityExists(for classNum: Int) {
        viewModel.ensureActivity(for: classNum)
    }

    private func isClassPlanificable(classNum: Int) -> Bool {
        guard let act = viewModel.clasesActividades[classNum] else { return false }
        return !RichTextHTML.plainText(from: act.objetivo).isEmpty ||
        !RichTextHTML.plainText(from: act.inicio).isEmpty ||
        !RichTextHTML.plainText(from: act.desarrollo).isEmpty ||
        !RichTextHTML.plainText(from: act.cierre).isEmpty ||
        !RichTextHTML.plainText(from: act.adecuacion).isEmpty ||
        !RichTextHTML.plainText(from: act.contextoProfesor ?? "").isEmpty ||
        !act.oaIds.isEmpty ||
        !act.habilidades.isEmpty ||
        !act.actitudes.isEmpty ||
        !act.materiales.isEmpty ||
        !act.tics.isEmpty ||
        !(act.archivos ?? []).isEmpty ||
        hasExternalPedagogyData(act)
    }

    private func indicatorsForClass(_ oa: OAEditado) -> [IndicadorEditado] {
        guard let raw = indicatorSelectionValues(for: oa), !raw.isEmpty else {
            return oa.indicadores.filter(\.seleccionado)
        }

        let selected = Set(raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let normalizedSelected = Set(selected.map(normalizePedagogicalId))
        let known = oa.indicadores.filter {
            selected.contains($0.id) ||
            selected.contains($0.texto) ||
            normalizedSelected.contains(normalizePedagogicalId($0.id)) ||
            normalizedSelected.contains(normalizePedagogicalId($0.texto))
        }
        let knownText = Set(known.flatMap { [$0.id, $0.texto] })
        let normalizedKnown = Set(knownText.map(normalizePedagogicalId))
        let custom = selected
            .filter { !knownText.contains($0) && !normalizedKnown.contains(normalizePedagogicalId($0)) }
            .map { value in
                IndicadorEditado(id: "\(oa.id)_class_\(value.hashValue.magnitude)", texto: value, seleccionado: true)
            }

        return known + custom.sorted { $0.texto.localizedCaseInsensitiveCompare($1.texto) == .orderedAscending }
    }

    private func curriculumToggleSection(
        title: String,
        icon: String,
        available: [String],
        selected: [String],
        tint: Color,
        onToggle: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            let merged = Array(Set(available + selected)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if merged.isEmpty {
                Text("Sin \(title.lowercased()) seleccionadas en la unidad.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ReplicaFlowLayout(spacing: 7) {
                    ForEach(merged, id: \.self) { value in
                        let isSelected = selected.contains(value)
                        Button {
                            onToggle(value)
                        } label: {
                            HStack(spacing: 5) {
                                Text(value)
                                    .font(.caption.weight(.black))
                                    .lineLimit(2)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .black))
                                }
                            }
                            .foregroundStyle(isSelected ? .white : tint)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(isSelected ? tint : tint.opacity(0.11), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func toggleString(_ value: String, keyPath: WritableKeyPath<ActividadClase, [String]>) {
        var act = activeActivity
        if act[keyPath: keyPath].contains(value) {
            act[keyPath: keyPath].removeAll { $0 == value }
        } else {
            act[keyPath: keyPath].append(value)
        }
        viewModel.clasesActividades[selectedClassNum] = act
    }

    private func getStudents() -> [EstudiantePerfil] {
        viewModel.snapshot?.studentsByCourse[viewModel.curso] ?? []
    }

    private func hasExternalPedagogyData(_ act: ActividadClase) -> Bool {
        if let objetivoMultinivel = act.objetivoMultinivel,
           [objetivoMultinivel.basico, objetivoMultinivel.intermedio, objetivoMultinivel.avanzado, objetivoMultinivel.recomendado].contains(where: { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) {
            return true
        }
        if let bloom = act.analisisBloom, !bloom.isEmpty { return true }
        if let indicadores = act.indicadoresEvaluacion, !indicadores.isEmpty { return true }
        if let actividadEvaluacion = act.actividadEvaluacion,
           (
            [actividadEvaluacion.tipo, actividadEvaluacion.descripcion, actividadEvaluacion.instrumento].contains(where: { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) ||
            !(actividadEvaluacion.criterios ?? []).isEmpty ||
            !(actividadEvaluacion.alineacionMBE ?? []).isEmpty
           ) {
            return true
        }
        if let desarrolloFormal = act.desarrolloFormal,
           [desarrolloFormal.inicio, desarrolloFormal.desarrollo, desarrolloFormal.cierre].contains(where: { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) {
            return true
        }
        return false
    }

    private func indicatorSelectionValues(for oa: OAEditado) -> [String]? {
        guard let map = activeActivity.indicadoresPorOa else { return nil }
        let keys = oaIdCandidates(for: oa)
        for key in keys {
            if let values = map[key], !values.isEmpty {
                return values
            }
        }

        let normalizedKeys = Set(keys.map(normalizePedagogicalId))
        if let match = map.first(where: { normalizedKeys.contains(normalizePedagogicalId($0.key)) && !$0.value.isEmpty }) {
            return match.value
        }
        return nil
    }

    private func matchesOAId(_ value: String, oa: OAEditado) -> Bool {
        let candidates = oaIdCandidates(for: oa)
        if candidates.contains(value) { return true }
        let normalized = normalizePedagogicalId(value)
        return candidates.map(normalizePedagogicalId).contains(normalized)
    }

    private func oaIdCandidates(for oa: OAEditado) -> [String] {
        var candidates = [oa.id]
        if let numero = oa.numero {
            candidates.append("OA\(numero)")
            candidates.append(String(numero))
            candidates.append("oa-\(numero)")
            candidates.append("oa_\(numero)")
        }
        return Array(Set(candidates)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func normalizePedagogicalId(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func externalTextRow(_ label: String, _ value: String?, tint: Color) -> some View {
        Group {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    EPStatusPill(text: label, tint: tint)
                    RichTextRenderer(html: value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func labeledChipList(_ label: String, _ values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.black))
            ReplicaFlowLayout(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tint.opacity(0.1), in: Capsule())
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension Binding where Value == Optional<String> {
    func toNonOptional() -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}

private extension ActividadClase {
    var estadoLabel: String {
        switch estado {
        case "planificada": return "Planificada"
        case "realizada": return "Realizada"
        case "no_planificada": return "No planificada"
        default: return estado.isEmpty ? "No planificada" : estado.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var estadoTint: Color {
        switch estado {
        case "planificada": return .green
        case "realizada": return .blue
        case "no_planificada": return .orange
        default: return .secondary
        }
    }
}
