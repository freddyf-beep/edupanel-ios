import SwiftUI
import GoogleSignIn

@main
struct EduPanelApp: App {
    @State private var authSession = AuthSession()
    @AppStorage(DisplayMode.storageKey) private var displayModeRaw = DisplayMode.simple.rawValue
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.auto.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authSession)
                .environment(\.displayMode, DisplayMode(rawValue: displayModeRaw) ?? .simple)
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

