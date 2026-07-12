import SwiftUI

struct EvaluacionesWordShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artifact: EvaluacionesWordArtifact

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(EPTheme.primary)
                Text(artifact.url.lastPathComponent)
                    .font(.headline.weight(.black))
                    .multilineTextAlignment(.center)
                Text("Documento Word listo para compartir, guardar o abrir en una aplicación compatible.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: artifact.url) {
                    Label("Compartir o guardar Word", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Exportación Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
            }
        }
    }
}
