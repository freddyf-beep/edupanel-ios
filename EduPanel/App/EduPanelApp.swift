import SwiftUI
import GoogleSignIn

@main
struct EduPanelApp: App {
    @State private var authSession = AuthSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authSession)
                .task {
                    await authSession.start()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

