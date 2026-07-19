import SwiftUI

struct ClassNavigator: View {
    let classNumbers: [Int]
    @Binding var selectedClass: Int
    let dateForClass: (Int) -> String
    let hasPlanForClass: (Int) -> Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: selectPrevious) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.black))
                    .frame(width: 44, height: 44)
                    .classInteractiveGlass(shape: .circle)
            }
            .buttonStyle(.plain)
            .disabled(selectedClass == classNumbers.first)
            .accessibilityLabel("Clase anterior")

            Menu {
                ForEach(classNumbers, id: \.self) { classNumber in
                    Button {
                        withAnimation(EPTheme.spring) { selectedClass = classNumber }
                    } label: {
                        Label(
                            "Clase \(classNumber) · \(dateForClass(classNumber))",
                            systemImage: hasPlanForClass(classNumber) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clase \(selectedClass) de \(classNumbers.count)")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                        Text(dateForClass(selectedClass))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .classInteractiveGlass(shape: .roundedRectangle)
            }
            .accessibilityLabel("Seleccionar clase")
            .accessibilityValue("Clase \(selectedClass) de \(classNumbers.count)")

            Button(action: selectNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.black))
                    .frame(width: 44, height: 44)
                    .classInteractiveGlass(shape: .circle)
            }
            .buttonStyle(.plain)
            .disabled(selectedClass == classNumbers.last)
            .accessibilityLabel("Clase siguiente")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.12))
                .frame(height: 1)
        }
        .sensoryFeedback(.selection, trigger: selectedClass)
    }

    private func selectPrevious() {
        guard let index = classNumbers.firstIndex(of: selectedClass), index > 0 else { return }
        withAnimation(EPTheme.spring) { selectedClass = classNumbers[index - 1] }
    }

    private func selectNext() {
        guard let index = classNumbers.firstIndex(of: selectedClass), index < classNumbers.count - 1 else { return }
        withAnimation(EPTheme.spring) { selectedClass = classNumbers[index + 1] }
    }
}

struct ClassOverviewHeader: View {
    let classNumber: Int
    let date: String
    let activity: ActividadClase
    let linkedObjectiveCount: Int
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clase \(classNumber)")
                            .font(.title3.weight(.black))
                        Label(date, systemImage: "calendar")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button(action: onEdit) {
                        Label("Editar", systemImage: "pencil")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .classInteractiveGlass(shape: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    .accessibilityLabel("Editar planificación de la clase \(classNumber)")
                }

                HStack(spacing: 7) {
                    EPStatusPill(text: activity.classStatusLabel, icon: "circle.fill", tint: activity.classStatusTint)
                    EPStatusPill(
                        text: linkedObjectiveCount == 1 ? "1 OA" : "\(linkedObjectiveCount) OA",
                        icon: "target",
                        tint: linkedObjectiveCount == 0 ? .orange : .green
                    )
                }
            }
        }
    }
}

struct ClassMoment: Identifiable {
    let title: String
    let html: String
    let symbol: String
    let tint: Color

    var id: String { title }
}

