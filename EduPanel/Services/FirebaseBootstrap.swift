import Foundation
import FirebaseCore

enum FirebaseBootstrap {
    static func configureIfPossible() -> AppConfigurationIssue? {
        if FirebaseApp.app() != nil {
            return nil
        }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return .missingFirebasePlist
        }

        FirebaseApp.configure()
        return nil
    }
}

