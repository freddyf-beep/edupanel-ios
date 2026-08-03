import SwiftUI

struct ProfileCoursesTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot
    @Binding var selectedTab: ProfileTabKey
    @State private var searchText = ""
    @State private var filter: ProfileCourseFilter = .all
    @State private var presentedSheet: ProfileCoursesSheet?

    private var courses: [ProfileCourseSummary] {
        viewModel.courseSummaries(for: snapshot)
    }

    private var filteredCourses: [ProfileCourseSummary] {
        courses.filter { course in
            let matchesFilter = switch filter {
            case .all: true
            case .official: course.type == .oficial
            case .workshops: course.type != .oficial
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchableText = ([course.name, course.levelText] + course.subjects).joined(separator: " ")
            return matchesFilter && (query.isEmpty || searchableText.localizedStandardContains(query))
        }
    }

    private var showsTypeFilter: Bool {
        courses.contains { $0.type == .oficial } && courses.contains { $0.type != .oficial }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    title
                    Spacer(minLength: 8)
                    headerActions
                }

                VStack(alignment: .leading, spacing: 3) {
                    title
                    headerActions
                        .padding(.top, 8)
                }
            }

            if snapshot.courseCatalog.isEmpty, !snapshot.courses.isEmpty {
                legacyCoursesBanner
            }

            if courses.count >= 4 {
                searchAndFilter
            }

            if courses.isEmpty {
                ProfileEmptyAction(
                    icon: "folder.badge.plus",
                    title: "Aún no tienes cursos",
                    message: "Crea tu primer curso o taller. Después podrás agregar asignaturas, horario y estudiantes.",
                    buttonTitle: "Crear curso"
                ) {
                    presentedSheet = .create
                }
            } else if filteredCourses.isEmpty {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "No hay cursos en este filtro",
                        systemImage: filter.systemImage,
                        description: Text("Prueba mostrando todos los cursos.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredCourses) { course in
                        ProfileCourseCard(viewModel: viewModel, course: course) {
                            presentedSheet = .manage(courseID: course.courseID, courseName: course.name)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                ProfileSaveBadge(status: viewModel.saveHorarioStatus)
                ProfileSaveBadge(status: viewModel.saveMappingStatus)
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .create:
                AcademicCourseEditorSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .manage(let courseID, let courseName):
                CourseWorkspaceSheet(
                    viewModel: viewModel,
                    courseID: courseID,
                    initialCourseName: courseName
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .archived:
                ArchivedCoursesSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var title: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(EPTheme.primary)
                .frame(width: 36, height: 36)
                .background(EPTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Mis cursos")
                    .font(.title3.weight(.black))
                Text("Niveles, asignaturas y estudiantes en un solo lugar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            if !snapshot.archivedCourses.isEmpty {
                Button {
                    presentedSheet = .archived
                } label: {
                    Label("Archivados", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)
            }

            Button {
                presentedSheet = .create
            } label: {
                Label("Crear curso", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        }
        .font(.footnote.weight(.bold))
    }

    private var legacyCoursesBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tienes cursos de una versión anterior", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.orange)
            Text("Reorganízalos para usar niveles y asignaturas en toda la app. No se borrará tu configuración anterior.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await viewModel.importLegacyCourses() }
            } label: {
                Label("Reorganizar cursos", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .font(.footnote.weight(.bold))
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.22))
        }
    }

    private var searchAndFilter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar curso o asignatura", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar búsqueda")
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if showsTypeFilter || filter != .all {
                Menu {
                    Picker("Tipo de curso", selection: $filter) {
                        ForEach(ProfileCourseFilter.allCases) { filter in
                            Label(filter.title, systemImage: filter.systemImage)
                                .tag(filter)
                        }
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(filter == .all ? AnyShapeStyle(.secondary) : AnyShapeStyle(EPTheme.primary))
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Filtrar cursos")
                .accessibilityValue(filter.title)
            }
        }
    }
}

private enum ProfileCourseFilter: String, CaseIterable, Identifiable {
    case all
    case official
    case workshops

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todos"
        case .official: "Oficiales"
        case .workshops: "Talleres"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .official: "graduationcap"
        case .workshops: "sparkles"
        }
    }
}

