import Observation
import SwiftUI
import UIKit

struct PlaceholderModuleView: View {
    let tab: AppTab
    var onVolverInicio: (() -> Void)? = nil

    private var descripcion: String {
        switch tab {
        case .evaluaciones:
            return "Aquí crearás rúbricas, listas de cotejo y pruebas, y calificarás a tus estudiantes directamente desde el celular."
        case .clases:
            return "El libro de clases digital: leccionario, asistencia y registro diario de cada bloque, sincronizado con la web."
        case .inicio:
            return "Tu resumen diario con clases, pendientes y recordatorios."
        case .planificaciones:
            return "Planifica unidades didácticas por curso con cronograma y clases."
        case .cronograma:
            return "Tu mapa pedagógico del año con todas las actividades."
        case .perfil:
            return "Tu horario, cursos, estudiantes e identidad docente."
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: EPTheme.primary.opacity(0.3), radius: 18, y: 9)

            VStack(spacing: 9) {
                Text(tab.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))

                Text(descripcion)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Label("Próximamente", systemImage: "hammer.fill")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(EPTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(EPTheme.primary.opacity(0.1), in: Capsule())

            if let onVolverInicio {
                Button {
                    onVolverInicio()
                } label: {
                    Label("Volver al inicio", systemImage: "house.fill")
                        .font(.system(size: 13, weight: .black))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
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
                    .font(.system(size: 22, weight: .black, design: .rounded))

                Text(route.placeholderText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
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
        .navigationTitle(route.title)
    }
}
