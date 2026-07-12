import SwiftUI

struct PruebasUpcomingCard: View {
    var body: some View {
        EPWebCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Próximamente")
                            .font(.caption.weight(.black))
                        Text("Funciones reservadas para la siguiente etapa en Mac")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ReplicaFlowLayout(spacing: 7) {
                    upcoming("Adaptaciones PIE con IA", icon: "person.crop.circle.badge.checkmark")
                    upcoming("Simulación de estudiantes", icon: "person.3.sequence.fill")
                    upcoming("Calibración de Bloom", icon: "chart.bar.xaxis")
                    upcoming("Historial y versiones", icon: "clock.arrow.circlepath")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Funciones próximamente")
    }

    private func upcoming(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.purple.opacity(0.09), in: Capsule())
    }
}
