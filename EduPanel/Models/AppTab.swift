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
        case .clases: return "Clases"
        case .perfil: return "Perfil"
        }
    }

    var systemImage: String {
        switch self {
        case .inicio: return "house"
        case .planificaciones: return "square.and.pencil"
        case .cronograma: return "calendar"
        case .evaluaciones: return "checkmark.circle"
        case .clases: return "calendar.badge.clock"
        case .perfil: return "person.crop.circle"
        }
    }
}
