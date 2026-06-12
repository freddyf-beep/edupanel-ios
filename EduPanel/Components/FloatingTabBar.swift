import SwiftUI

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var badges: [AppTab: Int] = [:]
    var onMore: () -> Void = {}

    @Namespace private var barNamespace

    private let visibles: [AppTab] = [.inicio, .planificaciones, .cronograma, .perfil]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(visibles) { tab in
                tabItem(tab)
            }
            moreItem
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.35), Color(.separator).opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
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
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolEffect(.bounce, value: isSelected)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(.green, in: Capsule())
                                .offset(x: 11, y: -7)
                        }
                    }

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .black : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(EPTheme.primary)
                        .matchedGeometryEffect(id: "floating-tab-pill", in: barNamespace)
                        .shadow(color: EPTheme.primary.opacity(0.35), radius: 8, y: 3)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var moreItem: some View {
        Button {
            onMore()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 21, weight: .semibold))
                Text("Más")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir menú")
    }
}
