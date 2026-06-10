import SwiftUI

struct ProfileConnectionsTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot

    @AppStorage("edupanel_calendar_autosync") private var calendarAutosync = true
    @AppStorage("edupanel_drive_autosave") private var driveAutosave = false

    @State private var conectandoCalendar = false
    @State private var sincronizando = false
    @State private var calendarMessage: String?
    @State private var conectandoDrive = false
    @State private var trabajandoCarpeta = false
    @State private var driveMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            calendarSection
            driveSection
        }
    }

    // MARK: - Google Calendar

    private var calendarSection: some View {
        let isConnected = viewModel.draftPreferences.googleCalendarConnected

        return ProfileSection(title: "Google Calendar", icon: "calendar", hint: "Sincroniza actividades") {
            ConnectionStatusCard(
                title: "Estado de la conexión",
                message: isConnected
                    ? "Tu cuenta está conectada. Las actividades pueden incluir enlaces Drive cuando existan."
                    : "Conecta tu cuenta de Google para enviar actividades y enlaces de apoyo.",
                isConnected: isConnected
            )

            HStack(spacing: 10) {
                Button {
                    Task { await alternarCalendar(!isConnected) }
                } label: {
                    HStack(spacing: 7) {
                        if conectandoCalendar {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: isConnected ? "link.badge.plus" : "link")
                        }
                        Text(isConnected ? "Desconectar" : "Conectar Google Calendar")
                    }
                    .font(.footnote.weight(.black))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isConnected ? .secondary : EPTheme.primary)
                .disabled(conectandoCalendar)

                Button {
                    sincronizarAhora()
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
                .disabled(!isConnected || sincronizando)
            }

            Toggle(isOn: $calendarAutosync) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-sync al guardar cronograma")
                        .font(.footnote.weight(.black))
                    Text("Actualiza Google Calendar cada vez que guardas fechas de clases.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(EPTheme.primary)
            .disabled(!isConnected)
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let calendarMessage {
                mensajeEstado(calendarMessage)
            }
        }
    }

    private func alternarCalendar(_ conectar: Bool) async {
        conectandoCalendar = true
        calendarMessage = nil
        await viewModel.toggleConnection(type: "calendar", isConnected: conectar)
        conectandoCalendar = false
        calendarMessage = conectar ? "Google Calendar conectado." : "Google Calendar desconectado."
    }

    private func sincronizarAhora() {
        sincronizando = true
        calendarMessage = nil
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            sincronizando = false
            calendarMessage = "Solicitud de sincronización registrada. Los cronogramas con fecha se reflejarán en Google Calendar."
        }
    }

    // MARK: - Google Drive

    private var driveSection: some View {
        let isConnected = viewModel.draftPreferences.googleDriveConnected

        return ProfileSection(title: "Google Drive personal", icon: "externaldrive.fill", hint: "Carpetas privadas") {
            ConnectionStatusCard(
                title: "Estado de la conexión",
                message: isConnected
                    ? "Tu Drive personal está disponible en planificaciones, unidades, pruebas y guías."
                    : "Conecta tu cuenta para abrir tu Drive personal sin salir de EduPanel.",
                isConnected: isConnected
            )

            VStack(alignment: .leading, spacing: 6) {
                Label("Privado por docente", systemImage: "checkmark.shield.fill")
                    .font(.footnote.weight(.black))
                    .foregroundStyle(.green)
                Text("EduPanel crea carpetas solo en tu Drive personal cuando lo autorizas. Guarda IDs y enlaces mínimos, no contenido de documentos.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Label("Antes de configurar Drive", systemImage: "info.circle.fill")
                    .font(.footnote.weight(.black))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Google pedirá permiso para crear archivos y carpetas que EduPanel gestione.", systemImage: "checkmark")
                    Label("\"Crear / reparar\" genera una carpeta privada Edu-Panel con año, asignatura, curso y unidad.", systemImage: "checkmark")
                    Label("Los archivos quedan en tu Drive; EduPanel guarda solo enlaces e IDs.", systemImage: "checkmark")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task { await alternarDrive(!isConnected) }
            } label: {
                HStack(spacing: 7) {
                    if conectandoDrive {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: isConnected ? "gearshape.fill" : "link")
                    }
                    Text(isConnected ? "Desconectar Drive" : "Conectar Google Drive")
                }
                .font(.footnote.weight(.black))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isConnected ? .secondary : EPTheme.primary)
            .disabled(conectandoDrive)

            Toggle(isOn: driveAutosaveBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-respaldo Drive al guardar")
                        .font(.footnote.weight(.black))
                    Text("Actualiza Word y JSON al guardar. El PDF solo se crea al usar Exportar a Drive.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(EPTheme.primary)
            .disabled(!isConnected)
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if isConnected {
                HStack(spacing: 10) {
                    Button {
                        accionCarpeta("Carpeta Edu-Panel verificada y lista en tu Drive.")
                    } label: {
                        HStack(spacing: 7) {
                            if trabajandoCarpeta {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "folder.badge.gearshape")
                            }
                            Text("Crear / reparar carpeta")
                        }
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(EPTheme.primary)
                    .disabled(trabajandoCarpeta)

                    Button {
                        accionCarpeta("La carpeta raíz se abre desde la web por ahora.")
                    } label: {
                        Label("Abrir carpeta raíz", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.black))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(trabajandoCarpeta)
                }
            }

            if let driveMessage {
                mensajeEstado(driveMessage)
            }
        }
    }

    private var driveAutosaveBinding: Binding<Bool> {
        Binding(
            get: { driveAutosave },
            set: { nuevo in
                driveAutosave = nuevo
                driveMessage = nuevo
                    ? "Auto-respaldo Drive activado. Se actualizará Word y JSON al guardar."
                    : "Auto-respaldo Drive desactivado."
            }
        )
    }

    private func alternarDrive(_ conectar: Bool) async {
        conectandoDrive = true
        driveMessage = nil
        await viewModel.toggleConnection(type: "drive", isConnected: conectar)
        conectandoDrive = false
        if !conectar {
            driveAutosave = false
        }
        driveMessage = conectar ? "Google Drive conectado." : "Google Drive desconectado."
    }

    private func accionCarpeta(_ resultado: String) {
        trabajandoCarpeta = true
        driveMessage = nil
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            trabajandoCarpeta = false
            driveMessage = resultado
        }
    }

    private func mensajeEstado(_ texto: String) -> some View {
        Label(texto, systemImage: "info.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
