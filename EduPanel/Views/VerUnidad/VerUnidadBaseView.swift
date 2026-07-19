import SwiftUI

struct VerUnidadBaseView: View {
    var viewModel: VerUnidadViewModel

    @State private var presentedSheet: UnitOverviewSheet?
    @State private var showsSupportingCurriculum = false
    @State private var newResource = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let unit = viewModel.verUnidad {
                    UnitStatusCard(
                        dateRange: dateRange,
                        hours: unit.horas,
                        classes: totalClasses(for: unit)
                    )

                    UnitPlanCard(
                        purposeHTML: unit.descripcion,
                        hasTeacherContext: hasContent(unit.contextoDocente),
                        hasTeacherGoal: hasContent(unit.objetivoDocente),
                        onOpenContext: openContextEditor
                    )

                    UnitObjectivesCard(
                        objectives: selectedObjectives(from: unit),
                        onShowIndicators: openIndicators
                    )

                    UnitLearningRouteCard(
                        attitudes: routeAttitudes(from: unit),
                        skills: unit.habilidades.filter(\.seleccionado),
                        knowledge: unit.conocimientos.filter(\.seleccionado),
                        showsSupportingCurriculum: $showsSupportingCurriculum
                    )

                    UnitMaterialsCard(
                        files: unit.recursosMaterialesUnidadArchivos ?? [],
                        resources: resourcesBinding,
                        newResource: $newResource,
                        onAddResource: addResource
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .reportsTabBarScroll()
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .context:
                UnitContextEditorSheet(
                    teacherContext: teacherContextBinding,
                    teacherGoal: teacherGoalBinding
                )
            case .indicators(let objective):
                UnitIndicatorsSheet(objective: objective)
            }
        }
    }

    private var dateRange: String {
        let dates = (viewModel.cronograma?.clases ?? [])
            .compactMap { Self.parseDate($0.fecha) }
            .sorted()

        guard let first = dates.first, let last = dates.last else {
            return "Sin fechas asignadas"
        }

        if Calendar.current.isDate(first, inSameDayAs: last) {
            return Self.dateFormatter.string(from: first)
        }
        return "\(Self.dateFormatter.string(from: first)) al \(Self.dateFormatter.string(from: last))"
    }

    private var resourcesBinding: Binding<[String]> {
        Binding(
            get: { viewModel.verUnidad?.recursosMaterialesUnidad ?? [] },
            set: { viewModel.verUnidad?.recursosMaterialesUnidad = $0 }
        )
    }

    private var teacherContextBinding: Binding<String> {
        Binding(
            get: { viewModel.verUnidad?.contextoDocente ?? "" },
            set: { viewModel.verUnidad?.contextoDocente = $0 }
        )
    }

    private var teacherGoalBinding: Binding<String> {
        Binding(
            get: { viewModel.verUnidad?.objetivoDocente ?? "" },
            set: { viewModel.verUnidad?.objetivoDocente = $0 }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static func parseDate(_ value: String) -> Date? {
        dateFormatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func totalClasses(for unit: VerUnidadGuardada) -> Int {
        let scheduled = viewModel.cronograma?.clases.map(\.numero).max() ?? 0
        return max(viewModel.cronograma?.totalClases ?? unit.clases, scheduled)
    }

    private func selectedObjectives(from unit: VerUnidadGuardada) -> [OAEditado] {
        unit.oas.filter { objective in
            objective.seleccionado && (objective.tipo ?? "").lowercased() != "oat"
        }
    }

    private func routeAttitudes(from unit: VerUnidadGuardada) -> [UnitRouteItem] {
        let attitudes = unit.actitudes
            .filter(\.seleccionado)
            .map {
                UnitRouteItem(
                    id: "actitud-\($0.id)",
                    category: "Actitud",
                    text: $0.texto,
                    symbol: "heart.fill"
                )
            }

        let transversalObjectives = unit.oas
            .filter { $0.seleccionado && ($0.tipo ?? "").lowercased() == "oat" }
            .map {
                UnitRouteItem(
                    id: "oaa-\($0.id)",
                    category: $0.numero.map { "OAA \($0)" } ?? "OAA",
                    text: $0.descripcion,
                    symbol: "person.2.fill"
                )
            }

        return attitudes + transversalObjectives
    }

    private func hasContent(_ html: String) -> Bool {
        !RichTextHTML.plainText(from: html).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func openContextEditor() {
        presentedSheet = .context
    }

    private func openIndicators(_ objective: OAEditado) {
        presentedSheet = .indicators(objective)
    }

    private func addResource() {
        let value = newResource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        var resources = viewModel.verUnidad?.recursosMaterialesUnidad ?? []
        resources.append(value)
        viewModel.verUnidad?.recursosMaterialesUnidad = resources
        newResource = ""
    }
}

enum UnitOverviewSheet: Identifiable {
    case context
    case indicators(OAEditado)

    var id: String {
        switch self {
        case .context:
            return "context"
        case .indicators(let objective):
            return "indicators-\(objective.id)"
        }
    }
}
