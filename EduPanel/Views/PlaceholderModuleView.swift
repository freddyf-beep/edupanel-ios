import SwiftUI

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

                Text("Este modulo quedo reservado para replicar la experiencia docente de la web en formato nativo.")
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

