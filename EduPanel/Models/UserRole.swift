import Foundation
import FirebaseAuth

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case docente
    case direccion
    case diferencial
    case apoderado
    case estudiante

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docente: return "Docente"
        case .direccion: return "Direccion"
        case .diferencial: return "Diferencial"
        case .apoderado: return "Apoderado"
        case .estudiante: return "Estudiante"
        }
    }
}

struct AuthenticatedUser: Equatable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    let photoURL: URL?
    let role: UserRole

    var firstName: String {
        guard let displayName, !displayName.isEmpty else { return "profe" }
        return displayName.split(separator: " ").first.map(String.init) ?? "profe"
    }

    init(id: String, email: String?, displayName: String?, photoURL: URL?, role: UserRole) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.role = role
    }

    init(firebaseUser: User, role: UserRole = .docente) {
        self.init(
            id: firebaseUser.uid,
            email: firebaseUser.email,
            displayName: firebaseUser.displayName,
            photoURL: firebaseUser.photoURL,
            role: role
        )
    }
}
