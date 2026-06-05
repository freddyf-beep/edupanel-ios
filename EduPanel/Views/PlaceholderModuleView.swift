import Observation
import SwiftUI
import UIKit

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

                Text("Sin contenido por ahora.")
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

struct RoutePlaceholderView: View {
    let route: AppRoute

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: route.systemImage)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.pink)
                .frame(width: 86, height: 86)
                .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(spacing: 8) {
                Text(route.title)
                    .font(.title2.bold())

                Text("Sin contenido por ahora.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.title)
    }
}

enum ProfileSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case error

    var title: String {
        switch self {
        case .idle: return ""
        case .saving: return "Guardando"
        case .saved: return "Guardado"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .saving: return .blue
        case .saved: return .green
        case .error: return .red
        }
    }
}

@MainActor
@Observable
final class ProfileViewModel {
    var snapshot: DashboardSnapshot?
    var draftProfile = PerfilUsuario.empty
    var draftSchool = InfoColegio.empty
    var draftPreferences = PreferenciasUsuario.empty
    var draftNivelMapping: [String: String] = [:]
    var draftCursoTipos: [String: TipoCurricular] = [:]
    var isLoading = false
    var errorMessage: String?
    var saveProfileStatus: ProfileSaveStatus = .idle
    var saveSchoolStatus: ProfileSaveStatus = .idle
    var savePreferencesStatus: ProfileSaveStatus = .idle
    var saveMappingStatus: ProfileSaveStatus = .idle

    private let repository: DashboardRepository

    init(repository: DashboardRepository) {
        self.repository = repository
    }

    func load() async {
        guard snapshot == nil else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard()
            snapshot = next
            draftProfile = next.profile
            draftSchool = next.school
            draftPreferences = next.preferences
            draftNivelMapping = next.nivelMapping
            draftCursoTipos = next.cursoTipos
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveProfile() async {
        saveProfileStatus = .saving
        do {
            try await repository.saveProfile(draftProfile)
            if var snapshot {
                snapshot.profile = draftProfile
                self.snapshot = snapshot
            }
            saveProfileStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            saveProfileStatus = .error
        }
    }

    func saveSchool() async {
        saveSchoolStatus = .saving
        do {
            try await repository.saveSchool(draftSchool)
            if var snapshot {
                snapshot.school = draftSchool
                self.snapshot = snapshot
            }
            saveSchoolStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            saveSchoolStatus = .error
        }
    }

    func savePreferences() async {
        savePreferencesStatus = .saving
        do {
            try await repository.savePreferences(draftPreferences)
            if var snapshot {
                snapshot.preferences = draftPreferences
                self.snapshot = snapshot
            }
            savePreferencesStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            savePreferencesStatus = .error
        }
    }

    func saveLevelMapping() async {
        saveMappingStatus = .saving
        do {
            try await repository.saveLevelMapping(draftNivelMapping, cursoTipos: draftCursoTipos)
            if var snapshot {
                snapshot.nivelMapping = draftNivelMapping
                snapshot.cursoTipos = draftCursoTipos
                self.snapshot = snapshot
            }
            saveMappingStatus = .saved
        } catch {
            errorMessage = error.localizedDescription
            saveMappingStatus = .error
        }
    }
}

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @State private var selectedTab: ProfileTabKey = .resumen
    @State private var showBannerPicker = false

    let user: AuthenticatedUser

