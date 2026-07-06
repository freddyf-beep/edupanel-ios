import Foundation
import SwiftUI

private enum DashboardTabKey: String, CaseIterable, Identifiable {
    case hoy
    case pendientes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoy: return "Hoy"
        case .pendientes: return "Pendientes"
        }
    }

    var systemImage: String {
        switch self {
        case .hoy: return "sun.max.fill"
        case .pendientes: return "bell.fill"
        }
    }
}

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var selectedTab: DashboardTabKey = .hoy
    @State private var newReminder = ""
    @State private var reminderColor: ReminderColor = .amarillo
    @AppStorage("edupanel_dashboard_reminders") private var remindersData = "[]"

    @Environment(\.displayMode) private var displayMode

    let user: AuthenticatedUser
    let onOpenProfile: () -> Void
    let onOpenPlanificaciones: () -> Void

    init(
        repository: DashboardRepository,
        user: AuthenticatedUser,
        onOpenProfile: @escaping () -> Void = {},
        onOpenPlanificaciones: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: DashboardViewModel(repository: repository))
        self.user = user
        self.onOpenProfile = onOpenProfile
        self.onOpenPlanificaciones = onOpenPlanificaciones
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
        .background(EPTheme.background)
        .navigationTitle("Inicio")
        .toolbar {
            if displayMode.isSimple {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.calificaciones) {
                        toolbarIcon("checkmark.clipboard")
                    }
                    NavigationLink(value: AppRoute.cronograma) {
                        toolbarIcon("calendar.badge.clock")
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(EPTheme.primary)
            .frame(width: 32, height: 32)
            .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dashboardContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }

            heroCard(snapshot)

            if snapshot.horario.isEmpty {
                noScheduleCard
            } else if displayMode.isSimple {
                todayTimeline(snapshot)
            } else {
                dashboardTabs(snapshot)

                switch selectedTab {
                case .hoy:
                    todayTimeline(snapshot)
                    quickActions
                    if !decodedReminders.isEmpty {
                        remindersReadCard
                    }
                case .pendientes:
                    pendingPanel(snapshot)
                    remindersEditorCard
                }
            }
        }
    }

    // MARK: - Hero

    private func heroCard(_ snapshot: DashboardSnapshot) -> some View {
        let greeting = greetingInfo
        let currentOrNext = snapshot.currentOrNextClass()
        let isCurrent = currentOrNext.map { isClassCurrent($0, now: Date()) } ?? false
        let progress = currentOrNext.map { blockProgress($0, now: Date()) } ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Label("\(greeting.greet), \(user.firstName)", systemImage: greeting.icon)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Text(formattedHeroDate)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 8) {
                if let item = currentOrNext {
                    HStack(spacing: 10) {
                        Image(systemName: isCurrent ? "flame.fill" : "clock.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.2), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isCurrent ? "BLOQUE ACTUAL" : "PRÓXIMO BLOQUE")
                                .font(.system(size: 8.5, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.75))
                            Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Text(item.timeRange)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: Capsule())
                    }

                    if isCurrent {
                        ProgressView(value: progress)
                            .tint(.white)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                } else {
                    Label(
                        snapshot.academicTodayClasses.isEmpty ? "Hoy no tienes clases programadas." : "Jornada finalizada — todas las clases registradas.",
                        systemImage: snapshot.academicTodayClasses.isEmpty ? "moon.zzz.fill" : "checkmark.seal.fill"
                    )
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                }
            }
            .padding(12)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            if !displayMode.isSimple {
                HStack(spacing: 10) {
                    HeroKPI(
                        label: "Clases hoy",
                        value: "\(snapshot.completedAcademicCount)/\(snapshot.totalAcademicCount)",
                        subtitle: "\(Int(snapshot.progress * 100))% completadas"
                    )
                    HeroKPI(
                        label: "Pendientes",
                        value: "\(snapshot.pendingClasses.count)",
                        subtitle: snapshot.pendingClasses.isEmpty ? "todo en orden" : "por registrar"
                    )
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: greeting.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: EPTheme.heroRadius, style: .continuous)
        )
        .shadow(color: (greeting.colors.first ?? .black).opacity(0.25), radius: 14, y: 7)
        .scrollTransition(axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .opacity(phase.isIdentity ? 1 : 0.75)
        }
    }

    // MARK: - Tabs internos

    private func dashboardTabs(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 6) {
            ForEach(DashboardTabKey.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(EPTheme.spring) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11, weight: .black))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .black))
                        if tab == .pendientes && !snapshot.pendingClasses.isEmpty {
                            Text("\(snapshot.pendingClasses.count)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? .white.opacity(0.3) : .red, in: Capsule())
                        }
                    }
                    .foregroundStyle(isSelected ? EPTheme.primary : EPTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        isSelected ? AnyShapeStyle(EPTheme.primaryLight) : AnyShapeStyle(EPTheme.card),
                        in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous)
                            .stroke(isSelected ? EPTheme.primary.opacity(0.16) : EPTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - Timeline de hoy

    private func todayTimeline(_ snapshot: DashboardSnapshot) -> some View {
        let today = DateHelpers.weekdayName(for: Date())
        let classes = today.map { dia in
            snapshot.horario.filter { $0.dia == dia }.sorted { $0.horaInicio < $1.horaInicio }
        } ?? []

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tu día", systemImage: "sun.max.fill")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text(today ?? "Fin de semana")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if classes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(today == nil ? "Es fin de semana. Descansa." : "Sin bloques programados para hoy.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(classes) { item in
                        TimelineClassRow(
                            item: item,
                            isToday: true,
                            isCompleted: snapshot.classState[item.id] == true,
                            studentCount: snapshot.studentCounts[item.resumen] ?? 0,
                            route: AppRoute.classDetail(id: item.id, title: routeTitle(for: item))
                        ) {
                            Task { await viewModel.toggleCompletion(for: item) }
                        }
                    }
                }
            }
        }
        .webCard()
    }

    // MARK: - Acciones rápidas

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Acciones rápidas", systemImage: "bolt.fill")
                .font(.subheadline.weight(.black))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                QuickAction(title: "Calificar", icon: "checkmark.clipboard.fill", colors: [.green, .teal], kind: .route(.calificaciones))
                QuickAction(title: "Cronograma", icon: "calendar.badge.clock", colors: [.cyan, .blue], kind: .route(.cronograma))
                QuickAction(title: "Planificar", icon: "lightbulb.fill", colors: [.purple, EPTheme.primary], kind: .action(onOpenPlanificaciones))
                QuickAction(title: "Mi Perfil", icon: "person.crop.circle.fill", colors: [.indigo, .purple], kind: .action(onOpenProfile))
            }
        }
        .webCard()
    }

    // MARK: - Pendientes

    private func pendingPanel(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pendientes de hoy", systemImage: "bell.fill")
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
                        NavigationLink(value: AppRoute.classDetail(id: item.id, title: routeTitle(for: item))) {
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

    // MARK: - Recordatorios

    private var remindersReadCard: some View {
        let reminders = decodedReminders

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recordatorios", systemImage: "note.text")
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(reminders.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(reminders) { reminder in
                    ReminderRow(reminder: reminder) {
                        removeReminder(reminder.id)
                    }
                }
            }
        }
        .webCard()
    }

    private var remindersEditorCard: some View {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            reminderColor = color
                        }
                    } label: {
                        Circle()
                            .fill(color.background)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(reminderColor == color ? EPTheme.primary : Color.clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Agregar recordatorio...", text: $newReminder)
                    .textFieldStyle(.plain)
                    .font(.footnote)
                    .padding(11)
                    .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))

                Button {
                    addReminder()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.white)
                        .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(newReminder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reminders.count >= 10)
            }

            if reminders.isEmpty {
                Text("Sin recordatorios. Agrégalos para tenerlos a mano durante el día.")
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

    // MARK: - Estados

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
                .foregroundStyle(EPTheme.primary)
            Text("Configura tu horario")
                .font(.title3.bold())
            Text("Cuando agregues tus bloques en Mi Perfil, EduPanel los mostrará aquí para seguir tu jornada.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                onOpenProfile()
            } label: {
                Label("Ir a Mi Perfil", systemImage: "person.crop.circle.fill")
                    .font(.footnote.weight(.black))
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        }
        .webCard()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sin datos para mostrar", systemImage: "tray")
        } description: {
            Text("Revisa tu conexión e inténtalo de nuevo.")
        } actions: {
            Button("Reintentar") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        }
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

    // MARK: - Helpers

    private var greetingInfo: GreetingInfo {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 {
            return GreetingInfo(greet: "Buenos días", icon: "sunrise.fill", colors: [.orange, .pink])
        }
        if hour >= 12 && hour < 19 {
            return GreetingInfo(greet: "Buenas tardes", icon: "sun.max.fill", colors: [.purple, .pink])
        }
        return GreetingInfo(greet: "Buenas noches", icon: "moon.fill", colors: [.purple, .indigo, .blue])
    }

    private var formattedHeroDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return formatter.string(from: Date()).capitalized
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

    private func routeTitle(for item: ClaseHorario) -> String {
        let title = item.resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.tipo.label : title
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

// MARK: - Subvistas

private struct GreetingInfo {
    let greet: String
    let icon: String
    let colors: [Color]
}

private struct HeroKPI: View {
    let label: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.78))
            Text(value)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct QuickAction: View {
    enum Kind {
        case route(AppRoute)
        case action(() -> Void)
    }

    let title: String
    let icon: String
    let colors: [Color]
    let kind: Kind

    var body: some View {
        switch kind {
        case .route(let route):
            NavigationLink(value: route) {
                label
            }
            .buttonStyle(.plain)
        case .action(let action):
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack {
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .black))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: colors.first?.opacity(0.25) ?? .clear, radius: 7, y: 4)
    }
}

