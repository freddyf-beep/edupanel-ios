import UIKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

enum GoogleAuthError: LocalizedError {
    case missingClientID
    case missingPresenter
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Firebase no entrego clientID para Google Sign-In."
        case .missingPresenter:
            return "No se pudo abrir la ventana de login."
        case .missingIDToken:
            return "Google no devolvio un ID token valido."
        }
    }
}

@MainActor
struct GoogleAuthService {
    func signIn() async throws -> AuthenticatedUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw GoogleAuthError.missingClientID
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = UIApplication.shared.keyRootViewController else {
            throw GoogleAuthError.missingPresenter
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleAuthError.missingIDToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        return AuthenticatedUser(firebaseUser: authResult.user, role: .docente)
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
}

private extension UIApplication {
    var keyRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
