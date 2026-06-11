import SwiftUI

struct SettingsAppearanceSection: View {
    @AppStorage(DisplayMode.storageKey) private var displayModeRaw = DisplayMode.simple.rawValue
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.auto.rawValue

    private var displayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .simple
    }

    var body: some View {
        ProfileSection(title: "Apariencia", icon: "paintbrush.fill", hint: nil) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modo de visualización")
                        .profileFieldLabel()

                    VStack(spacing: 8) {
                        ForEach(DisplayMode.allCases) { mode in
                            modeCard(mode)
                        }
                    }
                }

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

    private func modeCard(_ mode: DisplayMode) -> some View {
        let isSelected = displayMode == mode

        return Button {
            withAnimation(EPTheme.spring) {
                displayModeRaw = mode.rawValue
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: mode.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        isSelected ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(Color(.systemGray5)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.footnote.weight(isSelected ? .black : .semibold))
                    Text(mode.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(EPTheme.primary)
                }
            }
            .padding(11)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? EPTheme.primary.opacity(0.4) : Color(.separator).opacity(0.1), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: displayModeRaw)
    }
}
