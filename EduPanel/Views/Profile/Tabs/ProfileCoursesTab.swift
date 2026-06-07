import SwiftUI

struct ProfileCoursesTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot
    @Binding var selectedTab: ProfileTabKey

    var body: some View {
        let courses = viewModel.courseSummaries(for: snapshot)

        return VStack(spacing: 18) {
            if courses.isEmpty {
                ProfileEmptyAction(
                    icon: "folder.badge.plus",
                    title: "Sin cursos",
                    message: "Agrega bloques lectivos en Mi Semana para crear cursos.",
                    buttonTitle: "Ir a Mi Semana"
                ) {
                    selectedTab = .semana
                }
            } else {
                ForEach(courses) { course in
                    ProfileSection(title: course.name, icon: "folder.fill", hint: course.levelText) {
                        ProfileCourseReplicaCard(course: course)
                    }
                }
            }
        }
    }
}

struct ProfileCourseReplicaCard: View {
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
                Text("Aún no hay estudiantes. Agrégalos manualmente o impórtalos presionando el botón 'Estudiantes' abajo.")
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

struct ProfileSubjectScheduleRow: View {
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

struct ProfileStudentRow: View {
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