    init(repository: DashboardRepository, user: AuthenticatedUser) {
        _viewModel = State(initialValue: ProfileViewModel(repository: repository))
        self.user = user
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    profileLoading
                } else if let snapshot = viewModel.snapshot {
                    if let error = viewModel.errorMessage {
                        ProfileErrorBanner(message: error)
                    }

                    profileHero(snapshot)
                    profileTabs
                    selectedContent(snapshot)
                } else {
                    profileEmpty
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Perfil")
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
        .sheet(isPresented: $showBannerPicker) {
            ProfileBannerSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
    }

    private func profileHero(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: bannerColors(for: viewModel.draftPreferences.bannerStyle),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 132)

                Button {
                    showBannerPicker = true
                } label: {
                    Image(systemName: "paintpalette.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.18), in: Circle())
                        .padding(12)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    AsyncUserAvatar(user: user)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(user.displayName ?? "Profesor EduPanel")
                            .font(.title2.weight(.black))
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            ProfilePill(text: snapshot.profile.tipoProfesor.isEmpty ? "Docente" : snapshot.profile.tipoProfesor, icon: "briefcase.fill")
                            if !snapshot.profile.especialidad.isEmpty {
                                ProfilePill(text: snapshot.profile.especialidad, icon: "music.note")
                            }
                        }

                        if !snapshot.school.nombre.isEmpty {
                            Label(snapshot.school.nombre, systemImage: "building.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("Configuracion")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(snapshot.setupProgress), total: 100)
                        .tint(snapshot.setupProgress == 100 ? .green : .pink)
                    Text("\(snapshot.setupProgress)%")
                        .font(.caption.weight(.black))
                        .foregroundStyle(snapshot.setupProgress == 100 ? .green : .pink)
                }

                LazyVGrid(columns: profileGrid, spacing: 10) {
                    ProfileKPI(label: "Cursos", value: "\(snapshot.courses.count)", icon: "folder.fill", color: .pink)
                    ProfileKPI(label: "Bloques clase", value: "\(snapshot.academicClasses.count)", icon: "clock.fill", color: .blue, hint: formatMinutes(snapshot.totalAcademicMinutes))
                    ProfileKPI(label: "Estudiantes", value: "\(snapshot.totalStudents)", icon: "person.2.fill", color: .green)
                    ProfileKPI(label: "PIE", value: "\(snapshot.totalPIEStudents)", icon: "number", color: .orange)
                    ProfileKPI(label: "Bloques libres", value: "\(snapshot.nonTeachingBlocks.count)", icon: "cup.and.saucer.fill", color: .purple, hint: formatMinutes(snapshot.totalFreeMinutes))
                    ProfileKPI(label: "Tu perfil", value: "\(snapshot.setupProgress)%", icon: "sparkles", color: snapshot.setupProgress == 100 ? .green : .teal)
                }
            }
            .padding(16)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
    }

    private var profileTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProfileTabKey.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .background(selectedTab == tab ? Color.pink : Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func selectedContent(_ snapshot: DashboardSnapshot) -> some View {
        switch selectedTab {
        case .resumen:
            profileSummary(snapshot)
        case .semana:
            profileWeek(snapshot)
        case .cursos:
            profileCourses(snapshot)
        case .asignaturas:
            profileSubjects(snapshot)
        case .identidad:
            ProfileIdentityTab(viewModel: viewModel)
        case .conexiones:
            ProfileConnectionsTab()
        }
    }

    private func profileSummary(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Mis cursos", icon: "folder.fill", hint: snapshot.courses.isEmpty ? "Aun no agregas ninguno" : "\(snapshot.courses.count) cursos") {
                if courseSummaries(snapshot).isEmpty {
                    ProfileEmptyAction(
                        icon: "calendar",
                        title: "No tienes cursos",
                        message: "Empieza creando bloques en Mi Semana.",
                        buttonTitle: "Crear primer bloque"
                    ) {
                        selectedTab = .semana
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(courseSummaries(snapshot)) { course in
                            Button {
                                selectedTab = .cursos
                            } label: {
                                ProfileCourseRow(course: course)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            ProfileSection(title: "Vista rapida de la semana", icon: "calendar", hint: nil) {
                MiniWeekView(snapshot: snapshot)
                Button {
                    selectedTab = .semana
                } label: {
                    Label("Ver semana completa", systemImage: "arrow.right")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.pink)
            }

            ProfileSection(title: "Tu progreso", icon: "sparkles", hint: "\(snapshot.setupProgress)%") {
                VStack(spacing: 10) {
                    ForEach(snapshot.setupChecklist) { item in
                        Button {
                            selectedTab = item.target
                        } label: {
                            ProfileChecklistRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ProfileSection(title: "Atajos rapidos", icon: "bolt.fill", hint: nil) {
                VStack(spacing: 8) {
                    ProfileShortcut(title: "Editar mi semana", icon: "calendar") { selectedTab = .semana }
                    ProfileShortcut(title: "Configurar mis cursos", icon: "folder.fill") { selectedTab = .cursos }
                    ProfileShortcut(title: "Asignaturas y niveles", icon: "book.closed.fill") { selectedTab = .asignaturas }
                    ProfileShortcut(title: "Datos del colegio", icon: "building.2.fill") { selectedTab = .identidad }
                    ProfileShortcut(title: "Conectar Google Calendar", icon: "link") { selectedTab = .conexiones }
                }
            }
        }
    }

    private func profileWeek(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Constructor de horario", icon: "calendar", hint: "Crea bloques de clases o libres") {
                Text("Vista visual de tu semana. Toca un bloque o usa Nuevo bloque para continuar el flujo en una pantalla dedicada.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                NavigationLink(value: AppRoute.perfilAction("Nuevo bloque")) {
                    Label("Nuevo bloque", systemImage: "plus")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }

            ForEach(DateHelpers.workdays, id: \.self) { day in
                let items = snapshot.horario
                    .filter { $0.dia == day }
                    .sorted { $0.horaInicio < $1.horaInicio }

                ProfileSection(title: day, icon: "calendar.day.timeline.left", hint: items.isEmpty ? "Sin bloques" : "\(items.count) bloques") {
                    if items.isEmpty {
                        Text("Sin bloques programados.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(items) { item in
                                NavigationLink(value: AppRoute.claseDetalle(item.id)) {
                                    ProfileScheduleRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func profileCourses(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            if courseSummaries(snapshot).isEmpty {
                ProfileEmptyAction(
                    icon: "folder.badge.plus",
                    title: "Sin cursos",
                    message: "Agrega bloques lectivos en Mi Semana para crear cursos.",
                    buttonTitle: "Ir a Mi Semana"
                ) {
                    selectedTab = .semana
                }
            } else {
                ForEach(courseSummaries(snapshot)) { course in
                    ProfileSection(title: course.name, icon: "folder.fill", hint: course.levelText) {
                        ProfileCourseRow(course: course)

                        if course.studentsPreview.isEmpty {
                            Text("Aun no hay estudiantes cargados para este curso.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(course.studentsPreview) { student in
                                    HStack(spacing: 10) {
                                        Text("\(student.orden)")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 30, height: 30)
                                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                                        Text(student.nombre)
                                            .font(.footnote.weight(.semibold))
                                        Spacer()
                                        if student.pie {
                                            Text("PIE")
                                                .font(.caption2.weight(.black))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(.orange.opacity(0.14), in: Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            NavigationLink(value: AppRoute.perfilAction("Gestionar estudiantes")) {
                                Label("Estudiantes", systemImage: "person.2.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            NavigationLink(value: AppRoute.perfilAction("Editar curso")) {
                                Label("Editar", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .font(.footnote.weight(.black))
                        .buttonStyle(.bordered)
                        .tint(.pink)
                    }
                }
            }
        }
    }

    private func profileSubjects(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Asignaturas que enseno", icon: "book.closed.fill", hint: "Selector web") {
                let subjects = subjectCandidates(snapshot)

                if subjects.isEmpty {
                    Text("No hay asignaturas detectadas en tu horario. Agrega bloques con asignatura en Mi Semana.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    ProfileSaveBadge(status: viewModel.savePreferencesStatus)

                    VStack(spacing: 8) {
                        ForEach(subjects, id: \.self) { subject in
                            Button {
                                toggleSubject(subject, candidates: subjects)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSubjectEnabled(subject, candidates: subjects) ? "checkmark.square.fill" : "square")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(isSubjectEnabled(subject, candidates: subjects) ? .pink : .secondary)
                                    Text(subject)
                                        .font(.footnote.weight(.semibold))
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            viewModel.draftPreferences.asignaturasHabilitadas = []
                        } label: {
                            Label("Mostrar todas", systemImage: "checklist")
                                .frame(maxWidth: .infinity)
                        }

                        Button {
                            Task { await viewModel.savePreferences() }
                        } label: {
                            Label("Guardar", systemImage: viewModel.savePreferencesStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(viewModel.savePreferencesStatus == .saving)
                    }
                    .font(.footnote.weight(.black))
                    .buttonStyle(.bordered)
                    .tint(.pink)
                }
            }

            ProfileSection(title: "Mapeo de niveles curriculares", icon: "graduationcap.fill", hint: "Mineduc") {
                if snapshot.courses.isEmpty {
                    Text("Primero agrega cursos en Mi Semana.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    ProfileSaveBadge(status: viewModel.saveMappingStatus)

                    VStack(spacing: 10) {
                        ForEach(snapshot.courses, id: \.self) { course in
                            let tipo = viewModel.draftCursoTipos[course] ?? .oficial
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(course)
                                        .font(.footnote.weight(.black))
                                    if tipo == .oficial && (viewModel.draftNivelMapping[course] ?? "").isEmpty {
                                        Text("Falta seleccionar nivel curricular.")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Picker("Tipo curricular", selection: Binding(
                                    get: { viewModel.draftCursoTipos[course] ?? .oficial },
                                    set: { next in setCourseType(next, for: course) }
                                )) {
                                    Text(TipoCurricular.oficial.label).tag(TipoCurricular.oficial)
                                    Text(TipoCurricular.taller.label).tag(TipoCurricular.taller)
                                    Text(TipoCurricular.libre.label).tag(TipoCurricular.libre)
                                }
                                .pickerStyle(.segmented)

                                if tipo == .oficial {
                                    Picker("Nivel curricular", selection: Binding(
                                        get: { viewModel.draftNivelMapping[course] ?? "" },
                                        set: { viewModel.draftNivelMapping[course] = $0 }
                                    )) {
                                        Text("Sin configurar").tag("")
                                        ForEach(CurriculumLevels.all, id: \.self) { level in
                                            Text(level).tag(level)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Label(tipo == .taller ? "Sin nivel curricular para taller/electivo." : "Sin curriculum oficial para uso libre.", systemImage: "info.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Button {
                        Task { await viewModel.saveLevelMapping() }
                    } label: {
                        Label("Guardar niveles", systemImage: viewModel.saveMappingStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .font(.footnote.weight(.black))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(viewModel.saveMappingStatus == .saving)
                }
            }
        }
    }

    private var profileLoading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando Mi Perfil...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var profileEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No se pudo cargar Mi Perfil")
                .font(.headline)
            Button("Reintentar") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var profileGrid: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private func courseSummaries(_ snapshot: DashboardSnapshot) -> [ProfileCourseSummary] {
        snapshot.courses.map { course in
            let blocks = snapshot.academicClasses.filter { $0.resumen == course }
            let minutes = blocks.reduce(0) { total, item in
                total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            }
            let students = snapshot.studentsByCourse[course] ?? []
            let subjects = Array(Set(blocks.compactMap(\.asignatura))).sorted()
            let type = snapshot.cursoTipos[course] ?? .oficial
            return ProfileCourseSummary(
                name: course,
                colorHex: blocks.first?.colorHex ?? "#EC4899",
                blocks: blocks.count,
                minutes: minutes,
                students: students.count,
                pie: students.filter(\.pie).count,
                level: snapshot.nivelMapping[course],
                type: type,
                subjects: subjects,
                studentsPreview: Array(students.prefix(5))
            )
        }
    }

    private func subjectCandidates(_ snapshot: DashboardSnapshot) -> [String] {
        Array(Set(snapshot.academicClasses.compactMap(\.asignatura) + viewModel.draftPreferences.asignaturasHabilitadas))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
    }

    private func isSubjectEnabled(_ subject: String, candidates: [String]) -> Bool {
        let enabled = viewModel.draftPreferences.asignaturasHabilitadas
        return enabled.isEmpty ? candidates.contains(subject) : enabled.contains(subject)
    }

    private func toggleSubject(_ subject: String, candidates: [String]) {
        var enabled = viewModel.draftPreferences.asignaturasHabilitadas
        if enabled.isEmpty {
            enabled = candidates
        }

        if enabled.contains(subject) {
            enabled.removeAll { $0 == subject }
        } else {
            enabled.append(subject)
        }

        viewModel.draftPreferences.asignaturasHabilitadas = enabled.sorted()
    }

    private func setCourseType(_ type: TipoCurricular, for course: String) {
        if type == .oficial {
            viewModel.draftCursoTipos.removeValue(forKey: course)
        } else {
            viewModel.draftCursoTipos[course] = type
            viewModel.draftNivelMapping.removeValue(forKey: course)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0 h" }
        let hours = Double(minutes) / 60.0
        if minutes % 60 == 0 {
            return "\(minutes / 60) h"
        }
        return String(format: "%.1f h", hours)
    }

    private func bannerColors(for style: String) -> [Color] {
        switch style {
        case "oceano": return [.cyan, .blue]
        case "atardecer": return [.orange, .pink, .purple]
        case "esmeralda": return [.green, .teal]
        case "indigo": return [.indigo, .purple]
        case "grafito": return [.gray, .black]
        case "bosque": return [.green, .mint]
        case "lavanda": return [.purple, .pink]
        default: return [.pink, .red]
        }
    }
}

private struct ProfileIdentityTab: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Datos profesionales", icon: "briefcase.fill", hint: nil) {
                ProfileSaveBadge(status: viewModel.saveProfileStatus)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tipo de docente")
                            .profileFieldLabel()
                        Picker("Tipo de docente", selection: $viewModel.draftProfile.tipoProfesor) {
                            Text("Selecciona tu rol").tag("")
                            Text("Profesor(a) de Ed. General Basica").tag("General Basica")
                            Text("Profesor(a) de Educacion Media").tag("Media")
                            Text("Educador(a) Diferencial").tag("Diferencial")
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ProfileTextField(title: "Especialidad / Asignatura", placeholder: "Ej: Musica", text: $viewModel.draftProfile.especialidad)
                    ProfileTextField(title: "Estudios y titulos", placeholder: "Profesor de...", text: $viewModel.draftProfile.estudios)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Biografia")
                            .profileFieldLabel()
                        TextEditor(text: $viewModel.draftProfile.biografia)
                            .frame(minHeight: 96)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        Task { await viewModel.saveProfile() }
                    } label: {
                        Label("Guardar datos profesionales", systemImage: viewModel.saveProfileStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(viewModel.saveProfileStatus == .saving)
                }
            }

            ProfileSection(title: "Mi colegio", icon: "building.2.fill", hint: "Exportaciones") {
                ProfileSaveBadge(status: viewModel.saveSchoolStatus)

                VStack(alignment: .leading, spacing: 14) {
                    ProfileTextField(title: "Nombre del colegio", placeholder: "Ej: Colegio San Ignacio", text: $viewModel.draftSchool.nombre)

                    HStack(spacing: 12) {
                        SchoolLogoView(base64: viewModel.draftSchool.logoBase64)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(viewModel.draftSchool.logoBase64 == nil ? "Sin logo principal" : "Logo principal configurado")
                                .font(.footnote.weight(.black))
                            Text("La subida/cambio de imagen queda reservada para la pantalla dedicada.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink(value: AppRoute.perfilAction("Subir logo del colegio")) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline.weight(.bold))
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Toggle("Activar encabezado de exportaciones", isOn: $viewModel.draftSchool.encabezadoHabilitado)
                        .font(.footnote.weight(.black))

                    if viewModel.draftSchool.encabezadoHabilitado {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Lado izquierdo")
                                .profileFieldLabel()
                            TextEditor(text: $viewModel.draftSchool.encabezadoTextoIzq)
                                .frame(minHeight: 74)
                                .padding(8)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Lado derecho")
                                .profileFieldLabel()
                            TextEditor(text: $viewModel.draftSchool.encabezadoTextoDer)
                                .frame(minHeight: 74)
                                .padding(8)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    Button {
                        Task { await viewModel.saveSchool() }
                    } label: {
                        Label("Guardar colegio", systemImage: viewModel.saveSchoolStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(viewModel.saveSchoolStatus == .saving)
                }
            }
        }
    }
}

private struct ProfileConnectionsTab: View {
    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Google Calendar", icon: "calendar", hint: "Sincroniza actividades") {
                ConnectionStatusCard(
                    title: "Estado de la conexion",
                    message: "Conecta tu cuenta de Google para enviar actividades y enlaces de apoyo.",
                    isConnected: false
                )

                HStack(spacing: 10) {
                    NavigationLink(value: AppRoute.perfilAction("Conectar Google Calendar")) {
                        Label("Conectar", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    NavigationLink(value: AppRoute.perfilAction("Sincronizar Calendar")) {
                        Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.footnote.weight(.black))
                .buttonStyle(.bordered)
                .tint(.pink)
            }

            ProfileSection(title: "Google Drive personal", icon: "externaldrive.fill", hint: "Carpetas privadas") {
                ConnectionStatusCard(
                    title: "Estado de la conexion",
                    message: "Tu Drive personal queda disponible para planificaciones, unidades, pruebas y guias cuando lo autorices.",
                    isConnected: false
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("Privado por docente", systemImage: "checkmark.shield.fill")
                        .font(.footnote.weight(.black))
                    Text("EduPanel crea carpetas solo en tu Drive personal cuando lo autorizas. Guarda enlaces e IDs minimos para volver rapido.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                NavigationLink(value: AppRoute.perfilAction("Conectar Google Drive")) {
                    Label("Conectar Drive", systemImage: "link")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }
        }
    }
}

private struct ProfileCourseSummary: Identifiable {
    var id: String { name }
    let name: String
    let colorHex: String
    let blocks: Int
    let minutes: Int
    let students: Int
    let pie: Int
    let level: String?
    let type: TipoCurricular
    let subjects: [String]
    let studentsPreview: [EstudiantePerfil]

    var levelText: String {
        if type != .oficial {
            return type.label
        }
        return level ?? "Sin nivel"
    }
}

private struct ProfileBannerPreset: Identifiable {
    let id: String
    let title: String
    let colors: [Color]
}

private let profileBannerPresets: [ProfileBannerPreset] = [
    ProfileBannerPreset(id: "rosa", title: "Rosa", colors: [.pink, .red]),
    ProfileBannerPreset(id: "oceano", title: "Oceano", colors: [.cyan, .blue]),
    ProfileBannerPreset(id: "atardecer", title: "Atardecer", colors: [.orange, .pink, .purple]),
    ProfileBannerPreset(id: "esmeralda", title: "Esmeralda", colors: [.green, .teal]),
    ProfileBannerPreset(id: "indigo", title: "Indigo", colors: [.indigo, .purple]),
    ProfileBannerPreset(id: "grafito", title: "Grafito", colors: [.gray, .black]),
    ProfileBannerPreset(id: "bosque", title: "Bosque", colors: [.green, .mint]),
    ProfileBannerPreset(id: "lavanda", title: "Lavanda", colors: [.purple, .pink])
]

private struct ProfileBannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(profileBannerPresets) { preset in
                        Button {
                            viewModel.draftPreferences.bannerStyle = preset.id
                            Task {
                                await viewModel.savePreferences()
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .frame(height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                HStack {
                                    Text(preset.title)
                                        .font(.footnote.weight(.black))
                                    Spacer()
                                    if viewModel.draftPreferences.bannerStyle == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .navigationTitle("Fondo del perfil")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

private struct ProfileSection<Content: View>: View {
    let title: String
    let icon: String
    let hint: String?
    let content: Content

    init(title: String, icon: String, hint: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.pink)
                Text(title)
                    .font(.subheadline.weight(.black))
                if let hint {
                    Text(hint)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
    }
}

private struct ProfileKPI: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var hint: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.black))
                if let hint {
                    Text(hint)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileCourseRow: View {
    let course: ProfileCourseSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(profileHex: course.colorHex))
                .frame(width: 12, height: 12)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(course.name)
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                    if course.levelText == "Sin nivel" {
                        Text("Sin nivel")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.14), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Label("\(course.blocks) bloques", systemImage: "clock")
                    Label("\(course.students) alumnos", systemImage: "person.2.fill")
                    if course.pie > 0 {
                        Label("\(course.pie) PIE", systemImage: "number")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Text(course.levelText)
                    .font(.caption.weight(.black))
                    .foregroundStyle(course.levelText == "Sin nivel" ? .orange : .pink)

                if !course.subjects.isEmpty {
                    FlowChips(items: course.subjects, color: .blue)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileChecklistRow: View {
    let item: ProfileSetupItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.headline.weight(.bold))
                .foregroundStyle(item.isComplete ? .green : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.footnote.weight(.black))
                    .strikethrough(item.isComplete)
                    .foregroundStyle(item.isComplete ? .green : .primary)
                if let hint = item.hint, !hint.isEmpty {
                    Text(hint)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            if !item.isComplete {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(item.isComplete ? Color.green.opacity(0.1) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileShortcut: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MiniWeekView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(DateHelpers.workdays, id: \.self) { day in
                VStack(spacing: 6) {
                    Text(String(day.prefix(3)).uppercased())
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.secondary)
                    let items = snapshot.horario.filter { $0.dia == day }.sorted { $0.horaInicio < $1.horaInicio }
                    if items.isEmpty {
                        Text("-")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        VStack(spacing: 4) {
                            ForEach(items.prefix(3)) { item in
                                VStack(spacing: 1) {
                                    Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                                        .font(.system(size: 8, weight: .black))
                                        .lineLimit(1)
                                    Text(item.horaInicio)
                                        .font(.system(size: 7, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color(profileHex: item.colorHex), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ProfileScheduleRow: View {
    let item: ClaseHorario

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(String(item.horaInicio.prefix(2)))
                    .font(.headline.weight(.black))
                Text(String(item.horaInicio.suffix(2)))
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 50)
            .background(Color(profileHex: item.colorHex), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                    .font(.footnote.weight(.black))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.timeRange)
                    Text(item.tipo.label)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer()
            if item.tipo.isFreeBlock {
                Text("No lectivo")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileEmptyAction: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.black))
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Label(buttonTitle, systemImage: "arrow.right")
                    .font(.footnote.weight(.black))
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FlowChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(color)
                .background(color.opacity(0.12), in: Capsule())
        }
    }
}

private struct ProfilePill: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.black))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(.pink)
            .background(.pink.opacity(0.12), in: Capsule())
    }
}

private struct AsyncUserAvatar: View {
    let user: AuthenticatedUser

    var body: some View {
        Group {
            if let url = user.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var avatarFallback: some View {
        ZStack {
            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String((user.displayName ?? "P").prefix(1)).uppercased())
                .font(.title.weight(.black))
                .foregroundStyle(.white)
        }
    }
}

private struct ProfileErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileSaveBadge: View {
    let status: ProfileSaveStatus

    var body: some View {
        if status != .idle {
            Label(status.title, systemImage: status == .saving ? "hourglass" : status == .saved ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(status.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProfileTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .profileFieldLabel()
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.footnote.weight(.semibold))
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct SchoolLogoView: View {
    let base64: String?

    var body: some View {
        Group {
            if let image = decodedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                Image(systemName: "building.2.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.55))
            }
        }
        .frame(width: 62, height: 62)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var decodedImage: UIImage? {
        guard let base64, !base64.isEmpty else { return nil }
        let raw = base64.components(separatedBy: ",").last ?? base64
        guard let data = Data(base64Encoded: raw) else { return nil }
        return UIImage(data: data)
    }
}

private struct ConnectionStatusCard: View {
    let title: String
    let message: String
    let isConnected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.footnote.weight(.black))
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(isConnected ? "Conectado" : "Desconectado")
                .font(.caption2.weight(.black))
                .foregroundStyle(isConnected ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isConnected ? Color.green.opacity(0.14) : Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension Text {
    func profileFieldLabel() -> some View {
        self.font(.system(size: 10, weight: .black))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private extension Color {
    init(profileHex: String) {
        let clean = profileHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else {
            self = .pink
            return
        }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else {
            self = .pink
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
