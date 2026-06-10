import Observation
import SwiftUI
import UIKit

struct PlaceholderModuleView: View {
    let tab: AppTab

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: EPTheme.primary.opacity(0.28), radius: 16, y: 8)

            VStack(spacing: 8) {
                Text(tab.title)
                    .font(.system(size: 22, weight: .black))

                Text("Sin contenido por ahora.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Label("Próximamente", systemImage: "hammer.fill")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(EPTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(EPTheme.primary.opacity(0.1), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(tab.title)
    }
}

struct RoutePlaceholderView: View {
    let route: AppRoute

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: route.systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(EPTheme.primary)
                .frame(width: 92, height: 92)
                .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(EPTheme.primary.opacity(0.18), lineWidth: 1)
                )

            VStack(spacing: 8) {
                Text(route.title)
                    .font(.system(size: 22, weight: .black))

                Text(route.placeholderText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.title)
    }
}
