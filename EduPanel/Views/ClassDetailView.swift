import SwiftUI

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

    @Environment(\.displayMode) private var displayMode

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
            .padding(.bottom, 28)
        }
        .background(EPTheme.background)
        .navigationTitle(title.isEmpty ? "Detalle de clase" : title)
        .task(id: classId) { await cargar(forceRefresh: false) }
        .refreshable { await cargar(forceRefresh: true) }
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
                EPStatusPill(text: "\(snapshot.studentCounts[clase.resumen] ?? 0) estudiantes", icon: "person.2.fill", tint: .white)
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
                detailRow("Estudiantes", "\(snapshot.studentCounts[clase.resumen] ?? 0)")
            }
        }
    }

    private func estudiantesCard(snapshot: DashboardSnapshot, clase: ClaseHorario) -> some View {
        let estudiantes = snapshot.studentsByCourse[clase.resumen] ?? []
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
            } else {
                plan = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
