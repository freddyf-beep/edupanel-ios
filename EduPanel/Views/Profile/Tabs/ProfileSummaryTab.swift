import SwiftUI

struct ProfileSummaryTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot
    @Binding var selectedTab: ProfileTabKey

    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Mis cursos", icon: "folder.fill", hint: snapshot.courses.isEmpty ? "Aún no agregas ninguno" : "\(snapshot.courses.count) cursos") {
                let courses = viewModel.courseSummaries(for: snapshot)
                if courses.isEmpty {
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
                        ForEach(courses) { course in
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
                .tint(EPTheme.primary)
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
}

struct ProfileCourseRow: View {
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
                    .foregroundStyle(course.levelText == "Sin nivel" ? .orange : EPTheme.primary)

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
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ProfileChecklistRow: View {
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
        .background(item.isComplete ? Color.green.opacity(0.1) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MiniWeekView: View {
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
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
