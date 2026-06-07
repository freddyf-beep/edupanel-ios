import SwiftUI

struct ProfileConnectionsTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Google Calendar", icon: "calendar", hint: "Sincroniza actividades") {
                let isConnected = viewModel.draftPreferences.googleCalendarConnected
                ConnectionStatusCard(
                    title: "Estado de la conexión",
                    message: isConnected ? "Cuenta de Google vinculada. Actividades y leccionarios se sincronizan automáticamente." : "Conecta tu cuenta de Google para enviar actividades y enlaces de apoyo.",
                    isConnected: isConnected
                )

                HStack(spacing: 10) {
                    NavigationLink(value: AppRoute.calendarConnect) {
                        Label(isConnected ? "Desconectar" : "Conectar", systemImage: isConnected ? "link.badge.plus" : "link")
                            .frame(maxWidth: .infinity)
                    }
                    if isConnected {
                        NavigationLink(value: AppRoute.calendarSync) {
                            Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .font(.footnote.weight(.black))
                .buttonStyle(.bordered)
                .tint(.pink)
            }

            ProfileSection(title: "Google Drive personal", icon: "externaldrive.fill", hint: "Carpetas privadas") {
                let isConnected = viewModel.draftPreferences.googleDriveConnected
                ConnectionStatusCard(
                    title: "Estado de la conexión",
                    message: isConnected ? "Drive personal conectado. Carpeta raíz 'EduPanel' creada exitosamente." : "Tu Drive personal queda disponible para planificaciones, unidades, pruebas y guías cuando lo autorices.",
                    isConnected: isConnected
                )

                if isConnected {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Privado por docente", systemImage: "checkmark.shield.fill")
                            .font(.footnote.weight(.black))
                        Text("EduPanel crea carpetas solo en tu Drive personal. Puedes desconectar el acceso en cualquier momento.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                NavigationLink(value: AppRoute.driveConnect) {
                    Label(isConnected ? "Gestionar / Desconectar" : "Conectar Drive", systemImage: isConnected ? "gearshape.fill" : "link")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(isConnected ? .bordered : .borderedProminent)
                .tint(.pink)
            }
        }
    }
}
