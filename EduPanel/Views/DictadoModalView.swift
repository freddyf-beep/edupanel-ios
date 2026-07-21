import SwiftUI
import UniformTypeIdentifiers

struct DictadoModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var dictadoService: DictadoService
    @State private var copiedNotice = false

    init(contextualStrings: [String] = []) {
        _dictadoService = State(initialValue: DictadoService(contextualStrings: contextualStrings))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header description
                VStack(spacing: 4) {
                    Text("Dictado por Voz")
                        .font(.title2.weight(.black))
                    Text("Habla libremente y EduPanel transcribirá tus notas docentes en tiempo real.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 10)

                // Transcribed Text Display Box
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(dictadoService.state.isRecording ? EPTheme.primary.opacity(0.4) : Color(.separator).opacity(0.15), lineWidth: dictadoService.state.isRecording ? 1.8 : 1)
                        )

                    TextEditor(text: Binding(
                        get: { dictadoService.transcribedText },
                        set: { dictadoService.updateText($0) }
                    ))
                    .font(.body.weight(.medium))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .accessibilityLabel("Texto dictado editable")

                    if dictadoService.transcribedText.isEmpty {
                        Text(dictadoService.state.isRecording ? "Escuchando… habla claramente." : "Toca el micrófono para comenzar a dictar…")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .italic()
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxHeight: .infinity)

                // Status & Waveform Animation
                VStack(spacing: 12) {
                    if case .error(let message) = dictadoService.state {
                        VStack(spacing: 6) {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                            Button("Abrir Ajustes") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .font(.caption.weight(.bold))
                        }
                    } else if dictadoService.state.isRecording {
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { i in
                                Capsule()
                                    .fill(EPTheme.primary)
                                    .frame(width: 4, height: max(8, CGFloat(dictadoService.audioLevel * Float(15 + (i % 3) * 10))))
                                    .animation(.easeOut(duration: 0.15), value: dictadoService.audioLevel)
                            }
                        }
                        .frame(height: 32)

                        Text("GRABANDO...")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(EPTheme.primary)
                    }

                    // Main Microphone Control Button
                    Button {
                        withAnimation(EPTheme.spring) {
                            dictadoService.toggleDictado()
                        }
                    } label: {
                        ZStack {
                            if dictadoService.state.isRecording {
                                Circle()
                                    .fill(EPTheme.primary.opacity(0.25))
                                    .frame(width: 86, height: 86)
                                    .scaleEffect(1.0 + CGFloat(dictadoService.audioLevel * 0.3))
                                    .animation(.easeInOut(duration: 0.2), value: dictadoService.audioLevel)
                            }

                            Circle()
                                .fill(dictadoService.state.isRecording ? EPTheme.primary : Color(.secondarySystemGroupedBackground))
                                .frame(width: 72, height: 72)
                                .shadow(color: dictadoService.state.isRecording ? EPTheme.primary.opacity(0.4) : .black.opacity(0.1), radius: 10, y: 4)

                            Image(systemName: dictadoService.state.isRecording ? "stop.fill" : "mic.fill")
                                .font(.title.weight(.bold))
                                .foregroundStyle(dictadoService.state.isRecording ? .white : EPTheme.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(dictadoService.state == .requestingPermission)
                    .sensoryFeedback(.impact, trigger: dictadoService.state.isRecording)

                    if dictadoService.state == .requestingPermission {
                        ProgressView("Solicitando permisos…")
                            .font(.caption)
                    }

                    Label(dictadoService.privacyDescription, systemImage: "hand.raised.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Action Bar (Copiar, Limpiar, Cerrar)
                HStack(spacing: 12) {
                    Button {
                        dictadoService.clearText()
                    } label: {
                        Label("Limpiar", systemImage: "trash")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(dictadoService.transcribedText.isEmpty)

                    Button {
                        UIPasteboard.general.string = dictadoService.transcribedText
                        withAnimation {
                            copiedNotice = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedNotice = false
                        }
                    } label: {
                        Label(copiedNotice ? "¡Copiado!" : "Copiar", systemImage: copiedNotice ? "checkmark" : "doc.on.doc")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(copiedNotice ? .green : EPTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(dictadoService.transcribedText.isEmpty)
                }
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 18)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dictadoService.stopDictado()
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                }
            }
        }
        .onDisappear { dictadoService.stopDictado() }
    }
}