private enum ProfileCoursesSheet: Identifiable {
    case create
    case manage(courseID: String, courseName: String)
    case archived

    var id: String {
        switch self {
        case .create: "create"
        case .manage(let courseID, _): "manage-\(courseID)"
        case .archived: "archived"
        }
    }
}

private struct ProfileCourseCard: View {
    let viewModel: ProfileViewModel
    let course: ProfileCourseSummary
    let onManage: () -> Void

    @State private var confirmsArchive = false

    private var isOfficial: Bool { course.type == .oficial }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(profileHex: course.colorHex))
                .frame(height: 5)

            Button(action: onManage) {
                VStack(alignment: .leading, spacing: 13) {
                    header
                    statistics
                    subjectsPreview
                }
                .padding(15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            HStack(spacing: 6) {
                Button(action: onManage) {
                    Label("Gestionar", systemImage: "slider.horizontal.3")
                }
                .foregroundStyle(EPTheme.primary)

                Spacer(minLength: 6)

                NavigationLink(value: AppRoute.courseStudents(course.name)) {
                    Label("Estudiantes", systemImage: "person.2")
                }

                Menu {
                    Button(role: .destructive) {
                        confirmsArchive = true
                    } label: {
                        Label(course.academicKind == nil ? "Eliminar curso" : "Archivar curso", systemImage: course.academicKind == nil ? "trash" : "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Más opciones para \(course.name)")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.12))
        }
        .confirmationDialog(
            course.academicKind == nil ? "¿Eliminar \(course.name)?" : "¿Archivar \(course.name)?",
            isPresented: $confirmsArchive,
            titleVisibility: .visible
        ) {
            Button(course.academicKind == nil ? "Eliminar curso" : "Archivar curso", role: .destructive) {
                if course.academicKind == nil {
                    viewModel.removeCurso(course.name)
                } else {
                    Task { await viewModel.archiveCourse(course.courseID) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(course.academicKind == nil
                ? "Se quitarán sus bloques del horario. La nómina de estudiantes no se borrará."
                : "El curso y una copia de sus bloques quedarán guardados en Archivados.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: isOfficial ? "graduationcap.fill" : "sparkles")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(profileHex: course.colorHex))
                .frame(width: 38, height: 38)
                .background(Color(profileHex: course.colorHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Label(course.levelText, systemImage: isOfficial && course.level == nil ? "exclamationmark.triangle.fill" : "checkmark.seal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOfficial && course.level == nil ? .orange : .secondary)
            }

            Spacer(minLength: 4)

            Text(isOfficial ? "Oficial" : "Taller")
                .font(.caption2.weight(.black))
                .foregroundStyle(isOfficial ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background((isOfficial ? Color.green : Color.orange).opacity(0.11), in: Capsule())
        }
    }

    private var statistics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                statistic(course.subjects.count, title: "asignaturas", icon: "book.closed")
                statistic(course.blocks, title: "bloques", icon: "calendar")
                statistic(course.students, title: "estudiantes", icon: "person.2")
            }

            VStack(alignment: .leading, spacing: 7) {
                statistic(course.subjects.count, title: "asignaturas", icon: "book.closed")
                statistic(course.blocks, title: "bloques", icon: "calendar")
                statistic(course.students, title: "estudiantes", icon: "person.2")
            }
        }
        .foregroundStyle(.secondary)
    }

    private func statistic(_ value: Int, title: String, icon: String) -> some View {
        Label("\(value) \(title)", systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
    }

    @ViewBuilder
    private var subjectsPreview: some View {
        if isOfficial {
            if course.subjects.isEmpty {
                Label("Agrega las asignaturas que impartes", systemImage: "plus.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EPTheme.primary)
            } else {
                ReplicaFlowLayout(spacing: 6) {
                    ForEach(Array(course.subjects.prefix(3)), id: \.self) { subject in
                        Text(subject)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                    if course.subjects.count > 3 {
                        Text("+\(course.subjects.count - 3)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                }
            }
        }
    }
}

private struct ArchivedCoursesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileViewModel
    @State private var coursePendingDeletion: AcademicCourse?

    private var courses: [AcademicCourse] {
        viewModel.snapshot?.archivedCourses ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if courses.isEmpty {
                    ContentUnavailableView(
                        "Sin cursos archivados",
                        systemImage: "archivebox",
                        description: Text("Los cursos que archives aparecerán aquí.")
                    )
                } else {
                    List(courses) { course in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(profileHex: course.colorHex))
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.name)
                                    .font(.subheadline.weight(.bold))
                                Text(course.deleteEligibleAt.map { "Protegido hasta \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Protegido por 30 días")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("Restaurar") {
                                Task { await viewModel.restoreCourse(course.courseID) }
                            }
                            .font(.caption.weight(.bold))
                            if course.isDeleteEligible {
                                Button(role: .destructive) {
                                    coursePendingDeletion = course
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Eliminar permanentemente \(course.name)")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Cursos archivados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .sheet(item: $coursePendingDeletion) { course in
                PermanentCourseDeletionSheet(viewModel: viewModel, course: course)
            }
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

private struct CourseWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileViewModel
    let courseID: String
    let initialCourseName: String

    private var course: ProfileCourseSummary? {
        guard let snapshot = viewModel.snapshot else { return nil }
        return viewModel.courseSummaries(for: snapshot).first { $0.courseID == courseID }
    }

    var body: some View {
        if let course {
            CourseWorkspaceContent(viewModel: viewModel, course: course)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Curso no disponible",
                    systemImage: "folder.badge.questionmark",
                    description: Text("No pudimos encontrar \(initialCourseName). Puede que haya sido archivado.")
                )
                .navigationTitle("Gestionar curso")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
            }
        }
    }
}

private enum CourseWorkspaceSection: String, CaseIterable, Identifiable {
    case course
    case students

    var id: String { rawValue }

    var title: String {
        switch self {
        case .course: "Curso"
        case .students: "Estudiantes"
        }
    }
}

private struct CourseWorkspaceContent: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProfileViewModel
    let course: ProfileCourseSummary

    @Environment(\.displayMode) private var displayMode

    @State private var selectedSection: CourseWorkspaceSection = .course
    @State private var renombrando = false
    @State private var nuevoNombre = ""
    @State private var nuevoEstudiante = ""
    @State private var pieExpandido: String?
    @State private var confirmandoEliminar = false
    @State private var agregandoAsignatura = false
    @State private var nuevaAsignatura = ""
    @State private var wizardPreset: WizardPreset?
    @State private var editingBloque: ClaseHorario?
    @State private var editingSubjectsCourse: AcademicCourse?

    private var academicCourse: AcademicCourse? {
        viewModel.snapshot?.courseCatalog.first { $0.courseID == course.courseID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Picker("Contenido del curso", selection: $selectedSection) {
                        ForEach(CourseWorkspaceSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedSection == .course {
                        tipoNivelBlock
                        asignaturasBlock
                    } else {
                        estudiantesBlock
                    }
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Gestionar curso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            confirmandoEliminar = true
                        } label: {
                            Label(course.academicKind == nil ? "Eliminar curso" : "Archivar curso", systemImage: course.academicKind == nil ? "trash" : "archivebox")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Más opciones para \(course.name)")
                }
            }
        }
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
        .sheet(item: $editingSubjectsCourse) { course in
            CourseSubjectsEditorSheet(viewModel: viewModel, course: course)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            course.academicKind == nil ? "¿Eliminar el curso \(course.name) completo?" : "¿Archivar \(course.name)?",
            isPresented: $confirmandoEliminar,
            titleVisibility: .visible
        ) {
            Button(course.academicKind == nil ? "Sí, eliminar curso" : "Archivar curso", role: .destructive) {
                if course.academicKind == nil {
                    viewModel.removeCurso(course.name)
                    dismiss()
                } else {
                    Task {
                        await viewModel.archiveCourse(course.courseID)
                        dismiss()
                    }
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
                if let academicCourse, academicCourse.kind == .oficial {
                    Button {
                        editingSubjectsCourse = academicCourse
                    } label: {
                        Label("Editar", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.bold))
                    .tint(EPTheme.primary)
                } else if academicCourse == nil {
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
            TextField("Nombre y apellido del estudiante", text: $nuevoEstudiante)
                .textFieldStyle(.plain)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onSubmit { agregarEstudiante() }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    agregarEstudiante()
                } label: {
                    Label("Agregar", systemImage: "plus")
                        .font(.caption.weight(.black))
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(nuevoEstudiante.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await viewModel.saveStudents(curso: course.name) }
                } label: {
                    Label("Guardar", systemImage: "square.and.arrow.down.fill")
                        .font(.caption.weight(.black))
                }
                .buttonStyle(.bordered)
                .tint(EPTheme.primary)
            }

            HStack {
                ProfileSaveBadge(status: viewModel.saveStudentsStatus)
                Spacer()
                Text("Los cambios se guardan al presionar Guardar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

private struct CourseSubjectsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProfileViewModel

    @State private var draft: AcademicCourse
    @State private var options: [CurriculumSubjectOption] = []
    @State private var isSaving = false

    init(viewModel: ProfileViewModel, course: AcademicCourse) {
        self.viewModel = viewModel
        _draft = State(initialValue: course)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if options.isEmpty {
                        ProgressView("Cargando asignaturas…")
                    } else {
                        ForEach(options) { option in
                            Toggle(isOn: selectionBinding(for: option)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.label)
                                    if option.availability == .unavailable {
                                        Label("Contenido OA aún no publicado", systemImage: "exclamationmark.circle")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Asignaturas que impartes")
                } footer: {
                    Text("Solo las asignaturas seleccionadas aparecerán al gestionar el horario de este curso.")
                }
            }
            .navigationTitle(draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Guardando…" : "Guardar") {
                        save()
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving || options.isEmpty)
                }
            }
        }
        .task(id: draft.level) {
            guard let level = draft.level else { return }
            options = await viewModel.curriculumSubjects(for: level)
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func selectionBinding(for option: CurriculumSubjectOption) -> Binding<Bool> {
        Binding(
            get: { draft.subjects.contains { $0.id == option.id } },
            set: { isSelected in
                if isSelected {
                    guard !draft.subjects.contains(where: { $0.id == option.id }) else { return }
                    draft.subjects.append(
                        CourseSubjectSelection(
                            id: option.id,
                            label: option.label,
                            availability: option.availability
                        )
                    )
                } else {
                    draft.subjects.removeAll { $0.id == option.id }
                }
            }
        )
    }

    private func save() {
        isSaving = true
        Task {
            await viewModel.saveCourse(draft)
            isSaving = false
            dismiss()
        }
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
                        Text("Podrás elegir las asignaturas después, desde Gestionar curso.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    Button(isSaving ? "Creando…" : "Crear") { create() }
                        .fontWeight(.bold)
                        .disabled(isSaving || (kind == .taller && workshopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func create() {
        let courseID = UUID().uuidString.lowercased()
        let name = kind == .oficial ? officialName : workshopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dataKeySource = kind == .oficial ? name : "\(name)_\(courseID)"
        let course = AcademicCourse(
            courseID: courseID,
            dataKey: AcademicContract.normalizedKey(dataKeySource),
            kind: kind,
            name: name,
            level: kind == .oficial ? level : nil,
            section: kind == .oficial ? section : nil,
            workshopName: kind == .taller ? name : nil,
            subjects: [],
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
