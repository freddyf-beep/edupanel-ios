import SwiftUI

struct GoogleConnectionView: View {
    let connectionType: String // "calendar" or "drive"
    let repository: DashboardRepository

    @State private var hasSavedConnectionPreference = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando configuración de la vista previa...")
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
                            
                            Text("Vista previa · próximamente")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 36)

                    // Description text
                    Text(connectionType == "calendar"
                         ? "Estamos preparando la integración con Google Calendar. Esta vista previa no inicia sesión, no vincula una cuenta y no crea ni sincroniza eventos."
                         : "Estamos preparando la integración con Google Drive. Esta vista previa no inicia sesión, no vincula una cuenta y no crea carpetas ni guarda archivos."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                    if hasSavedConnectionPreference {
                        Label(
                            "Hay una preferencia anterior guardada; no representa una cuenta de Google vinculada.",
                            systemImage: "info.circle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {} label: {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.title3)
                                Text("Conexión con Google próximamente")
                                    .font(.footnote.weight(.black))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EPTheme.primary)
                        .disabled(true)
                        .accessibilityHint("La conexión aún no está disponible y no inicia sesión ni vincula una cuenta.")

                        if connectionType == "calendar" {
                            Button {} label: {
                                Label("Sincronización disponible próximamente", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.footnote.weight(.black))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(EPTheme.primary)
                            .disabled(true)
                            .accessibilityHint("La sincronización aún no está disponible y no crea ni actualiza eventos.")
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

        }
        .tabBarPageBottomPadding()
        .navigationTitle(connectionType == "calendar" ? "Google Calendar" : "Google Drive")
        .task {
            await loadPreviewPreference()
        }
    }

    private func loadPreviewPreference() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard()
            if connectionType == "calendar" {
                hasSavedConnectionPreference = next.preferences.googleCalendarConnected
            } else {
                hasSavedConnectionPreference = next.preferences.googleDriveConnected
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
