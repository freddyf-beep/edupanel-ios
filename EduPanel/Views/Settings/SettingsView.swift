import SwiftUI

struct SettingsView: View {
    let user: AuthenticatedUser
    let repository: DashboardRepository

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsAppearanceSection()
                if !displayMode.isSimple {
                    SettingsTabBarSection()
                }
                SettingsAccountSection(user: user)
                SettingsDataSection(repository: repository)
                SettingsInfoSection()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .tabBarPageBottomPadding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Configuración")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = EPTheme.primary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.bold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(11)
        .frame(minHeight: 44)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
