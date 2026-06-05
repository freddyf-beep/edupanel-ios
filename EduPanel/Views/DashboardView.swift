import Foundation
import SwiftUI

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var selectedDay = DateHelpers.weekdayName(for: Date()) ?? "Lunes"
    @State private var newReminder = ""
    @State private var reminderColor: ReminderColor = .amarillo
    @AppStorage("edupanel_dashboard_reminders") private var remindersData = "[]"

    let user: AuthenticatedUser
    let onOpenProfile: () -> Void

    init(repository: DashboardRepository, user: AuthenticatedUser, onOpenProfile: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: DashboardViewModel(repository: repository))
        self.user = user
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    loadingState
                } else if let snapshot = viewModel.snapshot {
                    dashboardContent(snapshot)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Inicio")
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    private func dashboardContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            heroCard(snapshot)

            if snapshot.horario.isEmpty {
                noScheduleCard
            } else {
                quickActions(snapshot)
                courseStats(snapshot)
                todayTimeline(snapshot)
                pendingPanel(snapshot)
                remindersAndInsights(snapshot)
            }
        }
    }

    private func heroCard(_ snapshot: DashboardSnapshot) -> some View {
        let greeting = greetingInfo
        let currentOrNext = snapshot.currentOrNextClass()
        let isCurrent = currentOrNext.map { isClassCurrent($0, now: Date()) } ?? false
        let progress = currentOrNext.map { blockProgress($0, now: Date()) } ?? 0

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(greeting.greet), \(user.firstName)", systemImage: greeting.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(greeting.mood)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(formattedHeroDate)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer(minLength: 0)

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(isCurrent ? "Bloque actual" : "Proximo bloque", systemImage: isCurrent ? "flame.fill" : "clock.fill")
                    .font(.caption.weight(.black))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.9))

                if let item = currentOrNext {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(item.timeRange)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.84))
                    }

                    if isCurrent {
                        ProgressView(value: progress)
                            .tint(.white)
                            .background(.white.opacity(0.22), in: Capsule())
                        Text(item.tipo.isFreeBlock ? "Bloque no lectivo" : "\(Int(progress * 100))% completado")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                } else {
                    Text(snapshot.academicTodayClasses.isEmpty ? "Hoy no tienes clases programadas." : "Jornada finalizada - todas las clases registradas.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
            .padding(14)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            LazyVGrid(columns: dashboardGrid, spacing: 10) {
                HeroKPI(label: "Clases hoy", value: "\(snapshot.completedAcademicCount)/\(snapshot.totalAcademicCount)", subtitle: "\(Int(snapshot.progress * 100))% completadas")
                HeroKPI(label: "Pendientes", value: "\(snapshot.pendingClasses.count)", subtitle: snapshot.pendingClasses.isEmpty ? "todo en orden" : "abrir lista")
                HeroKPI(label: "Hora actual", value: currentTimeText, subtitle: DateHelpers.weekdayName(for: Date()) ?? "Fin de semana")
                HeroKPI(label: "Asignatura", value: activeSubject(from: snapshot), subtitle: "activa")
            }
        }
        .padding(18)
        .background(
            ZStack {
                LinearGradient(colors: greeting.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.black.opacity(0.12))
                    .frame(width: 190, height: 190)
                    .offset(x: -130, y: 130)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func quickActions(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Acciones rapidas", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(courseSummaries(snapshot).count) cursos - \(totalStudents(snapshot)) estudiantes")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: dashboardGrid, spacing: 10) {
                GradientAction(title: "Calificar", icon: "checkmark.clipboard.fill", colors: [.green, .teal], route: .calificaciones)
                GradientAction(title: "Ver cronograma", icon: "calendar.badge.clock", colors: [.cyan, .blue], route: .cronograma)
                GradientAction(title: "Editar clase", icon: "lightbulb.fill", colors: [.purple, .pink], route: .actividades)
                GradientAction(title: "Perfil 360", icon: "person.crop.circle.fill", colors: [.indigo, .purple], route: .perfil360)
            }
        }
        .webCard()
    }

    private func courseStats(_ snapshot: DashboardSnapshot) -> some View {
        let courses = courseSummaries(snapshot)

        return VStack(alignment: .leading, spacing: 12) {
            Label("Tus cursos", systemImage: "graduationcap.fill")
                .font(.subheadline.weight(.black))

            if courses.isEmpty {
                Text("Aun no hay cursos con clases regulares en tu horario.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                LazyVGrid(columns: dashboardGrid, spacing: 10) {
                    ForEach(courses) { course in
                        CourseMiniCard(course: course)
                    }
                }
            }
        }
    }

    private func todayTimeline(_ snapshot: DashboardSnapshot) -> some View {
        let classes = classes(for: selectedDay, in: snapshot)

        return VStack(alignment: .leading, spacing: 14) {
            daySelector

            if classes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Sin clases programadas el \(selectedDay.lowercased()).")
                        .font(.subheadline.weight(.bold))
                    Text("Configura tu horario en la web para que aparezca aqui.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(classes) { item in
                        TimelineClassRow(
                            item: item,
                            isToday: selectedDay == DateHelpers.weekdayName(for: Date()),
                            isCompleted: snapshot.classState[item.id] == true,
                            studentCount: snapshot.studentCounts[item.resumen] ?? 0
                        ) {
                            Task { await viewModel.toggleCompletion(for: item) }
                        }
                    }
                }
            }
        }
    }

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DateHelpers.workdays, id: \.self) { day in
                    Button {
                        selectedDay = day
                    } label: {
                        Text(String(day.prefix(3)))
                            .font(.caption.weight(.black))
                            .frame(minWidth: 48)
                            .padding(.vertical, 8)
                            .background(selectedDay == day ? Color.pink.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(selectedDay == day ? Color.pink : Color.primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selectedDay == day ? Color.pink : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pendingPanel(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pendientes", systemImage: "bell.fill")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(snapshot.pendingClasses.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(snapshot.pendingClasses.isEmpty ? Color.green : Color.orange, in: Capsule())
            }

            if snapshot.pendingClasses.isEmpty {
                Label("Todo en orden. No tienes pendientes para hoy.", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.pendingClasses) { item in
                        NavigationLink(value: AppRoute.claseDetalle(item.id)) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.resumen) sin marcar como dictada")
                                        .font(.footnote.weight(.black))
                                    Text("\(item.dia) \(item.timeRange)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .webCard()
    }

    private func remindersAndInsights(_ snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 18) {
            remindersPanel
            InsightsPanel(snapshot: snapshot, courses: courseSummaries(snapshot))
        }
    }

    private var remindersPanel: some View {
        let reminders = decodedReminders

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recordatorios", systemImage: "note.text")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(reminders.count)/10")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(ReminderColor.allCases) { color in
                    Button {
                        reminderColor = color
                    } label: {
                        Circle()
                            .fill(color.background)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(reminderColor == color ? Color.pink : Color.clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Agregar recordatorio...", text: $newReminder)
                    .textFieldStyle(.plain)
                    .font(.footnote)
                    .padding(11)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    addReminder()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.white)
                        .background(.pink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(newReminder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reminders.count >= 10)
            }

            if reminders.isEmpty {
                Text("Sin recordatorios. Agregalos para tenerlos a mano durante el dia.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(reminders) { reminder in
                        ReminderRow(reminder: reminder) {
                            removeReminder(reminder.id)
                        }
                    }
                }
            }
        }
        .webCard()
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var noScheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title)
                .foregroundStyle(.pink)
            Text("Configura tu horario")
                .font(.title3.bold())
            Text("Cuando agregues tus bloques en la web, EduPanel los mostrara aqui para seguir tu jornada.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                onOpenProfile()
            } label: {
                Label("Ir a Mi Perfil", systemImage: "person.crop.circle.fill")
                    .font(.footnote.weight(.black))
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .webCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Sin datos para mostrar")
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

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando tu jornada...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var greetingInfo: GreetingInfo {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 {
            return GreetingInfo(greet: "Buenos dias", mood: "Empieza la jornada con energia", icon: "sunrise.fill", colors: [.orange, .pink])
        }
        if hour >= 12 && hour < 14 {
            return GreetingInfo(greet: "Buenas tardes", mood: "Manten el ritmo del aula", icon: "sun.max.fill", colors: [.orange, .yellow])
        }
        if hour >= 14 && hour < 19 {
            return GreetingInfo(greet: "Buenas tardes", mood: "Ultima recta del dia", icon: "cup.and.saucer.fill", colors: [.purple, .pink])
        }
        return GreetingInfo(greet: "Buenas noches", mood: "Tiempo de planificar manana", icon: "moon.fill", colors: [.purple, .indigo, .blue])
    }

    private var formattedHeroDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "EEEE d 'de' MMMM - HH:mm"
        return formatter.string(from: Date()).lowercased()
    }

    private var currentTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private var dashboardGrid: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private var decodedReminders: [ReminderNote] {
        guard let data = remindersData.data(using: .utf8),
              let items = try? JSONDecoder().decode([ReminderNote].self, from: data) else {
            return []
        }
        return items
    }

    private func storeReminders(_ items: [ReminderNote]) {
        guard let data = try? JSONEncoder().encode(items),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        remindersData = raw
    }

    private func addReminder() {
        let clean = newReminder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var items = decodedReminders
        items.insert(ReminderNote(text: clean, color: reminderColor), at: 0)
        storeReminders(Array(items.prefix(10)))
        newReminder = ""
    }

    private func removeReminder(_ id: String) {
        storeReminders(decodedReminders.filter { $0.id != id })
    }

    private func activeSubject(from snapshot: DashboardSnapshot) -> String {
        if let asignatura = snapshot.academicTodayClasses.compactMap(\.asignatura).first, !asignatura.isEmpty {
            return String(asignatura.prefix(8))
        }
        if !snapshot.profile.especialidad.isEmpty {
            return String(snapshot.profile.especialidad.prefix(8))
        }
        return String(snapshot.profile.tipoProfesor.prefix(8))
    }

    private func totalStudents(_ snapshot: DashboardSnapshot) -> Int {
        snapshot.studentCounts.values.reduce(0, +)
    }

    private func classes(for day: String, in snapshot: DashboardSnapshot) -> [ClaseHorario] {
        snapshot.horario
            .filter { $0.dia == day }
            .sorted { $0.horaInicio < $1.horaInicio }
    }

    private func courseSummaries(_ snapshot: DashboardSnapshot) -> [CourseSummary] {
        let academic = snapshot.horario.filter(\.isAcademic)
        let names = Array(Set(academic.map(\.resumen))).sorted()
        return names.map { name in
            let blocks = academic.filter { $0.resumen == name }
            let color = blocks.first?.colorHex ?? "#F43F5E"
            let todayBlocks = snapshot.academicTodayClasses.filter { $0.resumen == name }.count
            return CourseSummary(course: name, colorHex: color, students: snapshot.studentCounts[name] ?? 0, todayBlocks: todayBlocks)
        }
    }

    private func isClassCurrent(_ item: ClaseHorario, now: Date) -> Bool {
        guard item.dia == DateHelpers.weekdayName(for: now) else { return false }
        let current = DateHelpers.minutesSinceMidnight(for: now)
        return current >= DateHelpers.minutes(from: item.horaInicio) && current < DateHelpers.minutes(from: item.horaFin)
    }

    private func blockProgress(_ item: ClaseHorario, now: Date) -> Double {
        let start = DateHelpers.minutes(from: item.horaInicio)
        let end = DateHelpers.minutes(from: item.horaFin)
        guard end > start else { return 0 }
        let current = DateHelpers.minutesSinceMidnight(for: now)
        let raw = Double(current - start) / Double(end - start)
        return min(1, max(0, raw))
    }
}

private struct GreetingInfo {
    let greet: String
    let mood: String
    let icon: String
    let colors: [Color]
}

private struct CourseSummary: Identifiable {
    var id: String { course }
    let course: String
    let colorHex: String
    let students: Int
    let todayBlocks: Int
}

private struct HeroKPI: View {
    let label: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.78))
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GradientAction: View {
    let title: String
    let icon: String
    let colors: [Color]
    let route: AppRoute

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.black))
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.black))
                    .opacity(0.8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CourseMiniCard: View {
    let course: CourseSummary

    var body: some View {
        HStack(spacing: 12) {
            Text(String(course.course.prefix(3)).uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color(hex: course.colorHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(course.course)
                    .font(.footnote.weight(.black))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label("\(course.students)", systemImage: "person.2.fill")
                    if course.todayBlocks > 0 {
                        Text("hoy \(course.todayBlocks)b")
                            .foregroundStyle(.pink)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.32), lineWidth: 1)
        )
    }
}

private struct TimelineClassRow: View {
    let item: ClaseHorario
    let isToday: Bool
    let isCompleted: Bool
    let studentCount: Int
    let onToggle: () -> Void

    private var isCurrent: Bool {
        guard isToday else { return false }
        let current = DateHelpers.minutesSinceMidnight(for: Date())
        return current >= DateHelpers.minutes(from: item.horaInicio) && current < DateHelpers.minutes(from: item.horaFin)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(circleFill)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color(hex: item.colorHex), lineWidth: isCompleted || isCurrent ? 0 : 2))
                    .padding(.top, 18)
                Rectangle()
                    .fill(Color(.separator).opacity(0.45))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(String(item.horaInicio.prefix(2)))
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(hex: item.colorHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                                .font(.subheadline.weight(.black))
                                .lineLimit(1)

                            if item.tipo.isFreeBlock {
                                BadgeLabel(text: "No lectivo", color: .secondary)
                            } else if isCompleted {
                                BadgeLabel(text: "Dictada", color: .green)
                            } else if isCurrent {
                                BadgeLabel(text: "EN CURSO", color: .pink)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                            Text(item.timeRange)
                            if item.tipo != .clase {
                                Text("- \(item.tipo.label)")
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)

                HStack {
                    if item.isAcademic {
                        Label("\(studentCount)", systemImage: "person.2.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(action: onToggle) {
                            Text(isCompleted ? "Hecha" : "Marcar")
                                .font(.caption.weight(.black))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(isCompleted ? Color.green : Color.primary)
                                .background(isCompleted ? Color.green.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Sin registro")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isCurrent ? Color.pink : Color(.separator).opacity(0.28), lineWidth: isCurrent ? 1.4 : 1)
            )
            .padding(.bottom, 12)
        }
    }

    private var circleFill: Color {
        if isCompleted { return .green }
        if isCurrent { return .pink }
        return Color(.systemGroupedBackground)
    }
}

private struct BadgeLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct ReminderRow: View {
    let reminder: ReminderNote
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(reminder.text)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.black))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .foregroundStyle(reminder.color.foreground)
        .background(reminder.color.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(reminder.color.foreground.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct InsightsPanel: View {
    let snapshot: DashboardSnapshot
    let courses: [CourseSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Tu dia en numeros", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.black))

            VStack(spacing: 12) {
                InsightRow(icon: "person.2.fill", label: "Alumnos totales", value: "\(courses.reduce(0) { $0 + $1.students })", color: .pink)
                InsightRow(icon: "clock.fill", label: "Horas/semana", value: String(format: "%.1f h", weeklyHours), color: .green)
                InsightRow(icon: "book.closed.fill", label: "Libro de clases", value: "Prototipo", color: .blue)
                InsightRow(icon: "flame.fill", label: "Restantes hoy", value: "\(snapshot.pendingClasses.count)", color: .orange)
            }

            Text(insightMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.pink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .webCard()
    }

    private var weeklyHours: Double {
        snapshot.horario.filter(\.isAcademic).reduce(0) { total, item in
            let minutes = max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            return total + Double(minutes) / 60
        }
    }

    private var insightMessage: String {
        if snapshot.academicTodayClasses.isEmpty {
            return "Dia tranquilo. Aprovecha para planificar la proxima semana."
        }
        if snapshot.pendingClasses.isEmpty {
            return "Tremendo. Completaste tus clases del dia."
        }
        let count = snapshot.pendingClasses.count
        return "Te queda\(count == 1 ? "" : "n") \(count) clase\(count == 1 ? "" : "s"). Tu puedes."
    }
}

private struct InsightRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14), in: Circle())

            Text(label)
                .font(.footnote.weight(.semibold))
            Spacer()
            Text(value)
                .font(.footnote.weight(.black))
        }
    }
}

private enum ReminderColor: String, Codable, CaseIterable, Identifiable {
    case rosa
    case amarillo
    case verde
    case azul

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .rosa: return .pink.opacity(0.16)
        case .amarillo: return .yellow.opacity(0.2)
        case .verde: return .green.opacity(0.16)
        case .azul: return .blue.opacity(0.16)
        }
    }

    var foreground: Color {
        switch self {
        case .rosa: return .pink
        case .amarillo: return .orange
        case .verde: return .green
        case .azul: return .blue
        }
    }
}

private struct ReminderNote: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let color: ReminderColor

    init(id: String = UUID().uuidString, text: String, color: ReminderColor) {
        self.id = id
        self.text = text
        self.color = color
    }
}

private extension View {
    func webCard() -> some View {
        self.padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
            )
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
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