struct ClassPlanOverviewCard: View {
    let objectiveHTML: String
    let moments: [ClassMoment]
    let onOpenObjective: () -> Void
    let onOpenMoment: (ClassMoment) -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 15) {
                UnitSectionHeader(
                    title: "Plan de la clase",
                    subtitle: "Objetivo y momentos principales",
                    symbol: "text.book.closed.fill"
                )

                if hasContent(objectiveHTML) {
                    Button(action: onOpenObjective) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("OBJETIVO DE LA CLASE")
                                    .font(.caption2.weight(.black))
                                    .tracking(0.7)
                                    .foregroundStyle(EPTheme.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(EPTheme.primary)
                            }
                            Text(plainText(objectiveHTML))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(EPTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abre el objetivo completo")
                }

                VStack(spacing: 9) {
                    ForEach(moments) { moment in
                        ClassMomentRow(moment: moment) {
                            onOpenMoment(moment)
                        }
                    }
                }
            }
        }
    }

    private func hasContent(_ html: String) -> Bool {
        !plainText(html).isEmpty
    }

    private func plainText(_ html: String) -> String {
        RichTextHTML.plainText(from: html)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ClassMomentRow: View {
    let moment: ClassMoment
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: moment.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(moment.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(moment.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(moment.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre el texto completo de \(moment.title.lowercased())")
    }

    private var summary: String {
        RichTextHTML.plainText(from: moment.html)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ClassLinkedObjective: Identifiable {
    let objective: OAEditado
    let indicators: [IndicadorEditado]

    var id: String { objective.id }
}

struct ClassLinkedObjectivesCard: View {
    let objectives: [ClassLinkedObjective]
    let onShowIndicators: (ClassLinkedObjective) -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 14) {
                UnitSectionHeader(
                    title: "Objetivos vinculados",
                    subtitle: objectives.isEmpty ? "Sin objetivos asignados" : objectiveCountText,
                    symbol: "target"
                )

                if objectives.isEmpty {
                    UnitEmptyMessage(
                        text: "Esta clase no tiene objetivos asignados.",
                        symbol: "target"
                    )
                } else {
                    ForEach(objectives) { linkedObjective in
                        ClassLinkedObjectiveRow(
                            linkedObjective: linkedObjective,
                            onShowIndicators: { onShowIndicators(linkedObjective) }
                        )
                    }
                }
            }
        }
    }

    private var objectiveCountText: String {
        objectives.count == 1 ? "1 objetivo para esta clase" : "\(objectives.count) objetivos para esta clase"
    }
}

private struct ClassLinkedObjectiveRow: View {
    let linkedObjective: ClassLinkedObjective
    let onShowIndicators: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(objectiveLabel)
                .font(.caption.weight(.black))
                .foregroundStyle(EPTheme.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(EPTheme.primary.opacity(0.12), in: Capsule())

            Text(linkedObjective.objective.descripcion)
                .font(.subheadline)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onShowIndicators) {
                HStack(spacing: 7) {
                    Image(systemName: "list.bullet.clipboard")
                    Text(indicatorText)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(EPTheme.primary)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .classInteractiveGlass(shape: .roundedRectangle)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre todos los indicadores vinculados a este objetivo")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var objectiveLabel: String {
        if let number = linkedObjective.objective.numero { return "OA \(number)" }
        let digits = linkedObjective.objective.id.filter(\.isNumber)
        return digits.isEmpty ? linkedObjective.objective.id.uppercased() : "OA \(digits)"
    }

    private var indicatorText: String {
        let count = linkedObjective.indicators.count
        return count == 1 ? "Ver 1 indicador" : "Ver \(count) indicadores"
    }
}

struct ClassContextAdaptationSection: View {
    let teacherContextHTML: String
    let adaptationHTML: String

    var body: some View {
        if hasContent {
            EPCollapsibleSection(
                title: "Contexto y adecuación",
                subtitle: "Notas y apoyos PIE/DUA.",
                icon: "person.text.rectangle"
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    if !plainText(teacherContextHTML).isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Contexto de la clase")
                                .font(.subheadline.weight(.bold))
                            RichTextRenderer(html: teacherContextHTML)
                        }
                    }
                    if !plainText(adaptationHTML).isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Adecuación curricular")
                                .font(.subheadline.weight(.bold))
                            RichTextRenderer(html: adaptationHTML)
                        }
                    }
                }
            }
        }
    }

    private var hasContent: Bool {
        !plainText(teacherContextHTML).isEmpty || !plainText(adaptationHTML).isEmpty
    }

    private func plainText(_ html: String) -> String {
        RichTextHTML.plainText(from: html)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ClassEmptyPlanCard: View {
    let classNumber: Int
    let isDisabled: Bool
    let onPlan: () -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(spacing: 13) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Esta clase aún no está planificada")
                    .font(.headline.weight(.black))
                Text("Define el objetivo, los momentos de la sesión y sus recursos directamente desde tu iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: onPlan) {
                    Label("Planificar esta clase", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(isDisabled)
                .accessibilityIdentifier("planificar-clase-\(classNumber)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

struct ClassActivityLoadingCard: View {
    var body: some View {
        UnitSectionSurface {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Recuperando planificaciones…")
                    .font(.headline.weight(.bold))
                Text("La edición se habilitará cuando termine la carga.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }
}

struct ClassActivityLoadErrorCard: View {
    let classNumber: Int
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.orange)
                Text("No pudimos cargar esta planificación")
                    .font(.headline.weight(.black))
                Text("Para proteger lo que ya existe, la edición queda bloqueada hasta recuperar la clase.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Reintentar", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(EPTheme.primary)
                    .disabled(isRetrying)
                    .accessibilityIdentifier("reintentar-carga-clase-\(classNumber)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

extension ActividadClase {
    var classStatusLabel: String {
        switch estado {
        case "planificada": return "Planificada"
        case "realizada": return "Realizada"
        case "no_planificada": return "No planificada"
        default: return estado.isEmpty ? "No planificada" : estado.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var classStatusTint: Color {
        switch estado {
        case "planificada": return .green
        case "realizada": return .blue
        case "no_planificada": return .orange
        default: return .secondary
        }
    }
}

private enum ClassInteractiveShape {
    case circle
    case capsule
    case roundedRectangle
}

private extension View {
    @ViewBuilder
    func classInteractiveGlass(shape: ClassInteractiveShape) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            switch shape {
            case .circle:
                glassEffect(.regular.tint(EPTheme.primary.opacity(0.12)).interactive(), in: .circle)
            case .capsule:
                glassEffect(.regular.tint(EPTheme.primary.opacity(0.12)).interactive(), in: .capsule)
            case .roundedRectangle:
                glassEffect(.regular.tint(EPTheme.primary.opacity(0.12)).interactive(), in: .rect(cornerRadius: 14))
            }
        } else {
            classMaterialFallback(shape: shape)
        }
#else
        classMaterialFallback(shape: shape)
#endif
    }

    @ViewBuilder
    func classMaterialFallback(shape: ClassInteractiveShape) -> some View {
        switch shape {
        case .circle:
            background(.regularMaterial, in: Circle())
        case .capsule:
            background(EPTheme.primary.opacity(0.1), in: Capsule())
        case .roundedRectangle:
            background(EPTheme.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
