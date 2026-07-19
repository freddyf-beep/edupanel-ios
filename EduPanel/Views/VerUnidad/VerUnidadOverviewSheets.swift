import SwiftUI

struct UnitContextEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var teacherContext: String
    @Binding var teacherGoal: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Esta información adapta la unidad a la realidad de tu curso. El propósito curricular se mantiene sin cambios.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    RichTextEditor(
                        title: "Contexto del profesor",
                        placeholder: "Características del curso, ritmos, intereses o necesidades que conviene considerar.",
                        html: $teacherContext,
                        minHeight: 130
                    )

                    RichTextEditor(
                        title: "Meta pedagógica del docente",
                        placeholder: "La meta propia que quieres alcanzar con esta unidad.",
                        html: $teacherGoal,
                        minHeight: 130
                    )

                    Label("Los cambios quedarán pendientes hasta guardar la unidad.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Contexto y meta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo", action: dismiss.callAsFunction)
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct UnitIndicatorsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let objective: OAEditado

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    UnitIndicatorsObjectiveHeader(
                        label: objectiveLabel,
                        description: objective.descripcion
                    )

                    if objective.indicadores.isEmpty {
                        UnitEmptyMessage(
                            text: "Este objetivo no tiene indicadores registrados.",
                            symbol: "list.bullet.clipboard"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(indicatorSummary)
                                .font(.subheadline.weight(.bold))

                            ForEach(objective.indicadores) { indicator in
                                UnitIndicatorReadOnlyRow(indicator: indicator)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Indicadores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar", action: dismiss.callAsFunction)
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var objectiveLabel: String {
        objective.numero.map { "OBJETIVO DE APRENDIZAJE \($0)" } ?? "OBJETIVO DE APRENDIZAJE"
    }

    private var indicatorSummary: String {
        let selected = objective.indicadores.filter(\.seleccionado).count
        return "\(selected) de \(objective.indicadores.count) seleccionados"
    }
}

private struct UnitIndicatorsObjectiveHeader: View {
    let label: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(EPTheme.primary)
            Text(description)
                .font(.headline)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(EPTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct UnitIndicatorReadOnlyRow: View {
    let indicator: IndicadorEditado

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: indicator.seleccionado ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(indicator.seleccionado ? EPTheme.primary : Color.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(indicator.texto)
                .font(.subheadline)
                .foregroundStyle(indicator.seleccionado ? Color.primary : Color.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(indicator.seleccionado ? "Seleccionado" : "No seleccionado")
    }
}
