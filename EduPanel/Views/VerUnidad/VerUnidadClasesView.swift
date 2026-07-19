import SwiftUI

struct VerUnidadClasesView: View {
    var viewModel: VerUnidadViewModel

    @State private var selectedClassNum = 1
    @State private var presentedSheet: ClassOverviewSheet?

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        VStack(spacing: 0) {
            ClassNavigator(
                classNumbers: classNumbers,
                selectedClass: $selectedClassNum,
                dateForClass: classDate,
                hasPlanForClass: isClassPlanificable
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ClassOverviewHeader(
                        classNumber: selectedClassNum,
                        date: classDate(selectedClassNum),
                        activity: activeActivity,
                        linkedObjectiveCount: linkedOAs.count,
                        canEdit: viewModel.canEditActivity(selectedClassNum) && !viewModel.isSaving,
                        onEdit: openEditor
                    )

                    classContent
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .reportsTabBarScroll()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: normalizeSelectedClass)
        .onChange(of: classNumbers) { _, _ in normalizeSelectedClass() }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .editor(let classNumber):
                ClassPlanningEditorView(viewModel: viewModel, classNumber: classNumber)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .reading(let data):
                ClassReadingSheet(data: data)
            case .indicators(let data):
                ClassIndicatorsSheet(data: data)
            case .list(let data):
                ClassTextListSheet(data: data)
            case .advanced(let activity):
                ClassAdvancedPedagogySheet(activity: activity)
            }
        }
    }

    @ViewBuilder
    private var classContent: some View {
        if viewModel.isReloadingActivities {
            ClassActivityLoadingCard()
        } else if !viewModel.canEditActivity(selectedClassNum) {
            ClassActivityLoadErrorCard(
                classNumber: selectedClassNum,
                isRetrying: viewModel.isSaving || viewModel.isReloadingActivities,
                onRetry: retryActivityLoads
            )
        } else if isClassPlanificable(selectedClassNum) {
            plannedClassContent
        } else {
            ClassEmptyPlanCard(
                classNumber: selectedClassNum,
                isDisabled: viewModel.isSaving,
                onPlan: openEditor
            )
        }
    }

    private var plannedClassContent: some View {
        let activity = activeActivity

        return Group {
            ClassPlanOverviewCard(
                objectiveHTML: activity.objetivo,
                moments: classMoments(from: activity),
                onOpenObjective: { openReading(title: "Objetivo de la clase", html: activity.objetivo, symbol: "scope") },
                onOpenMoment: openMoment
            )

            ClassLinkedObjectivesCard(
                objectives: linkedOAs.map {
                    ClassLinkedObjective(objective: $0, indicators: indicatorsForClass($0))
                },
                onShowIndicators: openIndicators
            )

            ClassContextAdaptationSection(
                teacherContextHTML: activity.contextoProfesor ?? "",
                adaptationHTML: activity.adecuacion
            )

            ClassCurriculumCard(
                categories: curriculumCategories(from: activity),
                onOpenCategory: openCurriculumCategory
            )

            ClassMaterialsCard(
                materials: activity.materiales,
                files: activity.archivos ?? []
            )

            if !displayMode.isSimple && ClassAdvancedPedagogyContent.hasData(activity) {
                ClassAdvancedSummaryButton {
                    presentedSheet = .advanced(activity)
                }
            }

            Label(
                "Los cambios se guardan en el iPhone y se sincronizan con EduPanel web",
                systemImage: "checkmark.icloud.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private var classNumbers: [Int] {
        guard let schedule = viewModel.cronograma else { return [1] }
        let maximum = max(schedule.totalClases, schedule.clases.map(\.numero).max() ?? 0)
        return maximum > 0 ? Array(1...maximum) : [1]
    }

    private var activeActivity: ActividadClase {
        viewModel.clasesActividades[selectedClassNum]
            ?? viewModel.activityTemplate(for: selectedClassNum)
    }

    private var linkedOAs: [OAEditado] {
        guard let unit = viewModel.verUnidad else { return [] }
        return unit.oas.filter { objective in
            activeActivity.oaIds.contains { matchesOAId($0, objective: objective) }
        }
    }

    private func classDate(_ classNumber: Int) -> String {
        let date = viewModel.cronograma?.clases
            .first(where: { $0.numero == classNumber })?
            .fecha ?? ""
        return date.isEmpty ? "Sin fecha" : date
    }

    private func classMoments(from activity: ActividadClase) -> [ClassMoment] {
        [
            ClassMoment(title: "Inicio", html: activity.inicio, symbol: "1.circle.fill", tint: .blue),
            ClassMoment(title: "Desarrollo", html: activity.desarrollo, symbol: "2.circle.fill", tint: .green),
            ClassMoment(title: "Cierre", html: activity.cierre, symbol: "3.circle.fill", tint: .purple)
        ]
        .filter { hasText($0.html) }
    }

    private func curriculumCategories(from activity: ActividadClase) -> [ClassCurriculumCategory] {
        [
            ClassCurriculumCategory(title: "Habilidades", symbol: "figure.mind.and.body", tint: .blue, items: activity.habilidades),
            ClassCurriculumCategory(title: "Actitudes", symbol: "heart.fill", tint: .red, items: activity.actitudes),
            ClassCurriculumCategory(title: "Herramientas TIC", symbol: "desktopcomputer", tint: .purple, items: activity.tics)
        ]
        .filter { !$0.items.isEmpty }
    }

    private func normalizeSelectedClass() {
        guard !classNumbers.contains(selectedClassNum) else { return }
        selectedClassNum = classNumbers.first ?? 1
    }

    private func openEditor() {
        guard !viewModel.isSaving, viewModel.canEditActivity(selectedClassNum) else { return }
        viewModel.ensureActivity(for: selectedClassNum)
        presentedSheet = .editor(selectedClassNum)
    }

    private func openMoment(_ moment: ClassMoment) {
        openReading(title: moment.title, html: moment.html, symbol: moment.symbol)
    }

    private func openReading(title: String, html: String, symbol: String) {
        presentedSheet = .reading(
            ClassReadingSheetData(title: title, html: html, symbol: symbol)
        )
    }

    private func openIndicators(_ linkedObjective: ClassLinkedObjective) {
        presentedSheet = .indicators(
            ClassIndicatorsSheetData(
                objective: linkedObjective.objective,
                indicators: linkedObjective.indicators
            )
        )
    }

    private func openCurriculumCategory(_ category: ClassCurriculumCategory) {
        presentedSheet = .list(
            ClassTextListSheetData(
                title: category.title,
                symbol: category.symbol,
                items: category.items
            )
        )
    }

    private func retryActivityLoads() {
        Task { await viewModel.retryActivityLoads() }
    }

    private func hasText(_ html: String) -> Bool {
        !RichTextHTML.plainText(from: html)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func isClassPlanificable(_ classNumber: Int) -> Bool {
        guard let activity = viewModel.clasesActividades[classNumber] else { return false }
        return hasText(activity.objetivo) ||
            hasText(activity.inicio) ||
            hasText(activity.desarrollo) ||
            hasText(activity.cierre) ||
            hasText(activity.adecuacion) ||
            hasText(activity.contextoProfesor ?? "") ||
            !activity.habilidades.isEmpty ||
            !activity.actitudes.isEmpty ||
            !activity.materiales.isEmpty ||
            !activity.tics.isEmpty ||
            activity.indicadoresPorOa?.values.contains(where: { !$0.isEmpty }) == true ||
            !(activity.archivos ?? []).isEmpty ||
            ClassAdvancedPedagogyContent.hasData(activity)
    }

    private func indicatorsForClass(_ objective: OAEditado) -> [IndicadorEditado] {
        guard let rawValues = indicatorSelectionValues(for: objective) else {
            return objective.indicadores.filter(\.seleccionado)
        }
        guard !rawValues.isEmpty else { return [] }

        let selected = Set(rawValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let normalizedSelected = Set(selected.map(normalizePedagogicalID))
        let known = objective.indicadores.filter {
            selected.contains($0.id) || selected.contains($0.texto) ||
                normalizedSelected.contains(normalizePedagogicalID($0.id)) ||
                normalizedSelected.contains(normalizePedagogicalID($0.texto))
        }
        let knownValues = Set(known.flatMap { [$0.id, $0.texto] })
        let normalizedKnown = Set(knownValues.map(normalizePedagogicalID))
        let custom = selected
            .filter { !knownValues.contains($0) && !normalizedKnown.contains(normalizePedagogicalID($0)) }
            .map { value in
                IndicadorEditado(
                    id: "\(objective.id)_class_\(value.hashValue.magnitude)",
                    texto: value,
                    seleccionado: true
                )
            }

        return known + custom.sorted {
            $0.texto.localizedCaseInsensitiveCompare($1.texto) == .orderedAscending
        }
    }

    private func indicatorSelectionValues(for objective: OAEditado) -> [String]? {
        guard let map = activeActivity.indicadoresPorOa else { return nil }
        let keys = objectiveIDCandidates(for: objective)
        for key in keys where map[key] != nil { return map[key] }

        let normalizedKeys = Set(keys.map(normalizePedagogicalID))
        return map.first(where: { normalizedKeys.contains(normalizePedagogicalID($0.key)) })?.value
    }

    private func matchesOAId(_ value: String, objective: OAEditado) -> Bool {
        let candidates = objectiveIDCandidates(for: objective)
        return candidates.contains(value) ||
            candidates.map(normalizePedagogicalID).contains(normalizePedagogicalID(value))
    }

    private func objectiveIDCandidates(for objective: OAEditado) -> [String] {
        var candidates = [objective.id]
        if let number = objective.numero {
            candidates += ["OA\(number)", String(number), "oa-\(number)", "oa_\(number)"]
        }
        return Array(Set(candidates))
    }

    private func normalizePedagogicalID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}
