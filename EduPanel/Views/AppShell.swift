import SwiftUI

struct AppShell: View {
    @Environment(AuthSession.self) private var authSession

    let user: AuthenticatedUser
    let dashboardRepository: DashboardRepository

    @State private var selectedTab: AppTab = .inicio

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(repository: dashboardRepository, user: user)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await authSession.signOut() }
                            } label: {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            .accessibilityLabel("Cerrar sesion")
                        }
                    }
            }
            .tabItem { Label(AppTab.inicio.title, systemImage: AppTab.inicio.systemImage) }
            .tag(AppTab.inicio)

            ForEach(AppTab.allCases.filter { $0 != .inicio }) { tab in
                NavigationStack {
                    PlaceholderModuleView(tab: tab)
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
    }
}

