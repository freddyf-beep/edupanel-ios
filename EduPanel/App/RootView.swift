import SwiftUI

struct RootView: View {
    @Environment(AuthSession.self) private var authSession

    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-attendance-preview") {
            NavigationStack {
                AttendanceView(
                    previewModel: AttendanceViewModel.preview(
                        isSigned: ProcessInfo.processInfo.arguments.contains("-attendance-signed"),
                        allConfirmed: ProcessInfo.processInfo.arguments.contains("-attendance-confirmed")
                    ),
                    startsWithQRScanner: ProcessInfo.processInfo.arguments.contains("-attendance-qr-preview")
                )
            }
        } else {
            authenticatedContent
        }
#else
        authenticatedContent
#endif
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        Group {
            switch authSession.state {
            case .checking:
                LaunchLoadingView()
            case .configurationError(let message):
                ConfigurationErrorView(message: message)
            case .signedOut, .blocked, .authorizationUnavailable:
                LoginView()
            case .signedIn(let user):
                if let repository = authSession.dashboardRepository {
                    AppShell(user: user, dashboardRepository: repository)
                } else {
                    ConfigurationErrorView(message: "La conexion de datos no esta disponible.")
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: authSession.state)
    }
}

private struct LaunchLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(EPTheme.primary.opacity(0.12), lineWidth: 7)
                    .frame(width: 116, height: 116)

                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(
                        EPTheme.heroGradient,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .frame(width: 116, height: 116)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 360 : 0)))

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .shadow(color: EPTheme.primary.opacity(0.22), radius: 14, y: 6)
                    .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.04 : 0.96))
            }
            .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Preparando tu jornada")
                    .font(.headline.weight(.black))

                Text("Estamos comprobando tu sesión de forma segura.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparando EduPanel y comprobando tu sesión")
        .task {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

private struct ConfigurationErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Falta configuracion")
                .font(.title2.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Revisa README.md, GoogleService-Info.plist y Config/Shared.xcconfig.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(.systemGroupedBackground))
    }
}
