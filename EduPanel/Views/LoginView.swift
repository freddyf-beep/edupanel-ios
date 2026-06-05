import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var authSession

    var body: some View {
        @Bindable var session = authSession

        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                VStack(spacing: 14) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

                    Text("EduPanel")
                        .font(.largeTitle.bold())

                    Text("Gestiona tu jornada docente, planificaciones y evaluaciones desde una app nativa.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 14) {
                    switch authSession.state {
                    case .blocked(let user):
                        blockedAccessCard(user: user, session: $session)
                    default:
                        signInCard
                    }

                    if let error = authSession.errorMessage, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(18)
                .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 22, y: 10)

                Text("Al iniciar sesion aceptas los terminos y politicas configuradas para EduPanel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("Build: Sidebar v1.0.18-d3e1596")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.pink)
                    .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Iniciar sesion")
                .font(.headline)

            Button {
                Task { await authSession.signInWithGoogle() }
            } label: {
                HStack {
                    if authSession.isSigningIn {
                        ProgressView()
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    Text(authSession.isSigningIn ? "Conectando..." : "Continuar con Google")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .disabled(authSession.isSigningIn)
        }
    }

    private func blockedAccessCard(user: AuthenticatedUser, session: Bindable<AuthSession>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Acceso por invitacion", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(user.email ?? "Sesion actual")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Tu cuenta inicio sesion correctamente, pero aun no esta autorizada para entrar a EduPanel.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Codigo de invitacion", text: session.inviteCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.weight(.semibold))
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task { await authSession.redeemInvite() }
            } label: {
                HStack {
                    if authSession.isRedeeming {
                        ProgressView()
                    } else {
                        Image(systemName: "key.fill")
                    }
                    Text(authSession.isRedeeming ? "Canjeando..." : "Canjear codigo")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(authSession.isRedeemingOrCodeEmpty)

            Button("Cambiar cuenta") {
                Task { await authSession.signOut() }
            }
            .font(.footnote.weight(.semibold))
        }
    }
}

private extension AuthSession {
    var isRedeemingOrCodeEmpty: Bool {
        isRedeeming || inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