private struct TimelineClassRow: View {
    let item: ClaseHorario
    let isToday: Bool
    let isCompleted: Bool
    let studentCount: Int
    let route: AppRoute
    let onToggle: () -> Void

    private var isCurrent: Bool {
        guard isToday else { return false }
        let current = DateHelpers.minutesSinceMidnight(for: Date())
        return current >= DateHelpers.minutes(from: item.horaInicio) && current < DateHelpers.minutes(from: item.horaFin)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(item.horaInicio.prefix(5)))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 48, height: 44)
                .background(Color(hex: item.colorHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                        .font(.footnote.weight(.black))
                        .lineLimit(1)

                    if item.tipo.isFreeBlock {
                        BadgeLabel(text: "No lectivo", color: .secondary)
                    } else if isCompleted {
                        BadgeLabel(text: "Dictada", color: .green)
                    } else if isCurrent {
                        BadgeLabel(text: "EN CURSO", color: EPTheme.primary)
                    }
                }

                HStack(spacing: 6) {
                    Text(item.timeRange)
                    if item.isAcademic {
                        Label("\(studentCount)", systemImage: "person.2.fill")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if item.isAcademic {
                Button(action: onToggle) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isCompleted ? .green : Color(.systemGray3))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                NavigationLink(value: route) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(EPTheme.subtle, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.5)
        }
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
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
                    .stroke(EPTheme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 5, y: 1)
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
