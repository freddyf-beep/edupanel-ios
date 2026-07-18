import SwiftUI

enum DisplayMode {
    case detallado

    /// Puente para las vistas que aún se están migrando al diseño único.
    /// Siempre es falso: el modo simple ya no forma parte de la aplicación.
    var isSimple: Bool { false }
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

// Compatibilidad temporal para las vistas heredadas durante su migración al
// único diseño completo. No existe selector ni preferencia visible al usuario.
private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue = DisplayMode.detallado
}

extension EnvironmentValues {
    var displayMode: DisplayMode {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }
}
