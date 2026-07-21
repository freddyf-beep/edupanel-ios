import SwiftUI

struct ProfileCoursesTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot
    @Binding var selectedTab: ProfileTabKey
    @State private var creatingCourse = false
    @State private var coursePendingDeletion: AcademicCourse?

    var body: some View {
        let courses = viewModel.courseSummaries(for: snapshot)

        return VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cursos y talleres").font(.headline.weight(.black))
                    Text("Define aquí su identidad, nivel y asignaturas.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { creatingCourse = true } label: {
                    Label("Nuevo", systemImage: "plus").font(.footnote.weight(.black))
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
            }

            if snapshot.courseCatalog.isEmpty, !snapshot.courses.isEmpty {
                Button {
                    Task { await viewModel.importLegacyCourses() }
                } label: {
                    Label("Importar configuración anterior", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text("La importación crea el catálogo v2 sin borrar ni reescribir los documentos anteriores.")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
                HStack {
                    Text("Cada curso muestra sus bloques, nivel curricular y estudiantes.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProfileSaveBadge(status: viewModel.saveHorarioStatus)
                        .fixedSize()
                    ProfileSaveBadge(status: viewModel.saveMappingStatus)
                        .fixedSize()
                }

                ForEach(courses) { course in
                    CursoConfigCard(viewModel: viewModel, course: course)
                }
            }

            if !snapshot.archivedCourses.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Archivados").font(.headline.weight(.black))
                    ForEach(snapshot.archivedCourses) { course in
                        HStack(spacing: 10) {
                            Circle().fill(Color(profileHex: course.colorHex)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).font(.footnote.weight(.bold))
                                Text(course.deleteEligibleAt.map { "Eliminación disponible desde \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Protegido por 30 días")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restaurar") { Task { await viewModel.restoreCourse(course.courseID) } }
                                .font(.caption.weight(.bold))
                            if course.isDeleteEligible {
                                Button(role: .destructive) {
                                    coursePendingDeletion = course
                                } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Eliminar permanentemente \(course.name)")
                            }
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .sheet(isPresented: $creatingCourse) { AcademicCourseEditorSheet(viewModel: viewModel) }
        .sheet(item: $coursePendingDeletion) { course in
            PermanentCourseDeletionSheet(viewModel: viewModel, course: course)
        }
    }
}

private struct PermanentCourseDeletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProfileViewModel
    let course: AcademicCourse

    @State private var exactName = ""
    @State private var impactSummary: String?
    @State private var isLoading = true
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Impacto") {
                    if isLoading {
                        ProgressView("Calculando impacto…")
                    } else if let impactSummary {
                        Label(impactSummary, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("No fue posible verificar el impacto. Revisa la conexión e inténtalo de nuevo.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Confirmación obligatoria") {
                    Text("Esta eliminación no se puede deshacer. Escribe exactamente:")
                    Text(course.name).font(.headline)
                    TextField("Nombre exacto del curso", text: $exactName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(role: .destructive) {
                        isDeleting = true
                        Task {
                            if await viewModel.permanentlyDeleteCourse(course, exactName: exactName) {
                                dismiss()
                            }
                            isDeleting = false
                        }
                    } label: {
                        if isDeleting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Eliminar permanentemente").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || impactSummary == nil || exactName != course.name || isDeleting)
                }
            }
            .navigationTitle("Eliminar curso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .task {
                impactSummary = await viewModel.deletionImpactSummary(for: course)
                isLoading = false
            }
        }
    }
}

private struct WizardPreset: Identifiable {
    let curso: String
    let asignatura: String?

    var id: String { "\(curso)::\(asignatura ?? "")" }
}

private struct CursoConfigCard: View {
    let viewModel: ProfileViewModel
    let course: ProfileCourseSummary

    @Environment(\.displayMode) private var displayMode

    @State private var renombrando = false
    @State private var nuevoNombre = ""
    @State private var mostrandoEstudiantes = false
    @State private var nuevoEstudiante = ""
    @State private var pieExpandido: String?
    @State private var confirmandoEliminar = false
    @State private var agregandoAsignatura = false
    @State private var nuevaAsignatura = ""
    @State private var wizardPreset: WizardPreset?
    @State private var editingBloque: ClaseHorario?
    @State private var curriculumOptions: [CurriculumSubjectOption] = []

    private var academicCourse: AcademicCourse? {
        viewModel.snapshot?.courseCatalog.first { $0.courseID == course.courseID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(profileHex: course.colorHex))
                .frame(height: 6)

            VStack(alignment: .leading, spacing: 14) {
                header
                tipoNivelBlock
                asignaturasBlock
            }
            .padding(16)

            if mostrandoEstudiantes {
                estudiantesBlock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            footer
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.1), lineWidth: 1)
        )
        .task(id: academicCourse?.level) {
            guard let level = academicCourse?.level else {
                curriculumOptions = []
                return
            }
            curriculumOptions = await viewModel.curriculumSubjects(for: level)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .sheet(item: $wizardPreset) { preset in
            BloqueWizardSheet(
                viewModel: viewModel,
                presetCurso: preset.curso,
                presetAsignatura: preset.asignatura
            )
        }
        .sheet(item: $editingBloque) { bloque in
            BloqueEditorSheet(viewModel: viewModel, bloque: bloque)
        }
        .confirmationDialog(
            course.academicKind == nil ? "¿Eliminar el curso \(course.name) completo?" : "¿Archivar \(course.name)?",
            isPresented: $confirmandoEliminar,
            titleVisibility: .visible
        ) {
            Button(course.academicKind == nil ? "Sí, eliminar curso" : "Archivar curso", role: .destructive) {
                if course.academicKind == nil {
                    viewModel.removeCurso(course.name)
                } else {
                    Task { await viewModel.archiveCourse(course.courseID) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(course.academicKind == nil
                ? "Se quitarán sus \(course.blocks) bloques del horario. La lista de estudiantes no se borra de Firestore."
                : "Se guardará una copia de sus bloques y quedará protegido contra eliminación durante 30 días.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            colorSelector

            VStack(alignment: .leading, spacing: 7) {
                if renombrando {
                    HStack(spacing: 8) {
                        TextField("Nombre del curso", text: $nuevoNombre)
                            .textFieldStyle(.plain)
                            .font(.headline.weight(.black))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onSubmit { confirmarRenombre() }

                        Button {
                            confirmarRenombre()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(EPTheme.primary, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            renombrando = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color(.systemGray5), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 7) {
                        Text(course.name)
                            .font(.title3.weight(.black))
                            .lineLimit(2)
                        if course.academicKind != .oficial {
                            Button {
                                nuevoNombre = course.name
                                renombrando = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, height: 26)
                                    .background(Color(.systemGray5), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ReplicaFlowLayout(spacing: 7) {
                    metricChip("\(asignaturasAgrupadas.count) asignatura\(asignaturasAgrupadas.count == 1 ? "" : "s")", icon: "book.closed.fill", tint: .blue)
                    metricChip("\(course.blocks) bloques · \(ProfileFormat.minutes(course.minutes))", icon: "clock.fill", tint: .purple)
                    metricChip("\(course.students) alumnos", icon: "person.2.fill", tint: .green)
                    if course.pie > 0 {
                        metricChip("\(course.pie) PIE", icon: "number", tint: .orange)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var colorSelector: some View {
        Menu {
            ForEach(BloqueHelpers.paleta, id: \.self) { hex in
                Button {
                    viewModel.recolorCurso(course.name, colorHex: hex)
                } label: {
                    Label(hex.uppercased() == course.colorHex.uppercased() ? "Actual" : hex, systemImage: hex.uppercased() == course.colorHex.uppercased() ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(profileHex: course.colorHex))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color(profileHex: course.colorHex).opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func confirmarRenombre() {
        let clean = nuevoNombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != course.name {
            viewModel.renameCurso(course.name, to: clean)
        }
        renombrando = false
    }

    // MARK: - Tipo y nivel

    private var tipoNivelBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let academicCourse {
                HStack {
                    Label(academicCourse.kind.label, systemImage: academicCourse.kind == .oficial ? "graduationcap.fill" : "paintbrush.fill")
                    Spacer()
                    if let level = academicCourse.level { Text(AcademicContract.displayLevel(level)) }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tipo de curso")
                    .profileFieldLabel()
                Picker("Tipo de curso", selection: tipoBinding) {
                    Text("Oficial Mineduc").tag(TipoCurricular.oficial)
                    Text("Taller").tag(TipoCurricular.taller)
                    Text("Libre").tag(TipoCurricular.libre)
                }
                .pickerStyle(.segmented)
            }

            if course.type == .oficial {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nivel curricular")
                        .profileFieldLabel()
                    Picker("Nivel curricular", selection: nivelBinding) {
                        Text("— Sin configurar —").tag("")
                        ForEach(CurriculumLevels.all, id: \.self) { nivel in
                            Text(nivel).tag(nivel)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke((course.level ?? "").isEmpty ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )

                    if (course.level ?? "").isEmpty {
                        Label("Falta seleccionar nivel curricular.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Label(course.type == .taller ? "Este curso no requiere nivel curricular Mineduc." : "Curso libre — sin currículum asociado.", systemImage: "info.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tipoBinding: Binding<TipoCurricular> {
        Binding(
            get: { viewModel.draftCursoTipos[course.name] ?? .oficial },
            set: { nuevo in
                if nuevo == .oficial {
                    viewModel.draftCursoTipos.removeValue(forKey: course.name)
                } else {
                    viewModel.draftCursoTipos[course.name] = nuevo
                    viewModel.draftNivelMapping.removeValue(forKey: course.name)
                }
                viewModel.saveMappingDebounced()
            }
        )
    }

    private var nivelBinding: Binding<String> {
        Binding(
            get: { viewModel.draftNivelMapping[course.name] ?? "" },
            set: { nuevo in
                if nuevo.isEmpty {
                    viewModel.draftNivelMapping.removeValue(forKey: course.name)
                } else {
                    viewModel.draftNivelMapping[course.name] = nuevo
                }
                viewModel.saveMappingDebounced()
            }
        )
    }

    // MARK: - Asignaturas y bloques

    private var asignaturasAgrupadas: [(asignatura: String, bloques: [ClaseHorario])] {
        let grouped = Dictionary(grouping: course.weeklyBlocks) { bloque in
            let nombre = bloque.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return nombre.isEmpty ? "Sin asignatura" : nombre
        }
        var result = grouped.map { ($0.key, $0.value) }
        for subject in course.subjects where !result.contains(where: { $0.0 == subject }) {
            result.append((subject, []))
        }
        return result.sorted { lhs, rhs in
            if lhs.0 == "Sin asignatura" { return false }
            if rhs.0 == "Sin asignatura" { return true }
            return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
        }
    }

    private var asignaturasBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Asignaturas y horario", systemImage: "book.closed.fill")
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    withAnimation(EPTheme.spring) {
                        agregandoAsignatura = true
                    }
                } label: {
                    Label("Asignatura", systemImage: "plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(EPTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(academicCourse != nil)
                .opacity(academicCourse == nil ? 1 : 0)
            }

            if let academicCourse, academicCourse.kind == .oficial, let level = academicCourse.level {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Activa las asignaturas que impartes en este curso.")
                        .font(.caption).foregroundStyle(.secondary)
                    ReplicaFlowLayout(spacing: 7) {
                        ForEach(curriculumOptions.isEmpty ? AcademicContract.subjects(for: level) : curriculumOptions) { option in
                            let enabled = academicCourse.subjects.contains { $0.id == option.id }
                            Button {
                                var updated = academicCourse
                                if enabled { updated.subjects.removeAll { $0.id == option.id } }
                                else { updated.subjects.append(CourseSubjectSelection(id: option.id, label: option.label, availability: option.availability)) }
                                Task { await viewModel.saveCourse(updated) }
                            } label: {
                                Label(
                                    option.label,
                                    systemImage: enabled ? "checkmark.circle.fill" : (option.availability == .unavailable ? "exclamationmark.circle" : "circle")
                                )
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(enabled ? EPTheme.primary : .secondary)
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background((enabled ? EPTheme.primary : Color.secondary).opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(option.availability == .unavailable ? "Seleccionable, pero aún no tiene contenido OA publicado." : "Contenido curricular publicado disponible.")
                        }
                    }
                    if curriculumOptions.contains(where: { $0.availability == .unavailable }) {
                        Label("El símbolo de advertencia indica que aún no hay contenido OA publicado; la asignatura sigue siendo seleccionable.", systemImage: "exclamationmark.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if agregandoAsignatura {
                HStack(spacing: 8) {
                    TextField("Ej. Música, Lenguaje…", text: $nuevaAsignatura)
                        .textFieldStyle(.plain)
                        .font(.footnote.weight(.semibold))
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit { continuarNuevaAsignatura() }

                    Button {
                        continuarNuevaAsignatura()
                    } label: {
                        Label("Continuar", systemImage: "arrow.right")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(nuevaAsignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancelar") {
                        withAnimation(EPTheme.spring) {
                            agregandoAsignatura = false
                            nuevaAsignatura = ""
                        }
                    }
                    .font(.caption.weight(.bold))
                    .tint(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if asignaturasAgrupadas.isEmpty {
                Text("Este curso aún no tiene asignaturas. Agrega una para comenzar.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(16)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(asignaturasAgrupadas, id: \.asignatura) { grupo in
                        asignaturaRow(grupo.asignatura, bloques: grupo.bloques)
                    }
                }
            }
        }
    }

    private func continuarNuevaAsignatura() {
        let nombre = nuevaAsignatura.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else { return }
        agregandoAsignatura = false
        nuevaAsignatura = ""
        wizardPreset = WizardPreset(curso: course.name, asignatura: nombre)
    }

    private func asignaturaRow(_ asignatura: String, bloques: [ClaseHorario]) -> some View {
        let sinAsignatura = asignatura == "Sin asignatura"
        let minutos = bloques.reduce(0) { total, bloque in
            total + max(0, DateHelpers.minutes(from: bloque.horaFin) - DateHelpers.minutes(from: bloque.horaInicio))
        }

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if sinAsignatura {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.orange)
                } else {
                    Circle()
                        .fill(Color(profileHex: bloques.first?.colorHex ?? course.colorHex))
                        .frame(width: 10, height: 10)
                }

                Text(asignatura)
                    .font(.footnote.weight(.black))
                    .foregroundStyle(sinAsignatura ? .orange : .primary)
                    .lineLimit(1)

                Text("· \(bloques.count) bloque\(bloques.count == 1 ? "" : "s") · \(ProfileFormat.minutes(minutos))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    wizardPreset = WizardPreset(curso: course.name, asignatura: sinAsignatura ? nil : asignatura)
                } label: {
                    Label("Bloque", systemImage: "plus")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(EPTheme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(EPTheme.primary.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if !displayMode.isSimple {
                bloquesRows(bloques)
            }
        }
        .padding(11)
        .background(
            sinAsignatura ? Color.orange.opacity(0.08) : Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(sinAsignatura ? Color.orange.opacity(0.3) : Color(.separator).opacity(0.1), lineWidth: 1)
        )
    }

    private func bloquesRows(_ bloques: [ClaseHorario]) -> some View {
            VStack(spacing: 6) {
                ForEach(bloques) { bloque in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(profileHex: bloque.colorHex))
                            .frame(width: 8, height: 8)
                        Text(bloque.dia)
                            .font(.caption.weight(.black))
                        Text(bloque.timeRange)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            editingBloque = bloque
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, height: 26)
                                .background(Color(.systemGray5), in: Circle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            viewModel.removeBloque(id: bloque.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.red)
                                .frame(width: 26, height: 26)
                                .background(.red.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
    }

    // MARK: - Estudiantes

    private var estudiantes: [EstudiantePerfil] {
        viewModel.students(for: course.name)
    }

    private var estudiantesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Nombre del estudiante (ej: Juan Tapia)", text: $nuevoEstudiante)
                    .textFieldStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onSubmit { agregarEstudiante() }

                Button {
                    agregarEstudiante()
                } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(EPTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(nuevoEstudiante.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await viewModel.saveStudents(curso: course.name) }
                } label: {
                    Label("Guardar", systemImage: "square.and.arrow.down.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(EPTheme.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack {
                ProfileSaveBadge(status: viewModel.saveStudentsStatus)
                Spacer()
                NavigationLink(value: AppRoute.courseStudents(course.name)) {
                    Label("Importación masiva", systemImage: "square.and.arrow.down.on.square")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.blue)
                }
            }

            if estudiantes.isEmpty {
                Text("Aún no hay estudiantes. Añade el primero arriba.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(estudiantes) { estudiante in
                        estudianteRow(estudiante)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func estudianteRow(_ estudiante: EstudiantePerfil) -> some View {
        let pieAbierto = estudiante.pie && pieExpandido == estudiante.id

        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text("\(estudiante.orden)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(.systemGray5), in: Circle())

                Text(estudiante.nombre)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    viewModel.updateStudents(curso: course.name) { lista in
                        lista.map { $0.id == estudiante.id ? $0.con(pie: !$0.pie) : $0 }
                    }
                } label: {
                    Text("PIE")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(estudiante.pie ? .orange : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(estudiante.pie ? Color.orange.opacity(0.15) : Color(.systemGray5), in: Capsule())
                }
                .buttonStyle(.plain)

                if estudiante.pie {
                    Button {
                        withAnimation(EPTheme.spring) {
                            pieExpandido = pieAbierto ? nil : estudiante.id
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(pieAbierto ? 90 : 0))
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    viewModel.updateStudents(curso: course.name) { lista in
                        reordenar(lista.filter { $0.id != estudiante.id })
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 26)
                        .background(.red.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if pieAbierto {
                pieDetalle(estudiante)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(estudiante.pie ? Color.orange.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }

    private let diagnosticosPIE = ["TEL", "DEA", "DI", "FIL", "TEA", "TDAH", "Disc. Visual", "Disc. Auditiva", "Disc. Motora", "Trast. Psiquiátrico"]

    private func pieDetalle(_ estudiante: EstudiantePerfil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Diagnóstico")
                    .profileFieldLabel()
                Picker("Diagnóstico", selection: Binding(
                    get: { estudiante.pieDiagnostico },
                    set: { nuevo in
                        viewModel.updateStudents(curso: course.name) { lista in
                            lista.map { $0.id == estudiante.id ? $0.con(pieDiagnostico: nuevo) : $0 }
                        }
                    }
                )) {
                    Text("— Seleccionar —").tag("")
                    ForEach(diagnosticosPIE, id: \.self) { diagnostico in
                        Text(diagnostico).tag(diagnostico)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Especialista")
                    .profileFieldLabel()
                TextField("Nombre del especialista", text: Binding(
                    get: { estudiante.pieEspecialista },
                    set: { nuevo in
                        viewModel.updateStudents(curso: course.name) { lista in
                            lista.map { $0.id == estudiante.id ? $0.con(pieEspecialista: nuevo) : $0 }
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .font(.caption.weight(.semibold))
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Notas de adecuación")
                    .profileFieldLabel()
                TextField("Apoyos, adecuaciones…", text: Binding(
                    get: { estudiante.pieNotas },
                    set: { nuevo in
                        viewModel.updateStudents(curso: course.name) { lista in
                            lista.map { $0.id == estudiante.id ? $0.con(pieNotas: nuevo) : $0 }
                        }
                    }
                ), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(.caption.weight(.semibold))
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.07))
    }

    private func agregarEstudiante() {
        let nombre = nuevoEstudiante.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty else { return }
        viewModel.updateStudents(curso: course.name) { lista in
            let siguienteOrden = (lista.map(\.orden).max() ?? 0) + 1
            return lista + [EstudiantePerfil(
                id: "est_\(Int(Date().timeIntervalSince1970 * 1000))",
                nombre: nombre,
                orden: siguienteOrden,
                pie: false,
                pieDiagnostico: "",
                pieEspecialista: "",
                pieNotas: ""
            )]
        }
        nuevoEstudiante = ""
    }

    private func reordenar(_ lista: [EstudiantePerfil]) -> [EstudiantePerfil] {
        lista
            .sorted { $0.orden < $1.orden }
            .enumerated()
            .map { index, estudiante in estudiante.con(orden: index + 1) }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                withAnimation(EPTheme.spring) {
                    mostrandoEstudiantes.toggle()
                }
            } label: {
                Label(
                    mostrandoEstudiantes ? "Ocultar estudiantes" : "Estudiantes (\(course.students))",
                    systemImage: "person.2.fill"
                )
                .font(.caption.weight(.black))
                .foregroundStyle(mostrandoEstudiantes ? .white : EPTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(mostrandoEstudiantes ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(EPTheme.primary.opacity(0.1)), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                confirmandoEliminar = true
            } label: {
                Label(course.academicKind == nil ? "Eliminar curso" : "Archivar curso", systemImage: course.academicKind == nil ? "trash" : "archivebox")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemGroupedBackground).opacity(0.5))
    }

    private func metricChip(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .black))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct AcademicCourseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProfileViewModel
    @State private var kind: AcademicCourseKind = .oficial
    @State private var level = AcademicContract.officialLevels.first ?? "1ro Básico"
    @State private var section = "A"
    @State private var workshopName = ""
    @State private var colorHex = "#EC4899"
    @State private var selectedSubjects: Set<String> = []
    @State private var curriculumOptions: [CurriculumSubjectOption] = []
    @State private var isSaving = false

    private var officialName: String {
        (try? AcademicContract.officialCourseName(level: level, section: section)) ?? "Curso"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tipo") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(AcademicCourseKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .oficial {
                    Section("Identidad oficial") {
                        Picker("Nivel", selection: $level) {
                            ForEach(AcademicContract.officialLevels, id: \.self) { Text(AcademicContract.displayLevel($0)).tag($0) }
                        }
                        Picker("Sección", selection: $section) {
                            ForEach(AcademicContract.sections, id: \.self) { Text($0).tag($0) }
                        }
                        LabeledContent("Nombre", value: officialName)
                    }

                    Section("Asignaturas") {
                        ForEach(curriculumOptions.isEmpty ? AcademicContract.subjects(for: level) : curriculumOptions) { subject in
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle(subject.label, isOn: Binding(
                                    get: { selectedSubjects.contains(subject.id) },
                                    set: { enabled in
                                        if enabled { selectedSubjects.insert(subject.id) }
                                        else { selectedSubjects.remove(subject.id) }
                                    }
                                ))
                                if subject.availability == .unavailable {
                                    Text("Seleccionable · contenido OA aún no publicado")
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .onChange(of: level) { _, newLevel in
                        selectedSubjects.removeAll()
                        Task { curriculumOptions = await viewModel.curriculumSubjects(for: newLevel) }
                    }
                } else {
                    Section("Taller") {
                        TextField("Nombre del taller", text: $workshopName)
                        Text("Los talleres no usan nivel ni asignaturas curriculares oficiales.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Color") { BloqueColorPalette(colorHex: $colorHex) }
            }
            .navigationTitle(kind == .oficial ? "Nuevo curso" : "Nuevo taller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { create() }
                        .fontWeight(.bold)
                        .disabled(isSaving || (kind == .taller && workshopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
        .task { curriculumOptions = await viewModel.curriculumSubjects(for: level) }
    }

    private func create() {
        let courseID = UUID().uuidString.lowercased()
        let name = kind == .oficial ? officialName : workshopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dataKeySource = kind == .oficial ? name : "\(name)_\(courseID)"
        let options = curriculumOptions.isEmpty ? AcademicContract.subjects(for: level) : curriculumOptions
        let course = AcademicCourse(
            courseID: courseID,
            dataKey: AcademicContract.normalizedKey(dataKeySource),
            kind: kind,
            name: name,
            level: kind == .oficial ? level : nil,
            section: kind == .oficial ? section : nil,
            workshopName: kind == .taller ? name : nil,
            subjects: kind == .oficial ? options.filter { selectedSubjects.contains($0.id) }.map {
                CourseSubjectSelection(id: $0.id, label: $0.label, availability: $0.availability)
            } : [],
            colorHex: colorHex,
            status: .active,
            archivedAt: nil,
            deleteEligibleAt: nil
        )
        isSaving = true
        Task {
            await viewModel.saveCourse(course)
            isSaving = false
            if viewModel.errorMessage == nil { dismiss() }
        }
    }
}

private extension EstudiantePerfil {
    func con(
        nombre: String? = nil,
        orden: Int? = nil,
        pie: Bool? = nil,
        pieDiagnostico: String? = nil,
        pieEspecialista: String? = nil,
        pieNotas: String? = nil
    ) -> EstudiantePerfil {
        EstudiantePerfil(
            id: id,
            nombre: nombre ?? self.nombre,
            orden: orden ?? self.orden,
            pie: pie ?? self.pie,
            pieDiagnostico: pieDiagnostico ?? self.pieDiagnostico,
            pieEspecialista: pieEspecialista ?? self.pieEspecialista,
            pieNotas: pieNotas ?? self.pieNotas
        )
    }
}
