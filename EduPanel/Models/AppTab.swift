import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case inicio
    case planificaciones
    case cronograma
    case evaluaciones
    case clases
    case perfil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inicio: return "Inicio"
        case .planificaciones: return "Planificar"
        case .cronograma: return "Cronograma"
        case .evaluaciones: return "Evaluaciones"
        case .clases: return "Asistencia"
        case .perfil: return "Perfil"
        }
    }

    var systemImage: String {
        switch self {
        case .inicio: return "house"
        case .planificaciones: return "square.and.pencil"
        case .cronograma: return "calendar"
        case .evaluaciones: return "checkmark.circle"
        case .clases: return "person.3.sequence"
        case .perfil: return "person.crop.circle"
        }
    }
}

enum TabBarPreferences {
    static let storageKey = "edupanel_tab_bar_items"
    static let defaultTabs: [AppTab] = [.inicio, .planificaciones, .evaluaciones, .cronograma, .perfil]
    static let minimumCount = 3
    static let maximumCount = 5

    static var defaultValue: String {
        encode(defaultTabs)
    }

    static func decode(_ value: String) -> [AppTab] {
        let tabs = value
            .split(separator: ",")
            .compactMap { AppTab(rawValue: String($0)) }
            .reduce(into: [AppTab]()) { result, tab in
                if !result.contains(tab) { result.append(tab) }
            }

        guard tabs.count >= minimumCount, tabs.count <= maximumCount else {
            return defaultTabs
        }
        return tabs
    }

    static func encode(_ tabs: [AppTab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }
}
