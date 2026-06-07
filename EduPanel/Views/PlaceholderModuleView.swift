import Observation
import SwiftUI
import UIKit

struct PlaceholderModuleView: View {
    let tab: AppTab

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 84, height: 84)
                .background(.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(spacing: 8) {
                Text(tab.title)
                    .font(.title2.bold())

                Text("Sin contenido por ahora.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(tab.title)
    }
}

struct RoutePlaceholderView: View {
    let route: AppRoute

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: route.systemImage)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.pink)
                .frame(width: 86, height: 86)
                .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(spacing: 8) {
                Text(route.title)
                    .font(.title2.bold())

                Text(route.placeholderText)
                    .font(.subheadline)
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
