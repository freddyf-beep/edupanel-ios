import SwiftUI

private struct ClassDictationContext: Identifiable {
    let id = UUID()
    let contextualStrings: [String]
    let voiceContext: VoiceNoteContext
    let linkOptions: [VoiceNoteLinkOption]
}

private enum ClassDetailLogError: LocalizedError {
    case signedBlock
    case unavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .signedBlock:
            return "Este registro ya está firmado. Reábrelo desde Asistencia antes de editarlo."
        case .unavailable:
            return "El registro de esta clase todavía no está disponible. Reintenta en unos segundos."
        case .saveFailed:
            return "No pudimos guardar el registro. Revisa tu conexión e inténtalo nuevamente."
        }
    }
}

struct ClassDetailView: View {
    let classId: String
    let title: String
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    @State private var snapshot: DashboardSnapshot?
    @State private var clase: ClaseHorario?
    @State private var plan: PlanificacionCurso?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var attendanceModel: AttendanceViewModel?
    @State private var isLoadingClassLog = false
    @State private var classLogErrorMessage: String?
    @State private var classLogSavedNotice = false
    @State private var dictationContext: ClassDictationContext?

    @Environment(\.displayMode) private var displayMode
    @Environment(AuthSession.self) private var authSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && clase == nil {
                    loadingState
                } else if let snapshot, let clase {
                    contenido(snapshot: snapshot, clase: clase)
                } else {
                    EPWebCard {
                        EPEmptyState(
                            icon: "calendar.badge.exclamationmark",
                            title: "Clase no encontrada",
                            message: "El bloque ya no existe en tu horario semanal."
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .tabBarPageBottomPadding()
        }
        .background(EPTheme.background)
        .navigationTitle(title.isEmpty ? "Detalle de clase" : title)
        .task(id: classId) { await cargar(forceRefresh: false) }
        .refreshable { await cargar(forceRefresh: true) }
        .sheet(item: $dictationContext) { context in
            DictadoModalView(
                contextualStrings: context.contextualStrings,
                ownerID: activeUserID,
                mode: .guiado,
                context: context.voiceContext,
                linkOptions: context.linkOptions,
                linkAction: { draft in
                    try await guardarRegistro(
                        draft,
                        students: context.linkOptions.first?.students ?? []
                    )
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando clase...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func contenido(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage {
                errorBanner(errorMessage)
            }

            header(snapshot: snapshot, clase: clase)
            estadoCard(snapshot: snapshot, clase: clase)
            detalleCard(snapshot: snapshot, clase: clase)
            estudiantesCard(snapshot: snapshot, clase: clase)
            planificacionCard(clase: clase)
            registroClaseCard(snapshot: snapshot, clase: clase)
        }
    }

    private func header(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        EPModuleHeader(
            eyebrow: "Detalle de clase",
            title: clase.resumen.isEmpty ? clase.tipo.label : clase.resumen,
            subtitle: "\(clase.dia) - \(clase.timeRange)",
            icon: "calendar.badge.clock",
            accent: .primary
        ) {
            HStack(spacing: 8) {
                EPStatusPill(text: clase.asignatura ?? "Asignatura pendiente", icon: "book.closed.fill", tint: .white)
                EPStatusPill(text: "\(snapshot.studentCount(forCourseID: clase.courseID, name: clase.resumen)) estudiantes", icon: "person.2.fill", tint: .white)
                Spacer(minLength: 0)
            }
        }
    }

    private func estadoCard(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        let isCompleted = snapshot.classState[clase.id] == true
        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Registro diario",
                    subtitle: "Marca el bloque como dictado cuando la clase quede registrada.",
                    icon: "checkmark.seal.fill"
                )

                HStack(spacing: 10) {
                    estadoPill(snapshot: snapshot, clase: clase)
                    Spacer(minLength: 0)
                    Button {
                        Task { await toggleDictada(clase: clase) }
                    } label: {
                        Label(isCompleted ? "Marcar pendiente" : "Marcar dictada", systemImage: isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .black))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCompleted ? .orange : .green)
                    .disabled(isSaving)
                }

                if isSaving {
                    Label("Guardando estado...", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detalleCard(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Datos del bloque",
                    subtitle: nil,
                    icon: "info.circle.fill"
                )

                detailRow("Curso", clase.resumen.isEmpty ? "Sin curso" : clase.resumen)
                detailRow("Tipo", clase.tipo.label)
                detailRow("Horario", clase.timeRange)
                detailRow("Dia", clase.dia)
                detailRow("Asignatura", clase.asignatura ?? "Sin asignatura")
                detailRow("Estudiantes", "\(snapshot.studentCount(forCourseID: clase.courseID, name: clase.resumen))")
            }
        }
    }

    private func estudiantesCard(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        let estudiantes = snapshot.students(forCourseID: clase.courseID, name: clase.resumen)
        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Estudiantes del curso",
                    subtitle: estudiantes.isEmpty ? "Aun no hay estudiantes cargados para este curso." : "\(estudiantes.count) estudiante\(estudiantes.count == 1 ? "" : "s") en Mi Perfil.",
                    icon: "person.2.fill"
                )

                if estudiantes.isEmpty {
                    EPEmptyState(
                        icon: "person.crop.circle.badge.plus",
                        title: "Sin estudiantes",
                        message: "Carga la lista del curso desde Mi Perfil para verlos aqui."
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(estudiantes.prefix(displayMode.isSimple ? 6 : 12)) { estudiante in
                            HStack(spacing: 8) {
                                Text("\(estudiante.orden)")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(estudiante.nombre)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if estudiante.pie {
                                    EPStatusPill(text: "PIE", tint: .orange)
                                }
                            }
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) {
                                Divider().opacity(0.35)
                            }
                        }
                    }

                    if estudiantes.count > (displayMode.isSimple ? 6 : 12) {
                        Text("+ \(estudiantes.count - (displayMode.isSimple ? 6 : 12)) estudiantes mas")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func planificacionCard(clase: ClaseHorario) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Planificacion asociada",
                    subtitle: nil,
                    icon: "book.closed.fill"
                )

                if let plan {
                    detailRow("Asignatura", plan.asignatura)
                    detailRow("Unidades", "\(plan.units.count)")

                    if let unit = unidadActiva(en: plan) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(unit.name)
                                .font(.system(size: 14, weight: .black))
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                EPStatusPill(text: "\(unit.hours)h", icon: "clock.fill", tint: .blue)
                                EPStatusPill(text: UnitPlanningState.state(for: unit).label, icon: UnitPlanningState.state(for: unit).icon, tint: UnitPlanningState.state(for: unit).tint)
                            }

                            NavigationLink(value: AppRoute.verUnidad(
                                curso: clase.resumen,
                                asignatura: plan.asignatura,
                                unidadId: String(unit.id),
                                unidadNombre: unit.name,
                                initialTab: "clases"
                            )) {
                                Label("Abrir clases de la unidad", systemImage: "rectangle.stack.fill")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(EPTheme.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
                    }
                } else {
                    EPEmptyState(
                        icon: "book.closed",
                        title: "Sin planificacion vinculada",
                        message: "Crea una planificacion para este curso y asignatura para enlazar sus clases."
                    )
                }
            }
        }
    }

    private func registroClaseCard(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Registro de la clase",
                    subtitle: "Agrega una nota nueva sin reemplazar los comentarios que ya guardaste.",
                    icon: "waveform.and.mic"
                )

                if isLoadingClassLog {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Cargando registro…")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if let classLogErrorMessage {
                        Label(classLogErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Reintentar") {
                            Task { await cargarRegistro(clase: clase, date: Date()) }
                        }
                        .font(.footnote.weight(.bold))
                    }

                    if let block = attendanceModel?.activeBlock, !block.activity.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COMENTARIOS")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)

                            Text(block.activity)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                            if !block.objective.isEmpty {
                                Divider()
                                detailRow("Objetivo", block.objective)
                            }
                        }
                        .padding(12)
                        .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
                    } else if classLogErrorMessage == nil {
                        EPEmptyState(
                            icon: "text.bubble",
                            title: "Aún no hay comentarios",
                            message: "Puedes dictarlos o escribirlos y revisarlos antes de guardar."
                        )
                    }

                    if classLogSavedNotice {
                        Label("Registro guardado en esta clase", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.green)
                    }

                    Button {
                        abrirDictado(snapshot: snapshot, clase: clase)
                    } label: {
                        Label(
                            attendanceModel?.activeBlock?.activity.isEmpty == false ? "Agregar comentario por voz" : "Registrar por voz",
                            systemImage: "mic.fill"
                        )
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(attendanceModel?.activeBlock?.isSigned == true || isLoadingClassLog)
                    .opacity(attendanceModel?.activeBlock?.isSigned == true ? 0.55 : 1)
                    .accessibilityHint("Abre un texto editable. El borrador se guarda localmente y puedes confirmar después para vincularlo a esta clase.")

                    if attendanceModel?.activeBlock?.isSigned == true {
                        Label("El leccionario está firmado y se muestra en modo lectura.", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func estadoPill(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        if snapshot.classState[clase.id] == true {
            return EPStatusPill(text: "Dictada", icon: "checkmark.seal.fill", tint: .green)
        }
        if isCurrent(clase) {
            return EPStatusPill(text: "En curso", icon: "waveform.path.ecg", tint: EPTheme.primary)
        }
        return EPStatusPill(text: "Pendiente", icon: "clock.fill", tint: .orange)
    }

    private func cargar(forceRefresh: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await dashboardRepository.fetchDashboard(forceRefresh: forceRefresh)
            snapshot = data
            clase = data.horario.first { $0.id == classId }

            if let clase = data.horario.first(where: { $0.id == classId }) {
                plan = try? await cargarPlan(clase: clase, snapshot: data)
                await cargarRegistro(clase: clase, date: Date())
            } else {
                plan = nil
                attendanceModel = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func cargarRegistro(clase: ClaseHorario, date: Date) async {
        guard let subject = resolvedSubject(for: clase) else {
            attendanceModel = nil
            classLogErrorMessage = "Define una asignatura para vincular el registro."
            return
        }

        isLoadingClassLog = true
        classLogErrorMessage = nil
        let model = AttendanceViewModel(
            course: clase.resumen,
            subject: subject,
            date: date,
            initialBlockID: clase.id,
            dashboardRepository: dashboardRepository
        )
        attendanceModel = model
        await model.load(forceRefresh: false)
        if case .failed = model.loadState {
            classLogErrorMessage = "No pudimos cargar el registro. Revisa tu conexión y reintenta."
        }
        isLoadingClassLog = false
    }

    private func abrirDictado(snapshot: DashboardSnapshot, clase: ClaseHorario) {
        guard let subject = resolvedSubject(for: clase) else {
            classLogErrorMessage = "Define una asignatura para registrar comentarios."
            return
        }
        let course = snapshot.course(id: clase.courseID, named: clase.resumen)
        let activeUnit = plan.flatMap(unidadActiva(en:))
        let voiceContext = VoiceNoteContext(
            courseID: clase.courseID ?? course?.courseID,
            courseName: course?.name ?? clase.resumen,
            courseKind: course?.kind,
            subjectID: clase.subjectID ?? snapshot.academicSelection(courseName: clase.resumen, subjectName: subject)?.subjectID,
            subjectName: subject,
            classID: clase.id,
            classTitle: clase.resumen.isEmpty ? clase.tipo.label : clase.resumen,
            dateKey: DateHelpers.dateKey(for: snapshot.date),
            unitID: activeUnit.map { String($0.id) },
            unitName: activeUnit?.name,
            activityID: attendanceModel?.activeBlock?.id
        )
        let students = snapshot.students(forCourseID: clase.courseID, name: clase.resumen).map {
            VoiceNoteStudentOption(id: $0.id, name: $0.nombre)
        }
        let option = VoiceNoteLinkOption(
            title: "\(course?.name ?? clase.resumen) · \(clase.horaInicio)",
            subtitle: subject,
            context: voiceContext,
            students: students
        )

        classLogSavedNotice = false
        dictationContext = ClassDictationContext(
            contextualStrings: voiceContext.safeContextualStrings,
            voiceContext: voiceContext,
            linkOptions: [option]
        )
    }

    private var activeUserID: String? {
        guard case .signedIn(let user) = authSession.state else { return nil }
        return user.id
    }

    private func guardarRegistro(
        _ draft: VoiceNoteDraft,
        students: [VoiceNoteStudentOption]
    ) async throws {
        guard let attendanceModel, let block = attendanceModel.activeBlock else {
            throw ClassDetailLogError.unavailable
        }
        guard !block.isSigned else { throw ClassDetailLogError.signedBlock }

        let rendered = renderedVoiceNote(draft, students: students)
        switch attendanceModel.appendVoiceNote(
            rendered,
            noteID: draft.id,
            metadata: draft.context.attendanceMetadata
        ) {
        case .appended, .metadataUpdated, .duplicate:
            break
        case .contentChanged:
            throw VoiceNoteLinkingError.contentChanged
        case .signedBlock:
            throw ClassDetailLogError.signedBlock
        case .unavailableBlock, .emptyContent:
            throw ClassDetailLogError.unavailable
        }
        guard await attendanceModel.save(providesFeedback: true) else {
            throw ClassDetailLogError.saveFailed
        }
        classLogErrorMessage = nil
        classLogSavedNotice = true
    }

    private func renderedVoiceNote(
        _ draft: VoiceNoteDraft,
        students: [VoiceNoteStudentOption]
    ) -> String {
        var sections = [draft.text.trimmingCharacters(in: .whitespacesAndNewlines)]
        let selectedNames = students
            .filter { draft.context.studentIDs.contains($0.id) }
            .map(\.name)
        if !selectedNames.isEmpty {
            sections.append("Estudiante\(selectedNames.count == 1 ? "" : "s"): \(selectedNames.joined(separator: ", "))")
        }
        if let value = nonEmpty(draft.context.topic) { sections.append("Tema: \(value)") }
        if let value = nonEmpty(draft.context.observationType) { sections.append("Observación: \(value)") }
        if let value = nonEmpty(draft.context.outcome) { sections.append("Resultado: \(value)") }
        if let value = nonEmpty(draft.context.nextStep) { sections.append("Próximo paso: \(value)") }
        if let value = nonEmpty(draft.context.classSummary) { sections.append("Resumen: \(value)") }
        return sections.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private func resolvedSubject(for clase: ClaseHorario) -> String? {
        let value = (clase.asignatura ?? plan?.asignatura ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func cargarPlan(clase: ClaseHorario, snapshot: DashboardSnapshot) async throws -> PlanificacionCurso? {
        if let asignatura = clase.asignatura, !asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await planificacionRepository.cargarPlanCurso(asignatura: asignatura, curso: clase.resumen)
        }
        let asignaturas = Array(Set(snapshot.academicClasses.compactMap(\.asignatura))).sorted()
        let planes = try await planificacionRepository.listarTodosPlanesCurso(
            posiblesCursos: [clase.resumen],
            posiblesAsignaturas: asignaturas
        )
        return planes.first { $0.curso == clase.resumen }
    }

    private func toggleDictada(clase: ClaseHorario) async {
        guard var current = snapshot else { return }
        isSaving = true
        errorMessage = nil
        var state = current.classState
        state[clase.id] = !(state[clase.id] == true)
        do {
            try await dashboardRepository.saveClassState(state)
            current.classState = state
            snapshot = current
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func unidadActiva(en plan: PlanificacionCurso) -> UnidadPlan? {
        let actual = plan.units.first { UnitPlanningState.state(for: $0) == .actual }
        return actual ?? plan.units.first { UnitPlanningState.state(for: $0) == .futura } ?? plan.units.first
    }

    private func isCurrent(_ clase: ClaseHorario) -> Bool {
        let now = Date()
        guard clase.dia == DateHelpers.weekdayName(for: now) else { return false }
        let current = DateHelpers.minutesSinceMidnight(for: now)
        return current >= DateHelpers.minutes(from: clase.horaInicio) && current < DateHelpers.minutes(from: clase.horaFin)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
    }
}
