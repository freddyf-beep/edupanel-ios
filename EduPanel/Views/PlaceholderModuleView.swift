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

                Text(route.placeholderText)
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
                    Text("Configuración")
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
            ProfileSection(title: "Mis cursos", icon: "folder.fill", hint: snapshot.courses.isEmpty ? "Aún no agregas ninguno" : "\(snapshot.courses.count) cursos") {
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

            ProfileSection(title: "Vista rápida de la semana", icon: "calendar", hint: nil) {
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

            ProfileSection(title: "Atajos rápidos", icon: "bolt.fill", hint: nil) {
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
        let nonTeachingList = nonTeachingGroups(snapshot)

        return VStack(spacing: 18) {
            ProfileSection(title: "Constructor de horario", icon: "calendar", hint: "Crea bloques de clases o libres") {
                Text("Vista visual de tu semana. Toca un bloque o usa Nuevo bloque para continuar el flujo en una pantalla dedicada.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                NavigationLink(value: AppRoute.newScheduleBlock) {
                    Label("Nuevo bloque", systemImage: "plus")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }

            if !nonTeachingList.isEmpty {
                ProfileSection(title: "Bloques no lectivos", icon: "cup.and.saucer.fill", hint: "\(nonTeachingList.count) grupos") {
                    Text("Estos bloques se ven en tu semana, pero no cuentan como clase, pendiente, leccionario ni asistencia.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: profileGrid, spacing: 10) {
                        ForEach(nonTeachingList) { group in
                            ProfileNonTeachingGroupRow(group: group)
                        }
                    }
                }
            }

            ProfileSection(title: "Vista calendario", icon: "calendar", hint: "\(snapshot.horario.count) bloques · \(weekHourRange(snapshot).label)") {
                if snapshot.horario.isEmpty {
                    ProfileEmptyAction(
                        icon: "calendar.badge.plus",
                        title: "Tu semana está vacía",
                        message: "Agrega tu primer bloque arriba para ver la grilla semanal.",
                        buttonTitle: "Nuevo bloque"
                    ) {
                        selectedTab = .semana
                    }
                } else {
                    ProfileWeekCalendar(snapshot: snapshot)
                }
            }

            ProfileSection(title: "Lista detallada", icon: "clock.fill", hint: "Edita o revisa bloques uno por uno") {
                if snapshot.horario.isEmpty {
                    Text("Sin bloques aún.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(DateHelpers.workdays, id: \.self) { day in
                            let items = snapshot.horario
                                .filter { $0.dia == day }
                                .sorted { $0.horaInicio < $1.horaInicio }

                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(day.uppercased())
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.secondary)
                                    VStack(spacing: 8) {
                                        ForEach(items) { item in
                                            NavigationLink(value: AppRoute.classDetail(id: item.id, title: routeTitle(for: item))) {
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
                        ProfileCourseReplicaCard(course: course)
                    }
                }
            }
        }
    }

    private func profileSubjects(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Asignaturas que enseño", icon: "book.closed.fill", hint: "Selector web") {
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
                weeklyBlocks: blocks.sorted {
                    let leftDay = DateHelpers.workdays.firstIndex(of: $0.dia) ?? 0
                    let rightDay = DateHelpers.workdays.firstIndex(of: $1.dia) ?? 0
                    if leftDay != rightDay { return leftDay < rightDay }
                    return $0.horaInicio < $1.horaInicio
                },
                studentsList: students.sorted { $0.orden < $1.orden }
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

    private func weekHourRange(_ snapshot: DashboardSnapshot) -> (minHour: Int, maxHour: Int, label: String) {
        guard !snapshot.horario.isEmpty else { return (8, 18, "8:00-18:00") }
        let minMinutes = max(0, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaInicio) }.min() ?? 8 * 60) - 30)
        let maxMinutes = min(24 * 60, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaFin) }.max() ?? 18 * 60) + 30)
        let minHour = max(0, minMinutes / 60)
        let maxHour = min(24, Int(ceil(Double(maxMinutes) / 60.0)))
        return (minHour, maxHour, "\(minHour):00-\(maxHour):00")
    }

    private func nonTeachingGroups(_ snapshot: DashboardSnapshot) -> [ProfileNonTeachingGroup] {
        let grouped = Dictionary(grouping: snapshot.nonTeachingBlocks) { item in
            "\(item.tipo.rawValue)::\(item.resumen.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }

        return grouped.compactMap { key, blocks in
            let sorted = blocks.sorted {
                let leftDay = DateHelpers.workdays.firstIndex(of: $0.dia) ?? 0
                let rightDay = DateHelpers.workdays.firstIndex(of: $1.dia) ?? 0
                if leftDay != rightDay { return leftDay < rightDay }
                return $0.horaInicio < $1.horaInicio
            }
            guard let first = sorted.first else { return nil }
            let sameTime = sorted.allSatisfy { $0.horaInicio == first.horaInicio && $0.horaFin == first.horaFin }
            let total = sorted.reduce(0) { total, item in
                total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            }

            return ProfileNonTeachingGroup(
                id: key,
                title: first.resumen.isEmpty ? first.tipo.label : first.resumen,
                typeLabel: first.tipo.label,
                colorHex: first.colorHex,
                days: sorted.map(\.dia),
                timeLabel: sameTime ? "\(first.horaInicio)-\(first.horaFin)" : "Horarios distintos",
                totalMinutes: total
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func routeTitle(for item: ClaseHorario) -> String {
        let title = item.resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.tipo.label : title
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
                            Text("Profesor(a) de Ed. General Básica").tag("General Básica")
                            Text("Profesor(a) de Educación Media").tag("Media")
                            Text("Educador(a) Diferencial").tag("Diferencial")
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ProfileTextField(title: "Especialidad / Asignatura", placeholder: "Ej: Música", text: $viewModel.draftProfile.especialidad)
                    ProfileTextField(title: "Estudios y títulos", placeholder: "Profesor de...", text: $viewModel.draftProfile.estudios)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Biografía")
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
                        NavigationLink(value: AppRoute.schoolLogo) {
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
                    title: "Estado de la conexión",
                    message: "Conecta tu cuenta de Google para enviar actividades y enlaces de apoyo.",
                    isConnected: false
                )

                HStack(spacing: 10) {
                    NavigationLink(value: AppRoute.calendarConnect) {
                        Label("Conectar", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    NavigationLink(value: AppRoute.calendarSync) {
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
                    title: "Estado de la conexión",
                    message: "Tu Drive personal queda disponible para planificaciones, unidades, pruebas y guías cuando lo autorices.",
                    isConnected: false
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("Privado por docente", systemImage: "checkmark.shield.fill")
                        .font(.footnote.weight(.black))
                    Text("EduPanel crea carpetas solo en tu Drive personal cuando lo autorizas. Guarda enlaces e IDs mínimos para volver rápido.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                NavigationLink(value: AppRoute.driveConnect) {
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

private struct ProfileNonTeachingGroup: Identifiable {
    let id: String
    let title: String
    let typeLabel: String
    let colorHex: String
    let days: [String]
    let timeLabel: String
    let totalMinutes: Int
}

private struct ProfileNonTeachingGroupRow: View {
    let group: ProfileNonTeachingGroup

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(profileHex: group.colorHex))
                .frame(width: 12, height: 12)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(group.title)
                        .font(.footnote.weight(.black))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Text(group.typeLabel)
                    Text(group.timeLabel)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Text("\(group.days.joined(separator: ", ")) · \(ProfileFormat.minutes(group.totalMinutes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileWeekCalendar: View {
    let snapshot: DashboardSnapshot

    private let dayWidth: CGFloat = 128
    private let hourColumnWidth: CGFloat = 52
    private let pixelsPerMinute: CGFloat = 0.92

    var body: some View {
        let range = hourRange
        let totalMinutes = max(60, (range.maxHour - range.minHour) * 60)
        let calendarHeight = CGFloat(totalMinutes) * pixelsPerMinute

        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 6) {
                    Text("")
                        .frame(height: 28)
                    ZStack(alignment: .topLeading) {
                        ForEach(range.minHour...range.maxHour, id: \.self) { hour in
                            Text("\(hour):00")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)
                                .offset(y: CGFloat((hour - range.minHour) * 60) * pixelsPerMinute - 2)
                        }
                    }
                    .frame(width: hourColumnWidth, height: calendarHeight, alignment: .topLeading)
                }

                ForEach(DateHelpers.workdays, id: \.self) { day in
                    VStack(spacing: 6) {
                        Text(day)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.primary)
                            .textCase(.uppercase)
                            .frame(width: dayWidth, height: 28)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(.systemGroupedBackground))

                            ForEach(0...(range.maxHour - range.minHour), id: \.self) { index in
                                Rectangle()
                                    .fill(Color(.separator).opacity(0.35))
                                    .frame(height: 1)
                                    .offset(y: CGFloat(index * 60) * pixelsPerMinute)
                            }

                            ForEach(blocks(for: day)) { item in
                                NavigationLink(value: AppRoute.classDetail(id: item.id, title: routeTitle(for: item))) {
                                    calendarBlock(item, minHour: range.minHour)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: dayWidth, height: calendarHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .padding(8)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var hourRange: (minHour: Int, maxHour: Int) {
        guard !snapshot.horario.isEmpty else { return (8, 18) }
        let minMinutes = max(0, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaInicio) }.min() ?? 8 * 60) - 30)
        let maxMinutes = min(24 * 60, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaFin) }.max() ?? 18 * 60) + 30)
        return (max(0, minMinutes / 60), min(24, Int(ceil(Double(maxMinutes) / 60.0))))
    }

    private func blocks(for day: String) -> [ClaseHorario] {
        snapshot.horario
            .filter { $0.dia == day }
            .sorted { $0.horaInicio < $1.horaInicio }
    }

    private func calendarBlock(_ item: ClaseHorario, minHour: Int) -> some View {
        let start = DateHelpers.minutes(from: item.horaInicio)
        let end = DateHelpers.minutes(from: item.horaFin)
        let top = max(0, CGFloat(start - minHour * 60) * pixelsPerMinute)
        let height = max(28, CGFloat(max(15, end - start)) * pixelsPerMinute - 2)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: item.tipo.isFreeBlock ? "cup.and.saucer.fill" : "book.closed.fill")
                    .font(.system(size: 9, weight: .black))
                Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                    .font(.system(size: 10, weight: .black))
                    .lineLimit(1)
            }

            if let asignatura = item.asignatura, !asignatura.isEmpty, height >= 38 {
                Text(asignatura)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
            }

            if height >= 48 {
                Text(item.timeRange)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: dayWidth - 8, height: height, alignment: .topLeading)
        .background(Color(profileHex: item.colorHex).opacity(item.tipo.isFreeBlock ? 0.88 : 1.0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
        .offset(x: 4, y: top)
    }

    private func routeTitle(for item: ClaseHorario) -> String {
        let title = item.resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.tipo.label : title
    }
}

private enum ProfileFormat {
    static func minutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0 h" }
        if minutes % 60 == 0 {
            return "\(minutes / 60) h"
        }
        return String(format: "%.1f h", Double(minutes) / 60.0)
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
    let weeklyBlocks: [ClaseHorario]
    let studentsList: [EstudiantePerfil]

    var levelText: String {
        if type != .oficial {
            return type.label
        }
        return level ?? "Sin nivel"
    }

    var subjectSchedules: [ProfileSubjectSchedule] {
        let grouped = Dictionary(grouping: weeklyBlocks) { item in
            let subject = item.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return subject.isEmpty ? "Sin asignatura" : subject
        }
        let declaredSubjects = subjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let subjectNames = Set(grouped.keys).union(declaredSubjects)

        return subjectNames.map { subject in
            let blocks = grouped[subject] ?? []
            let sorted = blocks.sorted {
                let leftDay = DateHelpers.workdays.firstIndex(of: $0.dia) ?? 0
                let rightDay = DateHelpers.workdays.firstIndex(of: $1.dia) ?? 0
                if leftDay != rightDay { return leftDay < rightDay }
                return $0.horaInicio < $1.horaInicio
            }
            let minutes = sorted.reduce(0) { total, item in
                total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            }
            return ProfileSubjectSchedule(
                subject: subject,
                colorHex: sorted.first?.colorHex ?? colorHex,
                blocks: sorted,
                minutes: minutes
            )
        }
        .sorted {
            if $0.isMissingSubject { return false }
            if $1.isMissingSubject { return true }
            return $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending
        }
    }
}

private struct ProfileSubjectSchedule: Identifiable {
    var id: String { subject }
    let subject: String
    let colorHex: String
    let blocks: [ClaseHorario]
    let minutes: Int

    var isMissingSubject: Bool {
        subject == "Sin asignatura"
    }
}

private struct ProfileCourseReplicaCard: View {
    let course: ProfileCourseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(profileHex: course.colorHex))
                .frame(height: 6)

            VStack(alignment: .leading, spacing: 14) {
                header
                curriculumBlock
                subjectsBlock
                studentsBlock
                actions
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.22), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(profileHex: course.colorHex))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 7) {
                Text(course.name)
                    .font(.title3.weight(.black))
                    .lineLimit(2)

                ReplicaFlowLayout(spacing: 7) {
                    profileMetricChip("\(course.subjectSchedules.count) asignaturas", icon: "book.closed.fill", tint: .blue)
                    profileMetricChip("\(course.blocks) bloques", icon: "clock.fill", tint: .purple)
                    profileMetricChip(ProfileFormat.minutes(course.minutes), icon: "timer", tint: .green)
                    profileMetricChip("\(course.students) alumnos", icon: "person.2.fill", tint: .pink)
                    if course.pie > 0 {
                        profileMetricChip("\(course.pie) PIE", icon: "number", tint: .orange)
                    }
                }
            }
        }
    }

    private var curriculumBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tipo de curso y nivel curricular")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 10) {
                profileStatusPill(course.type.label, icon: "graduationcap.fill", tint: course.type == .oficial ? .pink : .secondary)

                if course.type == .oficial {
                    if let level = course.level, !level.isEmpty {
                        profileStatusPill(level, icon: "checkmark.seal.fill", tint: .green)
                    } else {
                        profileStatusPill("Sin nivel", icon: "exclamationmark.triangle.fill", tint: .orange)
                    }
                } else {
                    Text(course.type == .taller ? "Este curso no requiere nivel curricular Mineduc." : "Curso libre sin currículo asociado.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var subjectsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Asignaturas y horario", systemImage: "book.closed.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                EPPlaceholderActionButton(
                    title: "Asignatura",
                    icon: "plus",
                    message: "La web permite crear asignaturas y abrir el formulario de bloque. En iOS queda visible hasta conectar el editor completo."
                )
            }

            if course.subjectSchedules.isEmpty {
                Text("Este curso aún no tiene asignaturas. Agrega bloques en Mi Semana para comenzar.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(18)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(course.subjectSchedules) { schedule in
                        ProfileSubjectScheduleRow(schedule: schedule)
                    }
                }
            }
        }
    }

    private var studentsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Estudiantes", systemImage: "person.2.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(course.students) alumnos")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
            }

            if course.studentsList.isEmpty {
                Text("Aún no hay estudiantes. La web permite importarlos desde JSON o agregarlos manualmente.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(18)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(course.studentsList.prefix(8))) { student in
                        ProfileStudentRow(student: student)
                        if student.id != course.studentsList.prefix(8).last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }

                    if course.studentsList.count > 8 {
                        Text("+ \(course.studentsList.count - 8) estudiantes más")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }
                }
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            NavigationLink(value: AppRoute.courseStudents(course.name)) {
                Label("Estudiantes", systemImage: "person.2.fill")
                    .frame(maxWidth: .infinity)
            }
            NavigationLink(value: AppRoute.editCourse(course.name)) {
                Label("Editar", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            NavigationLink(value: AppRoute.coursePlanificaciones(curso: course.name, asignatura: nil)) {
                Label("Planificar", systemImage: "book.closed.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption.weight(.black))
        .buttonStyle(.bordered)
        .tint(.pink)
    }

    private func profileMetricChip(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.black))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func profileStatusPill(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.black))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct ProfileSubjectScheduleRow: View {
    let schedule: ProfileSubjectSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if schedule.isMissingSubject {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.orange)
                } else {
                    Circle()
                        .fill(Color(profileHex: schedule.colorHex))
                        .frame(width: 10, height: 10)
                }

                Text(schedule.subject)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(schedule.isMissingSubject ? .orange : .primary)
                    .lineLimit(1)

                Spacer()

                Text("\(schedule.blocks.count) bloques · \(ProfileFormat.minutes(schedule.minutes))")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(schedule.blocks) { block in
                    NavigationLink(value: AppRoute.classDetail(id: block.id, title: block.resumen.isEmpty ? block.tipo.label : block.resumen)) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(profileHex: block.colorHex))
                                .frame(width: 8, height: 8)
                            Text(block.dia)
                                .font(.caption.weight(.black))
                            Spacer(minLength: 4)
                            Text(block.timeRange)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(schedule.isMissingSubject ? Color.orange.opacity(0.10) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(schedule.isMissingSubject ? Color.orange.opacity(0.30) : Color(.separator).opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ProfileStudentRow: View {
    let student: EstudiantePerfil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(student.orden)")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemGroupedBackground), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(student.nombre)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)

                if student.pie {
                    let detail = [student.pieDiagnostico, student.pieEspecialista, student.pieNotas]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if !detail.isEmpty {
                        Text(detail.joined(separator: " · "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct ProfileBannerPreset: Identifiable {
    let id: String
    let title: String
    let colors: [Color]
}

private let profileBannerPresets: [ProfileBannerPreset] = [
    ProfileBannerPreset(id: "rosa", title: "Rosa", colors: [.pink, .red]),
    ProfileBannerPreset(id: "oceano", title: "Océano", colors: [.cyan, .blue]),
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
