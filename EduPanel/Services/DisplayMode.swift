import SwiftUI

/// Nivel de complejidad que se muestra en la navegación y en las pantallas que
/// ya admiten divulgación progresiva. La preferencia se mantiene en el equipo.
enum DisplayMode: String, CaseIterable, Identifiable {
    case simple
    case completo

    static let storageKey = "edupanel_display_mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .completo: return "Completo"
        }
    }

    var description: String {
        switch self {
        case .simple:
            return "Muestra las tareas de uso diario y una navegación más directa."
        case .completo:
            return "Incluye accesos y opciones avanzadas para organizar tu trabajo."
        }
    }

    var isSimple: Bool { self == .simple }
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
