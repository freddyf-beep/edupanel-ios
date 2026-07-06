import SwiftUI

private struct ClasePlanificadaItem: Identifiable, Hashable {
    let bloque: ClaseHorario
    let unidad: UnidadPlan?
    let asignatura: String?

    var id: String {
        "\(bloque.id)::\(unidad?.id ?? 0)::\(asignatura ?? "")"
    }
}

struct ClasesView: View {
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository

    @State private var snapshot: DashboardSnapshot?
    @State private var planes: [PlanificacionCurso] = []
    @State private var selectedDia = DateHelpers.weekdayName(for: Date()) ?? "Lunes"
    @State private var selectedCurso = "__todos__"
    @State private var isLoading = true
    @State private var errorMessage: String?

    @Environment(\.displayMode) private var displayMode

    private let diasSemana = ["Lunes", "Martes", "Mi\u{00E9}rcoles", "Jueves", "Viernes"]

    private var tabs: [EPWebTab] {
        diasSemana.map { dia in
            EPWebTab(id: dia, title: diaAbreviado(dia), icon: dia == selectedDia ? "calendar.day.timeline.left" : "calendar")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && snapshot == nil {
                    loadingState
                } else {
                    contenido
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(EPTheme.background)
        .navigationTitle("Clases")
        .task { await cargar() }
        .refreshable { await cargar(forceRefresh: true) }
    }

    @ViewBuilder
    private var contenido: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage {
                    errorBanner(errorMessage)
                }

                header(snapshot)

                if snapshot.academicClasses.isEmpty {
                    EPWebCard {
                        EPEmptyState(
                            icon: "calendar.badge.exclamationmark",
                            title: "Sin clases en tu horario",
                            message: "Configura bloques de clase en Mi Perfil para usar el libro de clases."
                        )
                    }
                } else {
                    controles(snapshot)
                    kpis(snapshot)
                    EPWebTabBar(tabs: tabs, selected: $selectedDia)
                    bloquesDelDia(snapshot)
                }
            }
        } else {
            EPWebCard {
                EPEmptyState(
                    icon: "wifi.exclamationmark",
                    title: "No fue posible cargar tus clases",
                    message: "Revisa tu conexi\u{00F3}n e intenta nuevamente."
                )
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando libro de clases...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func header(_ snapshot: DashboardSnapshot) -> some View {
        EPModuleHeader(
            eyebrow: "Libro de clases",
            title: "Agenda y leccionario",
            subtitle: "Revisa tus bloques por d\u{00ED}a, estudiantes asociados y el acceso directo a las clases planificadas.",
            icon: "calendar.badge.clock",
            accent: .primary
        ) {
            HStack(spacing: 8) {
                EPStatusPill(text: "\(snapshot.academicClasses.count) bloques", icon: "calendar", tint: .white)
                EPStatusPill(text: "\(snapshot.courses.count) cursos", icon: "person.3.fill", tint: .white)
                Spacer(minLength: 0)
            }
        }
    }

    private func controles(_ snapshot: DashboardSnapshot) -> some View {
        EPWebCard(padding: 12) {
            HStack(spacing: 10) {
                Menu {
                    Button {
                        selectedCurso = "__todos__"
                    } label: {
                        Label("Todos los cursos", systemImage: selectedCurso == "__todos__" ? "checkmark" : "tray.full")
                    }

                    ForEach(snapshot.courses, id: \.self) { curso in
                        Button {
                            selectedCurso = curso
                        } label: {
                            Label(curso, systemImage: selectedCurso == curso ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    EPStatusPill(
                        text: selectedCurso == "__todos__" ? "Todos los cursos" : selectedCurso,
                        icon: "folder.fill"
                    )
                }

                Spacer(minLength: 0)

                if selectedDia != (snapshot.todayName ?? selectedDia), let today = snapshot.todayName, diasSemana.contains(today) {
                    Button {
                        withAnimation(EPTheme.spring) {
                            selectedDia = today
                        }
                    } label: {
                        Label("Hoy", systemImage: "location.fill")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(EPTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func kpis(_ snapshot: DashboardSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            EPKPIBox(
                title: "Bloques del d\u{00ED}a",
                value: "\(itemsDelDia(snapshot).count)",
                subtitle: selectedDia,
                icon: "calendar.day.timeline.left",
                tint: EPTheme.primary
            )
            EPKPIBox(
                title: "Estudiantes",
                value: "\(estudiantesDelDia(snapshot))",
                subtitle: "en cursos visibles",
                icon: "person.2.fill",
                tint: .blue
            )
            if !displayMode.isSimple {
                EPKPIBox(
                    title: "Planificadas",
                    value: "\(itemsDelDia(snapshot).filter { $0.unidad != nil }.count)",
                    subtitle: "con unidad vinculada",
                    icon: "book.closed.fill",
                    tint: .green
                )
                EPKPIBox(
                    title: "Pendientes hoy",
                    value: "\(snapshot.pendingClasses.count)",
                    subtitle: "por registrar",
                    icon: "exclamationmark.circle.fill",
                    tint: snapshot.pendingClasses.isEmpty ? .green : .orange
                )
            }
        }
    }

    private func bloquesDelDia(_ snapshot: DashboardSnapshot) -> some View {
        let items = itemsDelDia(snapshot)
        return VStack(alignment: .leading, spacing: 12) {
            EPSectionHeader(
                title: selectedCurso == "__todos__" ? "Clases de \(selectedDia)" : "\(selectedCurso) - \(selectedDia)",
                subtitle: items.isEmpty ? "No hay bloques acad\u{00E9}micos para este filtro." : "\(items.count) bloque\(items.count == 1 ? "" : "s") ordenado\(items.count == 1 ? "" : "s") por hora.",
                icon: "list.bullet.rectangle"
            )

            if items.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "moon.zzz.fill",
                        title: "Sin clases para mostrar",
                        message: "Cambia de d\u{00ED}a o curso para revisar otros bloques del horario."
                    )
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        claseRow(item, snapshot: snapshot)
                    }
                }
            }
        }
    }

    private func claseRow(_ item: ClasePlanificadaItem, snapshot: DashboardSnapshot) -> some View {
        EPWebCard(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 3) {
                    Text(String(item.bloque.horaInicio.prefix(5)))
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                    Text(String(item.bloque.horaFin.prefix(5)))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .frame(width: 54, height: 52)
                .background(EPTheme.color(hex: item.bloque.colorHex), in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.bloque.resumen)
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Text(item.asignatura ?? item.bloque.asignatura ?? "Asignatura sin definir")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        estadoPill(item.bloque, snapshot: snapshot)
                    }

                    HStack(spacing: 6) {
                        EPStatusPill(text: "\(snapshot.studentCounts[item.bloque.resumen] ?? 0) estudiantes", icon: "person.2.fill", tint: .blue)
                        EPStatusPill(text: item.unidad?.name ?? "Sin unidad", icon: item.unidad == nil ? "link.badge.plus" : "book.closed.fill", tint: item.unidad == nil ? .orange : .green)
                    }

                    if let unidad = item.unidad, let asignatura = item.asignatura ?? item.bloque.asignatura {
                        HStack(spacing: 8) {
                            NavigationLink(value: AppRoute.verUnidad(
                                curso: item.bloque.resumen,
                                asignatura: asignatura,
                                unidadId: String(unidad.id),
                                unidadNombre: unidad.name,
                                initialTab: "clases"
                            )) {
                                Label("Abrir clases", systemImage: "rectangle.stack.fill")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(EPTheme.primary)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(value: AppRoute.verUnidad(
                                curso: item.bloque.resumen,
                                asignatura: asignatura,
                                unidadId: String(unidad.id),
                                unidadNombre: unidad.name,
                                initialTab: "unidad"
                            )) {
                                Label("Unidad", systemImage: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func estadoPill(_ bloque: ClaseHorario, snapshot: DashboardSnapshot) -> some View {
        guard bloque.dia == snapshot.todayName else {
            return EPStatusPill(text: bloque.dia, icon: "calendar", tint: .gray)
        }
        if snapshot.classState[bloque.id] == true {
            return EPStatusPill(text: "Dictada", icon: "checkmark.seal.fill", tint: .green)
        }
        if isCurrent(bloque) {
            return EPStatusPill(text: "En curso", icon: "waveform.path.ecg", tint: EPTheme.primary)
        }
        return EPStatusPill(text: "Pendiente", icon: "clock.fill", tint: .orange)
    }

    private func itemsDelDia(_ snapshot: DashboardSnapshot) -> [ClasePlanificadaItem] {
        snapshot.academicClasses
            .filter { $0.dia == selectedDia }
            .filter { selectedCurso == "__todos__" || $0.resumen == selectedCurso }
            .sorted { lhs, rhs in
                if lhs.horaInicio == rhs.horaInicio { return lhs.resumen < rhs.resumen }
                return lhs.horaInicio < rhs.horaInicio
            }
            .map { bloque in
                let plan = planPara(bloque)
                return ClasePlanificadaItem(
                    bloque: bloque,
                    unidad: unidadActiva(en: plan),
                    asignatura: plan?.asignatura ?? bloque.asignatura
                )
            }
    }

    private func estudiantesDelDia(_ snapshot: DashboardSnapshot) -> Int {
        let cursos = Set(itemsDelDia(snapshot).map(\.bloque.resumen))
        return cursos.reduce(0) { total, curso in
            total + (snapshot.studentCounts[curso] ?? 0)
        }
    }

    private func planPara(_ bloque: ClaseHorario) -> PlanificacionCurso? {
        let asignatura = bloque.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let asignatura, !asignatura.isEmpty {
            return planes.first { plan in
                plan.curso == bloque.resumen && plan.asignatura == asignatura
            } ?? planes.first { $0.curso == bloque.resumen }
        }
        return planes.first { $0.curso == bloque.resumen }
    }

    private func unidadActiva(en plan: PlanificacionCurso?) -> UnidadPlan? {
        guard let plan else { return nil }
        let todayActive = plan.units.first { UnitPlanningState.state(for: $0) == .actual }
        return todayActive ?? plan.units.first { UnitPlanningState.state(for: $0) == .futura } ?? plan.units.first
    }

    private func cargar(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await dashboardRepository.fetchDashboard(forceRefresh: forceRefresh)
            snapshot = data
            if let today = data.todayName, diasSemana.contains(today), !diasSemana.contains(selectedDia) {
                selectedDia = today
            }
            if selectedCurso != "__todos__", !data.courses.contains(selectedCurso) {
                selectedCurso = "__todos__"
            }
            let asignaturas = Array(Set(data.academicClasses.compactMap(\.asignatura))).sorted()
            planes = try await planificacionRepository.listarTodosPlanesCurso(
                posiblesCursos: data.courses,
                posiblesAsignaturas: asignaturas
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
    }

    private func isCurrent(_ bloque: ClaseHorario) -> Bool {
        let now = Date()
        guard bloque.dia == DateHelpers.weekdayName(for: now) else { return false }
        let current = DateHelpers.minutesSinceMidnight(for: now)
        return current >= DateHelpers.minutes(from: bloque.horaInicio) && current < DateHelpers.minutes(from: bloque.horaFin)
    }

    private func diaAbreviado(_ dia: String) -> String {
        switch dia {
        case "Lunes": return "Lun"
        case "Martes": return "Mar"
        case "Mi\u{00E9}rcoles": return "Mi\u{00E9}"
        case "Jueves": return "Jue"
        case "Viernes": return "Vie"
        default: return dia
        }
    }
}
