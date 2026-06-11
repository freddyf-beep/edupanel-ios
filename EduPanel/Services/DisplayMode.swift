import SwiftUI

enum DisplayMode: String, CaseIterable, Identifiable {
    case simple
    case detallado

    static let storageKey = "displayMode"

    var id: String { rawValue }

    var isSimple: Bool { self == .simple }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .detallado: return "Detallado"
        }
    }

    var subtitle: String {
        switch self {
        case .simple: return "Vista compacta, solo lo esencial. Ideal para uso rápido."
        case .detallado: return "Toda la información visible. Ideal para planificación profunda."
        }
    }

    var icon: String {
        switch self {
        case .simple: return "bolt.fill"
        case .detallado: return "list.bullet.rectangle.fill"
        }
    }

    var toggled: DisplayMode {
        self == .simple ? .detallado : .simple
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case auto
    case claro
    case oscuro

    static let storageKey = "appTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automático"
        case .claro: return "Claro"
        case .oscuro: return "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .claro: return .light
        case .oscuro: return .dark
        }
    }
}

private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue = DisplayMode.simple
}

extension EnvironmentValues {
    var displayMode: DisplayMode {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }
}

struct DisplayModeToggleButton: View {
    @AppStorage(DisplayMode.storageKey) private var displayModeRaw = DisplayMode.simple.rawValue

    private var mode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .simple
    }

    var body: some View {
        Button {
            withAnimation(EPTheme.spring) {
                displayModeRaw = mode.toggled.rawValue
            }
        } label: {
            Image(systemName: mode.isSimple ? "eye" : "eye.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(EPTheme.primary)
                .frame(width: 34, height: 34)
                .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .accessibilityLabel("Cambiar a modo \(mode.toggled.title.lowercased())")
        .sensoryFeedback(.selection, trigger: displayModeRaw)
    }
}
