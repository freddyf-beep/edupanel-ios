import SwiftUI

struct SettingsAppearanceSection: View {
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.auto.rawValue

    var body: some View {
        ProfileSection(title: "Apariencia", icon: "paintbrush.fill", hint: nil) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tema")
                        .profileFieldLabel()
                    Picker("Tema", selection: $appThemeRaw) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}
