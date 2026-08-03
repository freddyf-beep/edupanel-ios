import SwiftUI

struct SettingsDataSection: View {
    let repository: DashboardRepository

    @AppStorage("edupanel_last_sync") private var lastSyncTimestamp = 0.0
    @State private var sincronizando = false
    @State private var mensaje: String?
    @State private var mensajeEsError = false

    var body: some View {
        ProfileSection(title: "Conexiones y sincronización", icon: "link", hint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink(value: AppRoute.calendarConnect) {
                    SettingsRow(
                        icon: "calendar",
                        title: "Google Calendar",
                        subtitle: "Vista previa · conexión próximamente",
                        tint: .blue
                    ) {
                        connectionAccessory
                    }
                }
                .buttonStyle(.plain)

                NavigationLink(value: AppRoute.driveConnect) {
                    SettingsRow(
                        icon: "externaldrive.fill",
                        title: "Google Drive",
                        subtitle: "Vista previa · conexión próximamente",
                        tint: .green
                    ) {
                        connectionAccessory
                    }
                }
                .buttonStyle(.plain)

                SettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Última actualización",
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
                        Text(sincronizando ? "Actualizando…" : "Actualizar datos de EduPanel")
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
                        .foregroundStyle(mensajeEsError ? .red : .secondary)
                }

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

    private var estadoPill: some View {
        Text("Próximamente")
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(.systemGray5), in: Capsule())
    }

    private var connectionAccessory: some View {
        HStack(spacing: 7) {
            estadoPill
            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.tertiary)
        }
    }

    private func sincronizar() {
        guard !sincronizando else { return }
        sincronizando = true
        mensaje = nil
        mensajeEsError = false
        Task {
            defer { sincronizando = false }

            do {
                _ = try await repository.fetchDashboard(forceRefresh: true)
                guard !Task.isCancelled else { return }
                lastSyncTimestamp = Date().timeIntervalSince1970
                mensaje = "Datos actualizados desde Firestore."
            } catch is CancellationError {
                return
            } catch {
                mensajeEsError = true
                mensaje = "No se pudieron actualizar los datos: \(error.localizedDescription)"
            }
        }
    }
}
