import SwiftUI

struct Perfil360View: View {
    let user: AuthenticatedUser
    let repository: DashboardRepository

    @Environment(\.displayMode) private var displayMode
    @State private var snapshot: DashboardSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let kpiColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: displayMode.isSimple ? 12 : 16) {
                EPModuleHeader(
                    eyebrow: "Perfil 360",
                    title: user.displayName ?? "Profesor EduPanel",
                    subtitle: "Vista transversal de identidad, cursos, semana y configuración base.",
                    icon: "person.crop.circle.badge.checkmark",
                    accent: .primary
                ) {
                    Button {
                        Task { await cargar(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Actualizar perfil 360")
                }

                if isLoading && snapshot == nil {
                    loadingCard
                } else if let errorMessage {
                    errorCard(errorMessage)
                } else if let snapshot {
                    contenido(snapshot)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .background(EPTheme.background.ignoresSafeArea())
        .navigationTitle("Perfil 360")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await cargar(forceRefresh: true)
        }
        .task {
            await cargar()
        }
    }

    @ViewBuilder
    private func contenido(_ snapshot: DashboardSnapshot) -> some View {
        LazyVGrid(columns: kpiColumns, spacing: 10) {
            EPKPIBox(title: "Cursos", value: "\(snapshot.courses.count)", subtitle: "con horario", icon: "folder.fill", tint: EPTheme.primary)
            EPKPIBox(title: "Estudiantes", value: "\(snapshot.totalStudents)", subtitle: "\(snapshot.totalPIEStudents) PIE", icon: "person.3.fill", tint: .blue)
            EPKPIBox(title: "Clases", value: "\(snapshot.academicClasses.count)", subtitle: "\(horasTexto(snapshot.totalAcademicMinutes)) semanales", icon: "calendar", tint: .green)
            EPKPIBox(title: "Perfil", value: "\(snapshot.setupProgress)%", subtitle: "configuración", icon: "checkmark.seal.fill", tint: snapshot.setupProgress >= 80 ? .green : .orange)
        }

        identidadCard(snapshot)
        semanaCard(snapshot)
        cursosCard(snapshot)
        checklistCard(snapshot)
        conexionesCard(snapshot)
    }

    private var loadingCard: some View {
        EPWebCard {
            HStack(spacing: 12) {
                ProgressView()
                Text("Cargando perfil 360...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorCard(_ message: String) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "No se pudo cargar", subtitle: message, icon: "exclamationmark.triangle.fill")
                Button {
                    Task { await cargar(forceRefresh: true) }
                } label: {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.black))
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
            }
        }
    }

    private func identidadCard(_ snapshot: DashboardSnapshot) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Identidad docente", subtitle: snapshot.school.nombre.isEmpty ? nil : snapshot.school.nombre, icon: "person.text.rectangle.fill")
                infoRow("Nombre", user.displayName ?? "Profesor EduPanel")
                infoRow("Correo", user.email ?? "Sin correo")
                infoRow("Rol", snapshot.profile.tipoProfesor.isEmpty ? user.role.title : snapshot.profile.tipoProfesor)
                infoRow("Especialidad", valor(snapshot.profile.especialidad))
                infoRow("Estudios", valor(snapshot.profile.estudios))
            }
        }
    }

    private func semanaCard(_ snapshot: DashboardSnapshot) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Semana docente", subtitle: "\(horasTexto(snapshot.totalAcademicMinutes)) lectivas y \(horasTexto(snapshot.totalFreeMinutes)) no lectivas", icon: "calendar.badge.clock")

                ForEach(DateHelpers.workdays, id: \.self) { dia in
                    let clases = snapshot.horario.filter { $0.dia == dia }
                    diaRow(dia: dia, clases: clases)
                }
            }
        }
    }

    private func cursosCard(_ snapshot: DashboardSnapshot) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Cursos y asignaturas", subtitle: "\(snapshot.totalStudents) estudiantes cargados", icon: "folder.fill")

                if snapshot.courses.isEmpty {
                    EPEmptyState(icon: "folder.badge.questionmark", title: "Sin cursos", message: "Configura tu horario en Mi Perfil para activar el resumen 360.")
                } else {
                    ForEach(snapshot.courses, id: \.self) { curso in
                        cursoRow(curso: curso, snapshot: snapshot)
                    }
                }
            }
        }
    }

    private func checklistCard(_ snapshot: DashboardSnapshot) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Preparación de perfil", subtitle: "\(snapshot.setupProgress)% completo", icon: "checklist.checked")

                ForEach(snapshot.setupChecklist) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(item.isComplete ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.footnote.weight(.black))
                            if let hint = item.hint, !hint.isEmpty {
                                Text(hint)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
                }
            }
        }
    }

    private func conexionesCard(_ snapshot: DashboardSnapshot) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Conexiones", subtitle: "Estado de integraciones sincronizadas", icon: "link")
                HStack(spacing: 8) {
                    conexionPill("Calendar", conectado: snapshot.preferences.googleCalendarConnected, icon: "calendar")
                    conexionPill("Drive", conectado: snapshot.preferences.googleDriveConnected, icon: "externaldrive.fill")
                }
            }
        }
    }

    private func diaRow(dia: String, clases: [ClaseHorario]) -> some View {
        let academicas = clases.filter(\.isAcademic)
        let libres = clases.filter { $0.tipo.isFreeBlock }
        return HStack(spacing: 10) {
            Text(String(dia.prefix(3)).uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(EPTheme.primary)
                .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(academicas.count) clases")
                    .font(.footnote.weight(.black))
                Text("\(libres.count) bloques no lectivos")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(horasTexto(minutos(clases)))
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
    }

    private func cursoRow(curso: String, snapshot: DashboardSnapshot) -> some View {
        let asignaturas = asignaturasDeCurso(curso, snapshot: snapshot)
        let estudiantes = snapshot.studentsByCourse[curso] ?? []
        let pie = estudiantes.filter(\.pie).count
        let nivel = snapshot.nivelMapping[curso]

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(colorCurso(curso, snapshot: snapshot))
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(curso)
                        .font(.subheadline.weight(.black))
                    Text("\(estudiantes.count) estudiantes\(pie > 0 ? " · \(pie) PIE" : "")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                EPStatusPill(text: nivel?.isEmpty == false ? nivel! : "Sin nivel", tint: nivel?.isEmpty == false ? .green : .orange)
            }

            if !asignaturas.isEmpty {
                ReplicaFlowLayout(spacing: 6) {
                    ForEach(asignaturas, id: \.self) { asignatura in
                        Text(asignatura)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(EPTheme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(EPTheme.primaryLight, in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.footnote.weight(.black))
                .multilineTextAlignment(.trailing)
        }
    }

    private func conexionPill(_ title: String, conectado: Bool, icon: String) -> some View {
        Label(conectado ? "\(title) conectado" : "\(title) pendiente", systemImage: conectado ? "checkmark.circle.fill" : icon)
            .font(.caption.weight(.black))
            .foregroundStyle(conectado ? .green : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(conectado ? Color.green.opacity(0.12) : EPTheme.subtle, in: Capsule())
    }

    private func cargar(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            snapshot = try await repository.fetchDashboard(forceRefresh: forceRefresh)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func asignaturasDeCurso(_ curso: String, snapshot: DashboardSnapshot) -> [String] {
        let asignaturas = snapshot.academicClasses
            .filter { $0.resumen == curso }
            .compactMap { $0.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(asignaturas)).sorted()
    }

    private func colorCurso(_ curso: String, snapshot: DashboardSnapshot) -> Color {
        let hex = snapshot.academicClasses.first { $0.resumen == curso }?.colorHex ?? "#F03E6E"
        return EPTheme.color(hex: hex, fallback: EPTheme.primary)
    }

    private func minutos(_ clases: [ClaseHorario]) -> Int {
        clases.reduce(0) { total, item in
            total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
        }
    }

    private func horasTexto(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    private func valor(_ text: String) -> String {
        let limpio = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return limpio.isEmpty ? "Sin completar" : limpio
    }
}
