import SwiftUI

struct SettingsAccountSection: View {
    @Environment(AuthSession.self) private var authSession
    let user: AuthenticatedUser

    @State private var confirmandoCierre = false

    var body: some View {
        ProfileSection(title: "Cuenta", icon: "person.crop.circle.fill", hint: "Google") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AsyncUserAvatar(user: user)
                        .scaleEffect(0.75)
                        .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName ?? "Profesor EduPanel")
                            .font(.footnote.weight(.black))
                            .lineLimit(1)
                        Text(user.email ?? "Sin correo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(role: .destructive) {
                    confirmandoCierre = true
                } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .confirmationDialog("¿Cerrar la sesión de \(user.email ?? "tu cuenta")?", isPresented: $confirmandoCierre, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) {
                Task { await authSession.signOut() }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}
