import SwiftUI

/// Planificación y visualización de las clases de una unidad.
struct VerUnidadClasesView: View {
    var viewModel: VerUnidadViewModel

    @State private var selectedClassNum = 1
    @State private var presentedSheet: ClassSheet?

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        VStack(spacing: 0) {
            classSelectorRail

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    resumenCard

                    if viewModel.isReloadingActivities {
                        activityLoadingCard
                    } else if !viewModel.canEditActivity(selectedClassNum) {
                        activityLoadErrorCard
                    } else if isClassPlanificable(classNum: selectedClassNum) {
                        planCard
                        oasCard
                        extrasSection
                        curriculoYRecursosSection
                        if !displayMode.isSimple {
                            externalPedagogyCard
                        }
                    } else {
                        emptyPlanCard
                    }

                    if viewModel.canEditActivity(selectedClassNum) {
                        editingSyncNote
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .editor(let classNumber):
                ClassPlanningEditorView(viewModel: viewModel, classNumber: classNumber)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .live(let classNumber):
                LiveClassModeView(
                    actividad: viewModel.clasesActividades[classNumber]
                        ?? viewModel.activityTemplate(for: classNumber),
                    students: getStudents(),
                    dashboardRepository: viewModel.planificacionRepository
                )
            }
        }
    }

    // MARK: - Selector de clases

    private var classSelectorRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(classNumbers, id: \.self) { cNum in
                    let isSelected = selectedClassNum == cNum
                    let hasData = isClassPlanificable(classNum: cNum)
                    let cronoClass = cronogramaClass(for: cNum)
                    Button {
                        withAnimation(EPTheme.spring) {
                            selectedClassNum = cNum
                        }
                    } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 5) {
                                Text("Clase \(cNum)")
                                    .font(.system(size: 12, weight: .black))
                                if hasData {
                                    Circle()
                                        .fill(isSelected ? .white : .green)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            if let cronoClass, !cronoClass.fecha.isEmpty {
                                Text(cronoClass.fecha)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                            }
                        }
                        .foregroundStyle(isSelected ? .white : EPTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            isSelected ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(Color(.systemGray6)),
                            in: Capsule()
                        )
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

    // MARK: - Resumen de la clase

    private var resumenCard: some View {
        let act = activeActivity
        let cronoClass = cronogramaClass(for: selectedClassNum)

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clase \(selectedClassNum)")
                            .font(.system(size: 18, weight: .black))
                        Text(cronoClass?.fecha.isEmpty == false ? cronoClass!.fecha : "Sin fecha programada")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 7) {
                        Button(action: openEditor) {
                            Label("Editar", systemImage: "pencil")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(EPTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(EPTheme.primary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSaving || !viewModel.canEditActivity(selectedClassNum))
                        .accessibilityLabel("Editar planificación de la clase \(selectedClassNum)")

                        Button(action: openLiveMode) {
                            Label("En vivo", systemImage: "play.fill")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(EPTheme.heroGradient, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Iniciar clase \(selectedClassNum) en vivo")
                        .disabled(viewModel.isReloadingActivities)
                    }
                }

                HStack(spacing: 7) {
                    EPStatusPill(text: act.estadoLabel, icon: "circle.fill", tint: act.estadoTint)
                    EPStatusPill(
                        text: "\(linkedOAs.count) OA",
                        icon: "tag.fill",
                        tint: linkedOAs.isEmpty ? .orange : .green
                    )
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Plan de la clase (lectura)

    private var planCard: some View {
        let act = activeActivity

        return EPWebCard {
            VStack(alignment: .leading, spacing: 16) {
                EPSectionHeader(title: "Plan de la clase", icon: "text.book.closed.fill")

                if hasText(act.objetivo) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OBJETIVO DE LA CLASE")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(EPTheme.primary)
                        RichTextRenderer(html: act.objetivo)
                    }
                }

                momentoRow(numero: 1, titulo: "Inicio", html: act.inicio, tint: .blue)
                momentoRow(numero: 2, titulo: "Desarrollo", html: act.desarrollo, tint: .green)
                momentoRow(numero: 3, titulo: "Cierre", html: act.cierre, tint: .purple)
            }
        }
    }

    @ViewBuilder
    private func momentoRow(numero: Int, titulo: String, html: String, tint: Color) -> some View {
        if hasText(html) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(numero)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(tint, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(titulo)
                        .font(.system(size: 13, weight: .black))
                    RichTextRenderer(html: html)
                }
            }
        }
    }

    // MARK: - OAs vinculados

    private var oasCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Objetivos vinculados", icon: "tag.fill")

                let linked = linkedOAs
                if linked.isEmpty {
                    Label("Esta clase no tiene OA asignados.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    ForEach(linked, id: \.id) { oa in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(EPTheme.primary)
                            Text(oa.descripcion)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            let selectedIndicators = indicatorsForClass(oa)
                            if !selectedIndicators.isEmpty {
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
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Contexto y adecuación (colapsable)

    private var extrasSection: some View {
        let act = activeActivity
        let contexto = act.contextoProfesor ?? ""

        return Group {
            if hasText(contexto) || hasText(act.adecuacion) {
                EPCollapsibleSection(title: "Contexto y adecuación", subtitle: "Notas y apoyos PIE/DUA.", icon: "person.text.rectangle") {
                    VStack(alignment: .leading, spacing: 14) {
                        if hasText(contexto) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Contexto de la clase")
                                    .font(.system(size: 12, weight: .black))
                                RichTextRenderer(html: contexto)
                            }
                        }
                        if hasText(act.adecuacion) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Adecuación curricular")
                                    .font(.system(size: 12, weight: .black))
                                RichTextRenderer(html: act.adecuacion)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Currículo y recursos (colapsable, solo lectura)

    private var curriculoYRecursosSection: some View {
        let act = activeActivity
        let hayContenido = !act.habilidades.isEmpty || !act.actitudes.isEmpty
            || !act.materiales.isEmpty || !act.tics.isEmpty || !(act.archivos ?? []).isEmpty

        return Group {
            if hayContenido {
                EPCollapsibleSection(title: "Currículo y recursos", subtitle: "Habilidades, actitudes y materiales.", icon: "tray.full.fill") {
                    VStack(alignment: .leading, spacing: 14) {
                        chipsRow(titulo: "Habilidades", items: act.habilidades, tint: EPTheme.primary)
                        chipsRow(titulo: "Actitudes", items: act.actitudes, tint: .orange)
                        chipsRow(titulo: "Materiales", items: act.materiales, tint: .blue)
                        chipsRow(titulo: "Herramientas TIC", items: act.tics, tint: .purple)

                        if let archivos = act.archivos, !archivos.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Archivos")
                                    .font(.system(size: 12, weight: .black))
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
        }
    }

    @ViewBuilder
    private func chipsRow(titulo: String, items: [String], tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(titulo)
                    .font(.system(size: 12, weight: .black))
                ReplicaFlowLayout(spacing: 7) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.11), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Datos pedagógicos avanzados (colapsable, solo lectura)

    private var externalPedagogyCard: some View {
        let act = activeActivity

        return Group {
            if hasExternalPedagogyData(act) {
                EPCollapsibleSection(title: "Datos pedagógicos avanzados", subtitle: "Multinivel, Bloom y evaluación.", icon: "brain.head.profile") {
                    VStack(alignment: .leading, spacing: 14) {
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
                                            EPStatusPill(text: item.nivel ?? "Nivel", tint: .purple)
                                        }
                                        if let justificacion = item.justificacion, !justificacion.isEmpty {
                                            Text(justificacion)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.secondary)
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
                                        Text(indicador.texto)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
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
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Vacío y aviso

    private var emptyPlanCard: some View {
        EPWebCard {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("Esta clase aún no está planificada")
                    .font(.system(size: 15, weight: .black))
                Text("Define el objetivo, los momentos de la sesión y sus recursos directamente desde tu iPhone.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: openEditor) {
                    Label("Planificar esta clase", systemImage: "square.and.pencil")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("planificar-clase-\(selectedClassNum)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private var editingSyncNote: some View {
        Label("Los cambios se guardan en el iPhone y se sincronizan con EduPanel web", systemImage: "checkmark.icloud.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var activityLoadErrorCard: some View {
        EPWebCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("No pudimos cargar esta planificación")
                    .font(.system(size: 15, weight: .black))
                Text("Para proteger lo que ya existe en EduPanel, la edición queda bloqueada hasta recuperar la clase.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task {
                        await viewModel.retryActivityLoads()
                    }
                } label: {
                    Label("Reintentar carga", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(viewModel.isSaving || viewModel.isReloadingActivities)
                .accessibilityIdentifier("reintentar-carga-clase-\(selectedClassNum)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private var activityLoadingCard: some View {
        EPWebCard {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Recuperando planificaciones...")
                    .font(.system(size: 14, weight: .black))
                Text("La edición se habilitará cuando termine la carga.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recuperando planificaciones de clases")
        }
    }

    // MARK: - Datos derivados

    private func hasText(_ html: String) -> Bool {
        !RichTextHTML.plainText(from: html).isEmpty
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

    private var activeActivity: ActividadClase {
        viewModel.clasesActividades[selectedClassNum] ?? viewModel.activityTemplate(for: selectedClassNum)
    }

    private func normalizeSelectedClass() {
        if !classNumbers.contains(selectedClassNum) {
            selectedClassNum = classNumbers.first ?? 1
        }
    }

    private func openEditor() {
        guard !viewModel.isSaving, viewModel.canEditActivity(selectedClassNum) else { return }
        viewModel.ensureActivity(for: selectedClassNum)
        presentedSheet = .editor(selectedClassNum)
    }

    private func openLiveMode() {
        guard !viewModel.isReloadingActivities else { return }
        viewModel.ensureActivity(for: selectedClassNum)
        presentedSheet = .live(selectedClassNum)
    }

    private func isClassPlanificable(classNum: Int) -> Bool {
        guard let act = viewModel.clasesActividades[classNum] else { return false }
        return !RichTextHTML.plainText(from: act.objetivo).isEmpty ||
        !RichTextHTML.plainText(from: act.inicio).isEmpty ||
        !RichTextHTML.plainText(from: act.desarrollo).isEmpty ||
        !RichTextHTML.plainText(from: act.cierre).isEmpty ||
        !RichTextHTML.plainText(from: act.adecuacion).isEmpty ||
        !RichTextHTML.plainText(from: act.contextoProfesor ?? "").isEmpty ||
        !act.habilidades.isEmpty ||
        !act.actitudes.isEmpty ||
        !act.materiales.isEmpty ||
        !act.tics.isEmpty ||
        act.indicadoresPorOa?.values.contains(where: { !$0.isEmpty }) == true ||
        !(act.archivos ?? []).isEmpty ||
        hasExternalPedagogyData(act)
    }

    private func indicatorsForClass(_ oa: OAEditado) -> [IndicadorEditado] {
        guard let raw = indicatorSelectionValues(for: oa) else {
            return oa.indicadores.filter(\.seleccionado)
        }

        guard !raw.isEmpty else { return [] }

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
            if let values = map[key] {
                return values
            }
        }

        let normalizedKeys = Set(keys.map(normalizePedagogicalId))
        if let match = map.first(where: { normalizedKeys.contains(normalizePedagogicalId($0.key)) }) {
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
            }
        }
    }
}

private enum ClassSheet: Identifiable {
    case editor(Int)
    case live(Int)

    var id: String {
        switch self {
        case .editor(let classNumber): return "editor-\(classNumber)"
        case .live(let classNumber): return "live-\(classNumber)"
        }
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
