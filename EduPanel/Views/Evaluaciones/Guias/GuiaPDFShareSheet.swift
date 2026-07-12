import SwiftUI
import PDFKit
import UIKit

struct GuiaPDFExportActions: View {
    let templates: [ExportFormatTemplate]
    let action: (GuiaPDFMode, ExportFormat?) -> Void

    @ViewBuilder
    var body: some View {
        ForEach(GuiaPDFMode.allCases) { mode in
            if templates.isEmpty {
                Button(mode.title, systemImage: icon(mode)) { action(mode, nil) }
            } else {
                Menu(mode.title, systemImage: icon(mode)) {
                    Button("Formato predeterminado", systemImage: "star.fill") { action(mode, nil) }
                    Divider()
                    ForEach(templates) { template in
                        Button(template.name) { action(mode, template.format) }
                    }
                }
            }
        }
    }

    private func icon(_ mode: GuiaPDFMode) -> String {
        mode == .pauta ? "checkmark.seal.fill" : "person.fill"
    }
}

struct GuiaPDFShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artifact: GuiaPDFArtifact

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                GuiaPDFPreview(url: artifact.url)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(EPTheme.border))

                if artifact.omittedImageCount > 0 {
                    Label(
                        "\(artifact.omittedImageCount) imagen(es) no pudieron incrustarse y aparecen como espacio no disponible.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                ShareLink(item: artifact.url) {
                    Label("Compartir o guardar PDF", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.black)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 12))
                }

                Button(action: printPDF) {
                    Label("Imprimir", systemImage: "printer.fill")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(EPTheme.background)
            .navigationTitle(artifact.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func printPDF() {
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = artifact.title
        controller.printInfo = printInfo
        controller.printingItem = artifact.url
        controller.present(animated: true)
    }
}

private struct GuiaPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
