import SwiftUI

struct ProfileWeekTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot
    @Binding var selectedTab: ProfileTabKey

    var body: some View {
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

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
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

    private func routeTitle(for item: ClaseHorario) -> String {
        let title = item.resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.tipo.label : title
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
}

struct ProfileNonTeachingGroup: Identifiable {
    let id: String
    let title: String
    let typeLabel: String
    let colorHex: String
    let days: [String]
    let timeLabel: String
    let totalMinutes: Int
}

struct ProfileNonTeachingGroupRow: View {
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

struct ProfileWeekCalendar: View {
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

struct ProfileScheduleRow: View {
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
