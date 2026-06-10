import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var authSession

    var body: some View {
        @Bindable var session = authSession

        ZStack {
            background

            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 48)

                    VStack(spacing: 16) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: EPTheme.primary.opacity(0.25), radius: 22, y: 10)

                        Text("EduPanel")
                            .font(.system(size: 34, weight: .black, design: .rounded))

                        Text("Gestiona tu jornada docente, planificaciones y evaluaciones desde una app nativa.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color(.separator).opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 24, y: 12)

                    Text("Al iniciar sesión aceptas los términos y políticas configuradas para EduPanel.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text("Build: Sidebar v1.0.18-d3e1596")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(EPTheme.primary.opacity(0.6))

                    Spacer(minLength: 24)
                }
                .padding(20)
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)

            Circle()
                .fill(EPTheme.primary.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -130, y: -260)

            Circle()
                .fill(EPTheme.fuchsia.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: 150, y: 240)
        }
        .ignoresSafeArea()
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Iniciar sesión")
                .font(.system(size: 17, weight: .black))

            Button {
                Task { await authSession.signInWithGoogle() }
            } label: {
                HStack(spacing: 9) {
                    if authSession.isSigningIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(authSession.isSigningIn ? "Conectando…" : "Continuar con Google")
                        .font(.system(size: 15, weight: .black))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: EPTheme.primary.opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(authSession.isSigningIn)
            .opacity(authSession.isSigningIn ? 0.75 : 1)
            .sensoryFeedback(.impact(weight: .medium), trigger: authSession.isSigningIn)
        }
    }

    private func blockedAccessCard(user: AuthenticatedUser, session: Bindable<AuthSession>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Acceso por invitación", systemImage: "lock.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.orange)

            Text(user.email ?? "Sesión actual")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.systemGray6), in: Capsule())

            Text("Tu cuenta inició sesión correctamente, pero aún no está autorizada para entrar a EduPanel.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Código de invitación", text: session.inviteCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .bold))
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )

            Button {
                Task { await authSession.redeemInvite() }
            } label: {
                HStack(spacing: 9) {
                    if authSession.isRedeeming {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(authSession.isRedeeming ? "Canjeando…" : "Canjear código")
                        .font(.system(size: 15, weight: .black))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .orange.opacity(0.25), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(authSession.isRedeemingOrCodeEmpty)
            .opacity(authSession.isRedeemingOrCodeEmpty ? 0.5 : 1)

            Button("Cambiar cuenta") {
                Task { await authSession.signOut() }
            }
            .font(.system(size: 12, weight: .bold))
            .tint(EPTheme.primary)
        }
    }
}

private extension AuthSession {
    var isRedeemingOrCodeEmpty: Bool {
        isRedeeming || inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
