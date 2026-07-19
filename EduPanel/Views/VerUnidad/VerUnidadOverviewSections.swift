import SwiftUI

struct UnitSectionSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
            }
    }
}

struct UnitSectionHeader: View {
    let title: String
    let subtitle: String?
    let symbol: String
    var tint: Color = EPTheme.primary

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct UnitStatusCard: View {
    let dateRange: String
    let hours: Int
    let classes: Int

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 15) {
                UnitSectionHeader(
                    title: "Estado de la unidad",
                    subtitle: "Fechas y carga de trabajo",
                    symbol: "calendar.badge.clock"
                )

                Label(dateRange, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(dateRange == "Sin fechas asignadas" ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                HStack(spacing: 10) {
                    UnitStatusMetric(value: "\(hours)", label: "horas", symbol: "clock")
                    UnitStatusMetric(value: "\(classes)", label: "clases", symbol: "text.book.closed")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estado de la unidad. \(dateRange). \(hours) horas. \(classes) clases.")
    }
}

private struct UnitStatusMetric: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(EPTheme.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct UnitPlanCard: View {
    let purposeHTML: String
    let hasTeacherContext: Bool
    let hasTeacherGoal: Bool
    let onOpenContext: () -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 16) {
                UnitSectionHeader(
                    title: "Plan de unidad",
                    subtitle: "La intención curricular que orienta toda la planificación",
                    symbol: "book.pages.fill"
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("PROPÓSITO CURRICULAR")
                        .font(.caption2.weight(.black))
                        .tracking(0.7)
                        .foregroundStyle(EPTheme.primary)

                    if RichTextHTML.plainText(from: purposeHTML).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Esta unidad todavía no tiene un propósito curricular definido.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        RichTextRenderer(html: purposeHTML)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(EPTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(EPTheme.primary)
                        .frame(width: 4)
                        .padding(.vertical, 12)
                }

                Button(action: onOpenContext) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.text.rectangle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(EPTheme.primary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Contexto y meta docente")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(completionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(13)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .unitInteractiveSurface(tint: EPTheme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre una ventana para completar el contexto del curso y la meta pedagógica")
                .accessibilityIdentifier("editar-contexto-meta-unidad")
            }
        }
    }

    private var completionText: String {
        let completed = [hasTeacherContext, hasTeacherGoal].filter { $0 }.count
        switch completed {
        case 2: return "Contexto y meta completados"
        case 1: return "1 de 2 campos completados"
        default: return "Agrega información propia de este curso"
        }
    }
}

struct UnitObjectivesCard: View {
    let objectives: [OAEditado]
    let onShowIndicators: (OAEditado) -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 14) {
                UnitSectionHeader(
                    title: "Objetivos de Aprendizaje",
                    subtitle: objectiveSummary,
                    symbol: "target"
                )

                if objectives.isEmpty {
                    UnitEmptyMessage(
                        text: "No hay objetivos seleccionados para esta unidad.",
                        symbol: "target"
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(objectives) { objective in
                            UnitObjectiveRow(
                                objective: objective,
                                onShowIndicators: { onShowIndicators(objective) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var objectiveSummary: String {
        objectives.count == 1 ? "1 objetivo seleccionado" : "\(objectives.count) objetivos seleccionados"
    }
}

private struct UnitObjectiveRow: View {
    let objective: OAEditado
    let onShowIndicators: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.black))
                    .foregroundStyle(EPTheme.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(EPTheme.primary.opacity(0.12), in: Capsule())

                if objective.esPropio == true {
                    Text("Propio")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.purple)
                }
            }

            Text(objective.descripcion)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onShowIndicators) {
                HStack(spacing: 7) {
                    Image(systemName: "list.bullet.clipboard")
                    Text(indicatorButtonTitle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(EPTheme.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .unitInteractiveSurface(tint: EPTheme.primary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre una ventana con los indicadores de este objetivo")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var label: String {
        objective.numero.map { "OA \($0)" } ?? (objective.esPropio == true ? "OBJETIVO PROPIO" : "OA")
    }

    private var indicatorButtonTitle: String {
        let count = objective.indicadores.count
        return count == 1 ? "Ver 1 indicador" : "Ver \(count) indicadores"
    }
}

struct UnitRouteItem: Identifiable {
    let id: String
    let category: String
    let text: String
    let symbol: String
}

struct UnitLearningRouteCard: View {
    let attitudes: [UnitRouteItem]
    let skills: [ElementoCurricular]
    let knowledge: [ElementoCurricular]
    @Binding var showsSupportingCurriculum: Bool

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 15) {
                UnitSectionHeader(
                    title: "Ruta de trabajo",
                    subtitle: "Actitudes y objetivos transversales que acompañan la unidad",
                    symbol: "point.topleft.down.to.point.bottomright.curvepath",
                    tint: .red
                )

                VStack(alignment: .leading, spacing: 9) {
                    Text("ACTITUDES Y OAA")
                        .font(.caption2.weight(.black))
                        .tracking(0.7)
                        .foregroundStyle(.red)

                    if attitudes.isEmpty {
                        UnitEmptyMessage(
                            text: "No hay actitudes ni OAA seleccionados.",
                            symbol: "heart"
                        )
                    } else {
                        ForEach(attitudes) { item in
                            UnitAttitudeRow(item: item)
                        }
                    }
                }

                Button(action: toggleSupportingCurriculum) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(.blue)
                        Text(showsSupportingCurriculum ? "Ocultar habilidades y conocimientos" : "Ver habilidades y conocimientos")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsSupportingCurriculum ? 180 : 0))
                    }
                    .padding(13)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .unitInteractiveSurface(tint: .blue)
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsSupportingCurriculum ? "Mostrados" : "Ocultos")
                .accessibilityIdentifier("alternar-habilidades-conocimientos")

                if showsSupportingCurriculum {
                    VStack(spacing: 14) {
                        UnitSupportingList(
                            title: "Habilidades",
                            symbol: "figure.mind.and.body",
                            tint: .blue,
                            items: skills.map(\.texto)
                        )
                        UnitSupportingList(
                            title: "Conocimientos",
                            symbol: "books.vertical.fill",
                            tint: .orange,
                            items: knowledge.map(\.texto)
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func toggleSupportingCurriculum() {
        withAnimation(EPTheme.spring) {
            showsSupportingCurriculum.toggle()
        }
    }
}

private struct UnitAttitudeRow: View {
    let item: UnitRouteItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: item.symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .background(Color.red.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.category.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(.red)
                Text(item.text)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct UnitSupportingList: View {
    let title: String
    let symbol: String
    let tint: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)

            if items.isEmpty {
                Text("Sin elementos seleccionados.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                        Text(item)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct UnitMaterialsCard: View {
    let files: [ArchivoAdjunto]
    @Binding var resources: [String]
    @Binding var newResource: String
    let onAddResource: () -> Void

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 14) {
                UnitSectionHeader(
                    title: "Materiales de la unidad",
                    subtitle: "Recursos que necesitarás durante las clases",
                    symbol: "shippingbox.fill",
                    tint: .purple
                )

                if files.isEmpty && resources.isEmpty {
                    UnitEmptyMessage(
                        text: "Todavía no hay materiales registrados.",
                        symbol: "shippingbox"
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(files) { file in
                            UnitMaterialFileRow(file: file)
                        }
                        ForEach(resources, id: \.self) { resource in
                            UnitDeclaredResourceRow(
                                resource: resource,
                                onRemove: { remove(resource) }
                            )
                        }
                    }
                }

                HStack(spacing: 9) {
                    TextField("Agregar un material", text: $newResource)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                        .onSubmit(onAddResource)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    Button(action: onAddResource) {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                            .unitInteractiveSurface(tint: .purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(newResource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Agregar material")
                }
            }
        }
    }

    private func remove(_ resource: String) {
        withAnimation(EPTheme.spring) {
            resources.removeAll { $0 == resource }
        }
    }
}

private struct UnitMaterialFileRow: View {
    let file: ArchivoAdjunto

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: file.provider == "drive" ? "externaldrive.fill" : "paperclip")
                .font(.body.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)
                .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.nombre)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(fileSize(file.tamano))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(11)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func fileSize(_ bytes: Double?) -> String {
        guard var size = bytes, size > 0 else { return "Archivo adjunto" }
        let units = ["B", "KB", "MB", "GB"]
        var unit = 0
        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        return "\(String(format: unit == 0 ? "%.0f" : "%.1f", size)) \(units[unit])"
    }
}

private struct UnitDeclaredResourceRow: View {
    let resource: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(resource)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eliminar \(resource)")
        }
        .padding(11)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct UnitEmptyMessage: View {
    let text: String
    let symbol: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    @ViewBuilder
    func unitInteractiveSurface(tint: Color) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint.opacity(0.16)).interactive(), in: .rect(cornerRadius: 14))
        } else {
            background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
#else
        background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
#endif
    }
}
