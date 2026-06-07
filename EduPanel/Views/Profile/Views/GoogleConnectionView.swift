import SwiftUI

struct GoogleConnectionView: View {
    let connectionType: String // "calendar" or "drive"
    let repository: DashboardRepository

    @Environment(\.dismiss) private var dismiss

    @State private var isConnected = false
    @State private var isLoading = false
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var actionStatus: ProfileSaveStatus = .idle

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando estado de la conexión...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 24) {
                    // Header Brand Card
                    VStack(spacing: 16) {
                        Image(systemName: connectionType == "calendar" ? "calendar" : "externaldrive.badge.icloud")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(connectionType == "calendar" ? .blue : .green)
                            .frame(width: 110, height: 110)
                            .background((connectionType == "calendar" ? Color.blue : Color.green).opacity(0.12), in: Circle())
                            .shadow(color: .black.opacity(0.05), radius: 5, y: 3)

                        VStack(spacing: 6) {
                            Text(connectionType == "calendar" ? "Google Calendar" : "Google Drive")
                                .font(.title3.weight(.black))
                            
                            Text(isConnected ? "Cuenta vinculada" : "Servicio no conectado")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isConnected ? .green : .secondary)
                        }
                    }
                    .padding(.top, 36)

                    // Description text
                    Text(connectionType == "calendar"
                         ? "Al conectar Google Calendar, EduPanel creará eventos correspondientes a tus bloques lectivos y registrará las actividades de tus planificaciones nativas."
                         : "Al vincular Google Drive, EduPanel organizará carpetas dedicadas para tus cursos donde podrás almacenar planificaciones, recursos y material de apoyo."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                    Spacer()

                    // Action buttons
                    VStack(spacing: 12) {
                        if !isConnected {
                            Button {
                                performConnect()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.title3)
                                    Text("Iniciar sesión con Google")
                                        .font(.footnote.weight(.black))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pink)
                        } else {
                            if connectionType == "calendar" {
                                Button {
                                    performSync()
                                } label: {
                                    Label(isSyncing ? "Sincronizando..." : "Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.footnote.weight(.black))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.bordered)
                                .tint(.pink)
                                .disabled(isSyncing)
                            }

                            Button(role: .destructive) {
                                performDisconnect()
                            } label: {
                                Label("Desvincular cuenta", systemImage: "link.badge.minus")
                                    .font(.footnote.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }

            if let errorMessage {
                ProfileErrorBanner(message: errorMessage)
                    .padding()
            }

            if actionStatus != .idle {
                HStack {
                    ProfileSaveBadge(status: actionStatus)
                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .navigationTitle(connectionType == "calendar" ? "Google Calendar" : "Google Drive")
        .task {
            await loadConnectionState()
        }
    }

    private func loadConnectionState() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard()
            if connectionType == "calendar" {
                isConnected = next.preferences.googleCalendarConnected
            } else {
                isConnected = next.preferences.googleDriveConnected
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func performConnect() {
        actionStatus = .saving
        errorMessage = nil
        // Simulate OAuth load delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Task {
                do {
                    let next = try await repository.fetchDashboard()
                    var cal = next.preferences.googleCalendarConnected
                    var drv = next.preferences.googleDriveConnected

                    if connectionType == "calendar" {
                        cal = true
                    } else {
                        drv = true
                    }

                    try await repository.saveConnections(googleCalendarConnected: cal, googleDriveConnected: drv)
                    isConnected = true
                    actionStatus = .saved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        actionStatus = .idle
                        dismiss()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    actionStatus = .error
                }
            }
        }
    }

    private func performDisconnect() {
        actionStatus = .saving
        errorMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Task {
                do {
                    let next = try await repository.fetchDashboard()
                    var cal = next.preferences.googleCalendarConnected
                    var drv = next.preferences.googleDriveConnected

                    if connectionType == "calendar" {
                        cal = false
                    } else {
                        drv = false
                    }

                    try await repository.saveConnections(googleCalendarConnected: cal, googleDriveConnected: drv)
                    isConnected = false
                    actionStatus = .saved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        actionStatus = .idle
                        dismiss()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    actionStatus = .error
                }
            }
        }
    }

    private func performSync() {
        isSyncing = true
        actionStatus = .saving
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSyncing = false
            actionStatus = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                actionStatus = .idle
            }
        }
    }
}
