import SwiftUI

struct SettingsDataSection: View {
    let repository: DashboardRepository

    @AppStorage("edupanel_last_sync") private var lastSyncTimestamp = 0.0
    @State private var preferences: PreferenciasUsuario?
    @State private var sincronizando = false
    @State private var mensaje: String?

    var body: some View {
        ProfileSection(title: "Datos y sincronización", icon: "arrow.triangle.2.circlepath", hint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRow(
                    icon: "calendar",
                    title: "Google Calendar",
                    subtitle: nil,
                    tint: .blue
                ) {
                    estadoPill(preferences?.googleCalendarConnected ?? false)
                }

                SettingsRow(
                    icon: "externaldrive.fill",
                    title: "Google Drive",
                    subtitle: nil,
                    tint: .green
                ) {
                    estadoPill(preferences?.googleDriveConnected ?? false)
                }

                SettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Última sincronización",
                    subtitle: lastSyncLabel,
                    tint: .purple
                ) {
                    EmptyView()
                }

                Button {
                    sincronizar()
                } label: {
                    HStack(spacing: 7) {
                        if sincronizando {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(sincronizando ? "Sincronizando…" : "Sincronizar ahora")
                    }
                    .font(.footnote.weight(.black))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(sincronizando)

                if let mensaje {
                    Label(mensaje, systemImage: "info.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            if let snapshot = try? await repository.fetchDashboard() {
                preferences = snapshot.preferences
            }
        }
    }

    private var lastSyncLabel: String {
        guard lastSyncTimestamp > 0 else { return "Nunca" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: lastSyncTimestamp))
    }

    private func estadoPill(_ conectado: Bool) -> some View {
        Text(conectado ? "Conectado" : "Desconectado")
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(conectado ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(conectado ? Color.green.opacity(0.14) : Color(.systemGray5), in: Capsule())
    }

    private func sincronizar() {
        sincronizando = true
        mensaje = nil
        Task {
            if let snapshot = try? await repository.fetchDashboard() {
                preferences = snapshot.preferences
            }
            try? await Task.sleep(for: .seconds(0.8))
            lastSyncTimestamp = Date().timeIntervalSince1970
            sincronizando = false
            mensaje = "Datos actualizados desde Firestore."
        }
    }
}
