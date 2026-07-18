import SwiftUI

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var badges: [AppTab: Int] = [:]
    var isCompact = false

    @Namespace private var barNamespace

    private let visibles: [AppTab] = [.inicio, .planificaciones, .evaluaciones, .cronograma, .perfil]

    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                barContent
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            fallbackBar
        }
#else
        fallbackBar
#endif
    }

    private var fallbackBar: some View {
        barContent
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private var barContent: some View {
        HStack(spacing: 3) {
            ForEach(visibles) { tab in
                tabItem(tab)
            }
        }
        .padding(isCompact ? 4 : 6)
        .frame(maxWidth: isCompact ? 286 : 360)
        .animation(EPTheme.spring, value: isCompact)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = selected == tab
        let badge = badges[tab] ?? 0

        return Button {
            withAnimation(EPTheme.spring) {
                selected = tab
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.11))
                        .matchedGeometryEffect(id: "floating-tab-pill", in: barNamespace)
                }

                Image(systemName: tab.systemImage)
                    .font(.system(size: isCompact ? 17 : 20, weight: isSelected ? .bold : .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolEffect(.bounce, value: isSelected)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(EPTheme.primary, in: Capsule())
                                .offset(x: 12, y: -9)
                        }
                    }
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 38 : 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TabBarScrollReporterKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var tabBarScrollReporter: (Bool) -> Void {
        get { self[TabBarScrollReporterKey.self] }
        set { self[TabBarScrollReporterKey.self] = newValue }
    }
}

private struct TabBarScrollReporterModifier: ViewModifier {
    @Environment(\.tabBarScrollReporter) private var report

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 56
            } action: { _, isAwayFromTop in
                report(isAwayFromTop)
            }
        } else {
            content
        }
    }
}

extension View {
    func reportsTabBarScroll() -> some View {
        modifier(TabBarScrollReporterModifier())
    }
}
