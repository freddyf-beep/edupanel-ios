import SwiftUI

struct SettingsInfoSection: View {
    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Información", icon: "info.circle.fill", hint: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsRow(icon: "app.badge.fill", title: "Versión de la app", subtitle: nil, tint: EPTheme.primary) {
                        Text(versionLabel)
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                    }

                    enlace(icon: "doc.text.fill", title: "Términos de uso", url: "https://edupanel.cl/terminos", tint: .blue)
                    enlace(icon: "hand.raised.fill", title: "Política de privacidad", url: "https://edupanel.cl/terminos", tint: .purple)
                }
            }

            ProfileSection(title: "Soporte", icon: "lifepreserver.fill", hint: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    enlace(
                        icon: "envelope.fill",
                        title: "Enviar feedback",
                        url: "mailto:soporte@edupanel.cl?subject=Feedback%20EduPanel%20iOS",
                        tint: .green
                    )
                    enlace(
                        icon: "exclamationmark.bubble.fill",
                        title: "Reportar un problema",
                        url: "mailto:soporte@edupanel.cl?subject=Problema%20EduPanel%20iOS%20\(versionLabel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
                        tint: .orange
                    )
                }
            }
        }
    }

    private func enlace(icon: String, title: String, url: String, tint: Color) -> some View {
        Group {
            if let destino = URL(string: url) {
                Link(destination: destino) {
                    SettingsRow(icon: icon, title: title, subtitle: nil, tint: tint) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
