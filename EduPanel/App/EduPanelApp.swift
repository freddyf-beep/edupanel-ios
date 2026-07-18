import SwiftUI
import GoogleSignIn

@main
struct EduPanelApp: App {
    @State private var authSession = AuthSession()
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.auto.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authSession)
                .preferredColorScheme((AppTheme(rawValue: appThemeRaw) ?? .auto).colorScheme)
                .task {
                    await authSession.start()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
