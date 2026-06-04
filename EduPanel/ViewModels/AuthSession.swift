import Foundation
import Observation
import FirebaseAuth

@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        case checking
        case signedOut
        case blocked(AuthenticatedUser)
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
            errorMessage = "No hay una sesion activa para canjear el codigo."
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

    private func validateAllowlist(for user: AuthenticatedUser) async {
        guard let client = apiClient else {
            state = .configurationError("La conexion API no esta configurada.")
            return
        }

        state = .checking

        do {
            let response: CheckAllowlistResponse = try await client.get("/api/check-allowlist")
            if response.allowed {
                state = .signedIn(user)
            } else {
                state = .blocked(user)
            }
        } catch {
            errorMessage = error.localizedDescription
            state = .blocked(user)
        }
    }

    private var isConfigurationError: Bool {
        if case .configurationError = state {
            return true
        }
        return false
    }
}

