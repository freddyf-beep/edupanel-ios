import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

@MainActor
private protocol AllowlistChecking {
    func isAllowed(firebaseUser: User) async throws -> Bool
}

@MainActor
private struct FirestoreAllowlistChecker: AllowlistChecking {
    private let db = Firestore.firestore()

    func isAllowed(firebaseUser: User) async throws -> Bool {
        let email = Self.normalizedEmail(firebaseUser.email)

        if firebaseUser.isEmailVerified, let email, Self.defaultAdminEmails.contains(email) {
            return true
        }

        if let email {
            let emailDocument = db.collection("allowlist").document(email)
            if try await documentExists(emailDocument) {
                return true
            }
        }

        let uidDocument = db.collection("allowlist_uids").document(firebaseUser.uid)
        return try await documentExists(uidDocument)
    }

    private func documentExists(_ reference: DocumentReference) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            reference.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: snapshot?.exists == true)
                }
            }
        }
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    // Debe mantenerse sincronizado con los administradores base del backend web.
    private static let defaultAdminEmails: Set<String> = [
        "freddyfigueroagea@gmail.com",
        "freddyfiguea@gmail.com"
    ]
}

@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        case checking
        case signedOut
        case blocked(AuthenticatedUser)
        case authorizationUnavailable(AuthenticatedUser)
        case signedIn(AuthenticatedUser)
        case configurationError(String)
    }

    var state: State = .checking
    var inviteCode = ""
    var testerName = ""
    var isSigningIn = false
    var isRedeeming = false
    var errorMessage: String?

    private(set) var apiClient: APIClient?
    private(set) var dashboardRepository: DashboardRepository?

    private let googleAuth = GoogleAuthService()

    init() {
        if let firebaseIssue = FirebaseBootstrap.configureIfPossible() {
            state = .configurationError(firebaseIssue.message)
            return
        }

        switch AppConfig.load() {
        case .success(let config):
            let client = APIClient(config: config)
            apiClient = client
            dashboardRepository = DashboardRepository()
        case .failure(let issue):
            state = .configurationError(issue.message)
        }
    }

    func start() async {
        guard !isConfigurationError else { return }
        guard let user = Auth.auth().currentUser else {
            state = .signedOut
            return
        }
        await validateAllowlist(for: AuthenticatedUser(firebaseUser: user, role: .docente))
    }

    func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil

        do {
            let user = try await googleAuth.signIn()
            await validateAllowlist(for: user)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }

        isSigningIn = false
    }

    func redeemInvite() async {
        let cleanCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCode.isEmpty else {
            errorMessage = "Ingresa un codigo de invitacion."
            return
        }
        guard let client = apiClient, let currentUser = Auth.auth().currentUser else {
            errorMessage = "No hay una sesión activa para canjear el código."
            return
        }

        isRedeeming = true
        errorMessage = nil

        do {
            let path = currentUser.isAnonymous ? "/api/redeem-test-invite" : "/api/redeem-invite"
            let body = RedeemInviteRequest(
                code: cleanCode,
                testerName: testerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : testerName
            )
            let _: RedeemInviteResponse = try await client.post(path, body: body)
            inviteCode = ""
            await validateAllowlist(for: AuthenticatedUser(firebaseUser: currentUser, role: .docente))
        } catch {
            errorMessage = error.localizedDescription
        }

        isRedeeming = false
    }

    func signOut() async {
        do {
            try googleAuth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        state = .signedOut
    }

    func retryAuthorization() async {
        guard let firebaseUser = Auth.auth().currentUser else {
            state = .signedOut
            return
        }

        errorMessage = nil
        await validateAllowlist(for: AuthenticatedUser(firebaseUser: firebaseUser, role: .docente))
    }

    private func validateAllowlist(for user: AuthenticatedUser) async {
        guard let client = apiClient else {
            state = .configurationError("La conexion API no esta configurada.")
            return
        }

        state = .checking

        do {
            let response: CheckAllowlistResponse = try await client.get("/api/check-allowlist")
            errorMessage = nil
            if response.allowed {
                state = .signedIn(user)
            } else {
                state = .blocked(user)
            }
        } catch {
            await validateAllowlistWithFirestore(for: user)
        }
    }

    private func validateAllowlistWithFirestore(for user: AuthenticatedUser) async {
        guard let firebaseUser = Auth.auth().currentUser, firebaseUser.uid == user.id else {
            errorMessage = "La sesión cambió. Vuelve a iniciar sesión para verificar tu acceso."
            state = .authorizationUnavailable(user)
            return
        }

        do {
            let allowed = try await FirestoreAllowlistChecker().isAllowed(firebaseUser: firebaseUser)
            errorMessage = nil
            state = allowed ? .signedIn(user) : .blocked(user)
        } catch {
            errorMessage = "No pudimos verificar tu acceso en este momento. Revisa tu conexión e inténtalo nuevamente."
            state = .authorizationUnavailable(user)
        }
    }

    private var isConfigurationError: Bool {
        if case .configurationError = state {
            return true
        }
        return false
    }
}
