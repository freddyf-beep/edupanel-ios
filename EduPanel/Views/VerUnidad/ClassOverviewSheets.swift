import SwiftUI
import WebKit

enum ClassOverviewSheet: Identifiable {
    case editor(Int)
    case reading(ClassReadingSheetData)
    case indicators(ClassIndicatorsSheetData)
    case list(ClassTextListSheetData)
    case advanced(ActividadClase)

    var id: String {
        switch self {
        case .editor(let classNumber): return "editor-\(classNumber)"
        case .reading(let data): return "reading-\(data.id)"
        case .indicators(let data): return "indicators-\(data.id)"
        case .list(let data): return "list-\(data.id)"
        case .advanced(let activity): return "advanced-\(activity.id)"
        }
    }
}

struct ClassReadingSheetData: Identifiable {
    let id = UUID()
    let title: String
    let html: String
    let symbol: String
}

struct ClassIndicatorsSheetData: Identifiable {
    let objective: OAEditado
    let indicators: [IndicadorEditado]

    var id: String { objective.id }
}

struct ClassTextListSheetData: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let items: [String]
}

struct ClassReadingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let data: ClassReadingSheetData

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Label(data.title, systemImage: data.symbol)
                        .font(.headline.weight(.black))
                        .foregroundStyle(EPTheme.primary)
                    RichTextRenderer(html: data.html)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(data.title)
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
}

struct ClassIndicatorsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let data: ClassIndicatorsSheetData

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ClassIndicatorObjectiveHeader(objective: data.objective)

                    if data.indicators.isEmpty {
                        UnitEmptyMessage(
                            text: "Esta clase no tiene indicadores vinculados a este objetivo.",
                            symbol: "list.bullet.clipboard"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(indicatorCountText)
                                .font(.subheadline.weight(.bold))
                            ForEach(data.indicators) { indicator in
                                ClassIndicatorFullRow(indicator: indicator)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Indicadores de la clase")
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

    private var indicatorCountText: String {
        data.indicators.count == 1 ? "1 indicador vinculado" : "\(data.indicators.count) indicadores vinculados"
    }
}

private struct ClassIndicatorObjectiveHeader: View {
    let objective: OAEditado

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(EPTheme.primary)
            Text(objective.descripcion)
                .font(.headline)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(EPTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var label: String {
        if let number = objective.numero { return "OBJETIVO DE APRENDIZAJE \(number)" }
        let digits = objective.id.filter(\.isNumber)
        return digits.isEmpty ? "OBJETIVO DE APRENDIZAJE" : "OBJETIVO DE APRENDIZAJE \(digits)"
    }
}

private struct ClassIndicatorFullRow: View {
    let indicator: IndicadorEditado

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(EPTheme.primary)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(indicator.texto)
                .font(.subheadline)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ClassTextListSheet: View {
    @Environment(\.dismiss) private var dismiss

    let data: ClassTextListSheetData

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(data.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: data.symbol)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(EPTheme.primary)
                                .frame(width: 27, height: 27)
                                .background(EPTheme.primary.opacity(0.1), in: Circle())
                                .accessibilityHidden(true)
                            Text(item)
                                .font(.subheadline)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(data.title)
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
}

enum ClassAdvancedPedagogyContent {
    static func hasData(_ activity: ActividadClase) -> Bool {
        if let objective = activity.objetivoMultinivel,
           [objective.basico, objective.intermedio, objective.avanzado, objective.recomendado]
            .contains(where: hasText) {
            return true
        }
        if !(activity.analisisBloom ?? []).isEmpty { return true }
        if !(activity.indicadoresEvaluacion ?? []).isEmpty { return true }
        if let evaluation = activity.actividadEvaluacion,
           [evaluation.tipo, evaluation.descripcion, evaluation.instrumento].contains(where: hasText) ||
            !(evaluation.criterios ?? []).isEmpty || !(evaluation.alineacionMBE ?? []).isEmpty {
            return true
        }
        if let development = activity.desarrolloFormal,
           [development.inicio, development.desarrollo, development.cierre].contains(where: hasText) {
            return true
        }
        return false
    }

    private static func hasText(_ value: String?) -> Bool {
        !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ClassAdvancedPedagogySheet: View {
    @Environment(\.dismiss) private var dismiss

    let activity: ActividadClase

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let objective = activity.objetivoMultinivel {
                        ClassMultilevelSection(objective: objective)
                    }
                    if let bloom = activity.analisisBloom, !bloom.isEmpty {
                        ClassBloomSection(items: bloom)
                    }
                    if let indicators = activity.indicadoresEvaluacion, !indicators.isEmpty {
                        ClassEvaluationIndicatorsSection(indicators: indicators)
                    }
                    if let evaluation = activity.actividadEvaluacion {
                        ClassEvaluationActivitySection(evaluation: evaluation)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Datos pedagógicos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar", action: dismiss.callAsFunction)
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ClassMultilevelSection: View {
    let objective: ObjetivoMultinivel

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 12) {
                UnitSectionHeader(title: "Objetivo multinivel", subtitle: nil, symbol: "chart.bar.doc.horizontal")
                AdvancedTextBlock(label: "Básico", value: objective.basico, tint: .green)
                AdvancedTextBlock(label: "Intermedio", value: objective.intermedio, tint: .blue)
                AdvancedTextBlock(label: "Avanzado", value: objective.avanzado, tint: .purple)
                AdvancedTextBlock(label: "Recomendado", value: objective.recomendado, tint: EPTheme.primary)
            }
        }
    }
}

private struct ClassBloomSection: View {
    let items: [AnalisisBloom]

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 12) {
                UnitSectionHeader(title: "Análisis Bloom", subtitle: nil, symbol: "brain.head.profile", tint: .indigo)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            EPStatusPill(text: item.oaId ?? "OA", icon: "tag.fill", tint: .blue)
                            EPStatusPill(text: item.nivel ?? "Nivel", tint: .purple)
                        }
                        if let justification = item.justificacion, !justification.isEmpty {
                            Text(justification)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

private struct ClassEvaluationIndicatorsSection: View {
    let indicators: [IndicadorEvaluacion]

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 10) {
                UnitSectionHeader(title: "Indicadores de evaluación", subtitle: nil, symbol: "checklist")
                ForEach(indicators) { indicator in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: indicator.seleccionado == false ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(indicator.seleccionado == false ? Color.secondary : EPTheme.primary)
                        Text(indicator.texto)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct ClassEvaluationActivitySection: View {
    let evaluation: ActividadEvaluacion

    var body: some View {
        UnitSectionSurface {
            VStack(alignment: .leading, spacing: 12) {
                UnitSectionHeader(title: "Actividad de evaluación", subtitle: nil, symbol: "checkmark.seal.fill", tint: .orange)
                AdvancedTextBlock(label: "Tipo", value: evaluation.tipo, tint: .orange)
                AdvancedTextBlock(label: "Instrumento", value: evaluation.instrumento, tint: .purple)
                if let description = evaluation.descripcion, !description.isEmpty {
                    RichTextRenderer(html: description)
                }
            }
        }
    }
}

private struct AdvancedTextBlock: View {
    let label: String
    let value: String?
    let tint: Color

    var body: some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                EPStatusPill(text: label, tint: tint)
                RichTextRenderer(html: value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ClassDrivePreview: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let externalURL: URL?
}

struct ClassDrivePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let preview: ClassDrivePreview

    var body: some View {
        NavigationStack {
            ClassDriveWebView(url: preview.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(preview.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    if let externalURL = preview.externalURL {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                openURL(externalURL)
                            } label: {
                                Label("Abrir en Drive", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ClassDriveWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
