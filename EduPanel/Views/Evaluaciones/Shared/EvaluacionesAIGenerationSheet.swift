import SwiftUI

struct EvaluacionesAIGenerationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let explanation: String
    let initialInstructions: String
    let generate: (String) async throws -> Void

    @State private var instructions: String
    @State private var isGenerating = false
    @State private var errorMessage: String?

    init(
        title: String,
        explanation: String,
        initialInstructions: String,
        generate: @escaping (String) async throws -> Void
    ) {
        self.title = title
        self.explanation = explanation
        self.initialInstructions = initialInstructions
        self.generate = generate
        _instructions = State(initialValue: initialInstructions)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(explanation, systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Section("Indicaciones") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 180)
                        .disabled(isGenerating)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        Task { await runGeneration() }
                    } label: {
                        HStack {
                            if isGenerating { ProgressView() }
                            Label(isGenerating ? "Generando…" : "Generar contenido", systemImage: "wand.and.stars")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isGenerating || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("El contenido se agrega al borrador para que puedas revisarlo antes de guardar.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isGenerating)
                }
            }
        }
        .interactiveDismissDisabled(isGenerating)
    }

    @MainActor
    private func runGeneration() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            try await generate(instructions.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
