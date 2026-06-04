import SwiftUI

struct RootView: View {
    @Environment(AuthSession.self) private var authSession

    var body: some View {
        Group {
            switch authSession.state {
            case .checking:
                LaunchLoadingView()
            case .configurationError(let message):
                ConfigurationErrorView(message: message)
            case .signedOut, .blocked:
                LoginView()
            case .signedIn(let user):
                if let repository = authSession.dashboardRepository {
                    AppShell(user: user, dashboardRepository: repository)
                } else {
                    ConfigurationErrorView(message: "La conexion de datos no esta disponible.")
                }
            }
        }
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            ProgressView()
                .controlSize(.regular)

            Text("Cargando EduPanel...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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

