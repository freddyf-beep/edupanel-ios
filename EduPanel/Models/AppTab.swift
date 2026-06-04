import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case inicio
    case planificaciones
    case evaluaciones
    case clases
    case perfil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inicio: return "Inicio"
        case .planificaciones: return "Planificaciones"
        case .evaluaciones: return "Evaluaciones"
        case .clases: return "Clases"
        case .perfil: return "Perfil"
        }
    }

    var systemImage: String {
        switch self {
        case .inicio: return "house.fill"
        case .planificaciones: return "book.closed.fill"
        case .evaluaciones: return "checklist.checked"
        case .clases: return "calendar.badge.clock"
        case .perfil: return "person.crop.circle.fill"
        }
    }
}
