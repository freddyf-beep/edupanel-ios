import Foundation
import FirebaseCore

enum FirebaseBootstrap {
    /// Un `static let` garantiza una sola configuración por proceso sin tener
    /// que consultar la app inexistente (Firebase registra esa consulta como
    /// error aun cuando el arranque sea correcto).
    private static let configurationIssue: AppConfigurationIssue? = {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return .missingFirebasePlist
        }

        FirebaseApp.configure()
        return nil
    }()

    static func configureIfPossible() -> AppConfigurationIssue? {
        configurationIssue
    }
}
