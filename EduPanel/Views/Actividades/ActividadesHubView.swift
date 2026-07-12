import SwiftUI

/// Entrada nativa a las actividades de clase organizadas por asignatura, curso y unidad.
/// La edición vive en `VerUnidad > Clases`, por lo que este hub no duplica escrituras.
struct ActividadesHubView: View {
    @State private var viewModel: PlanificacionesViewModel
    @State private var searchQuery = ""
    @State private var selectedCourse: String?

    init(
        dashboardRepository: DashboardRepository,
        planificacionRepository: PlanificacionRepository
    ) {
        self._viewModel = State(initialValue: PlanificacionesViewModel(
            dashboardRepository: dashboardRepository,
            planificacionRepository: planificacionRepository
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    loadingState
                } else if viewModel.snapshot == nil {
                    fullLoadErrorState
                } else {
                    hubContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(EPTheme.background)
        .navigationTitle("Actividades de clase")
        .task {
            await viewModel.load()
            normalizeSelection()
        }
        .refreshable {
            await viewModel.refresh()
            normalizeSelection()
        }
        .onChange(of: selectedSubject) { _, _ in
            normalizeSelectedCourse()
        }
    }

    private var hubContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = viewModel.errorMessage {
                errorBanner(message: errorMessage)
            }

            heroCard

            if availableSubjects.count > 1 {
                subjectSelector
            }

            if !availableCourses.isEmpty {
                courseSelector
            }

            if viewModel.planes.isEmpty, viewModel.errorMessage != nil {
                plansUnavailableState
            } else if filteredPlans.isEmpty {
                emptyActivitiesState
            } else {
                metricsGrid

                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(filteredPlans, id: \.routeKey) { plan in
                        courseSection(plan)
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Cargando cursos y unidades...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cargando actividades de clase")
    }

    private var fullLoadErrorState: some View {
        EPWebCard {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("No se pudieron cargar las actividades")
                    .font(.title3.weight(.black))
                Text(viewModel.errorMessage ?? "Revisa tu conexión e inténtalo nuevamente.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task {
                        await viewModel.refresh()
                        normalizeSelection()
                    }
                } label: {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("reintentar-actividades")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var heroCard: some View {
        EPModuleHeader(
            eyebrow: "Planificación diaria",
            title: "Actividades de clase",
            subtitle: "Elige una unidad para planificar sus clases o iniciar el modo en vivo.",
            icon: "lightbulb.fill",
            accent: .planificaciones
        ) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                TextField(
                    "",
                    text: $searchQuery,
                    prompt: Text("Buscar unidad, curso o asignatura...")
                        .foregroundStyle(.white.opacity(0.65))
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .tint(.white)
                .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Limpiar búsqueda")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private var subjectSelector: some View {
        EPWebCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(
                    title: "Asignatura",
                    subtitle: "Filtra las unidades que quieres trabajar.",
                    icon: "book.fill"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableSubjects, id: \.self) { subject in
                            filterChip(
                                title: subject,
                                icon: "book.closed.fill",
                                isSelected: subjectKey(subject) == subjectKey(selectedSubject)
                            ) {
                                withAnimation(EPTheme.spring) {
                                    viewModel.selectedSubject = subject
                                    selectedCourse = nil
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var courseSelector: some View {
        EPWebCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(
                    title: "Curso",
                    subtitle: "Puedes ver todos o concentrarte en uno.",
                    icon: "graduationcap.fill"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(
                            title: "Todos",
                            icon: "square.grid.2x2.fill",
                            isSelected: selectedCourse == nil
                        ) {
                            withAnimation(EPTheme.spring) {
                                selectedCourse = nil
                            }
                        }

                        ForEach(availableCourses, id: \.self) { course in
                            filterChip(
                                title: course,
                                icon: "person.3.fill",
                                isSelected: selectedCourse == course
                            ) {
                                withAnimation(EPTheme.spring) {
                                    selectedCourse = course
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func filterChip(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark.circle.fill" : icon)
                .font(.caption.weight(.black))
                .foregroundStyle(isSelected ? .white : EPTheme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? EPTheme.primary : EPTheme.primary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Seleccionado" : "No seleccionado")
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
            EPKPIBox(
                title: "Unidades",
                value: "\(visibleUnitCount)",
                subtitle: selectedCourse ?? selectedSubject,
                icon: "square.stack.3d.up.fill",
                tint: EPTheme.primary
            )
            EPKPIBox(
                title: "Clases",
                value: "\(visibleClassCount)",
                subtitle: "en cronogramas",
                icon: "rectangle.stack.fill",
                tint: .blue
            )
            EPKPIBox(
                title: "Por iniciar",
                value: "\(unitsWithoutCronograma)",
                subtitle: "sin cronograma",
                icon: "square.and.pencil",
                tint: unitsWithoutCronograma == 0 ? .green : .orange
            )
        }
    }

    private func courseSection(_ plan: PlanificacionCurso) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(EPTheme.primary.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(EPTheme.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.curso)
                        .font(.system(size: 16, weight: .black))
                    Text("\(plan.asignatura) · \(plan.units.count) unidad\(plan.units.count == 1 ? "" : "es")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(plan.units) { unit in
                unitLink(unit, plan: plan)
            }
        }
    }

    private func unitLink(_ unit: UnidadPlan, plan: PlanificacionCurso) -> some View {
        let cronograma = cronograma(for: unit, plan: plan)
        let totalClasses = cronograma.map { numberOfClasses(in: $0) } ?? 0
        let datedClasses = cronograma?.clases.filter {
            !$0.fecha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count ?? 0
        let routeID = UnitRouteID.routeId(
            for: unit,
            asignatura: plan.asignatura,
            course: plan.curso,
            cronogramasByUnit: viewModel.cronogramasByUnit
        )
        let tint = unit.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? EPTheme.primary
            : EPTheme.color(hex: unit.color)

        return NavigationLink(value: AppRoute.verUnidad(
            curso: plan.curso,
            asignatura: plan.asignatura,
            unidadId: routeID,
            unidadNombre: unit.name,
            initialTab: "clases"
        )) {
            EPWebCard(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .frame(width: 46, height: 46)
                        Image(systemName: totalClasses > 0 ? "text.book.closed.fill" : "square.and.pencil")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(tint)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(unit.name)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(EPTheme.ink)
                                .multilineTextAlignment(.leading)
                            if unit.hasDates {
                                Text("\(PlanDateParser.short(unit.start)) – \(PlanDateParser.short(unit.end))")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ReplicaFlowLayout(spacing: 6) {
                            EPStatusPill(
                                text: totalClasses > 0 ? "\(totalClasses) clases" : "Crear clases",
                                icon: totalClasses > 0 ? "rectangle.stack.fill" : "plus.circle.fill",
                                tint: totalClasses > 0 ? .blue : .orange
                            )
                            if totalClasses > 0 {
                                EPStatusPill(
                                    text: "\(datedClasses)/\(totalClasses) con fecha",
                                    icon: "calendar",
                                    tint: datedClasses == totalClasses ? .green : .secondary
                                )
                            }
                            if unit.hours > 0 {
                                EPStatusPill(text: "\(unit.hours) h", icon: "clock.fill", tint: .purple)
                            }
                        }
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 14)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir clases de \(unit.name), \(plan.curso)")
        .accessibilityHint(totalClasses > 0 ? "Tiene \(totalClasses) clases en el cronograma" : "Permite crear la planificación de sus clases")
    }

    private var emptyActivitiesState: some View {
        EPWebCard {
            VStack(spacing: 12) {
                EPEmptyState(
                    icon: searchQuery.isEmpty ? "lightbulb.slash.fill" : "magnifyingglass",
                    title: searchQuery.isEmpty ? "Sin unidades para esta selección" : "Sin resultados",
                    message: searchQuery.isEmpty
                        ? "Primero crea una planificación de curso con sus unidades; luego podrás trabajar cada clase aquí."
                        : "Prueba con otro nombre, curso o asignatura."
                )

                if searchQuery.isEmpty {
                    NavigationLink(value: AppRoute.module(.planificaciones)) {
                        Label("Ir a Planificar", systemImage: "book.closed.fill")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EPTheme.primary)
                } else {
                    Button("Limpiar búsqueda") {
                        searchQuery = ""
                    }
                    .font(.subheadline.weight(.black))
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var plansUnavailableState: some View {
        EPWebCard {
            VStack(spacing: 12) {
                EPEmptyState(
                    icon: "exclamationmark.icloud.fill",
                    title: "No se pudieron recuperar las unidades",
                    message: "No mostraremos una lista vacía porque puede haber planificaciones web que aún no se han podido leer."
                )

                Button {
                    Task {
                        await viewModel.refresh()
                        normalizeSelection()
                    }
                } label: {
                    Label("Reintentar carga", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(viewModel.isLoading)
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("No se cargó toda la información")
                    .font(.subheadline.weight(.black))
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    await viewModel.refresh()
                    normalizeSelection()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.callout.weight(.bold))
                    .padding(8)
                    .background(Color(.systemGray6), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Reintentar carga de actividades")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Datos derivados

    private var availableSubjects: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in viewModel.availableSubjects + viewModel.planes.map(\.asignatura) {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = subjectKey(clean)
            guard !clean.isEmpty, seen.insert(key).inserted else { continue }
            result.append(clean)
        }
        return result
    }

    private var selectedSubject: String {
        let current = viewModel.selectedSubject ?? viewModel.activeSubject
        if availableSubjects.contains(where: { subjectKey($0) == subjectKey(current) }) {
            return current
        }
        return availableSubjects.first ?? current
    }

    private var availableCourses: [String] {
        uniqueSorted(
            viewModel.planes
                .filter { subjectKey($0.asignatura) == subjectKey(selectedSubject) }
                .map(\.curso)
        )
    }

    private var filteredPlans: [PlanificacionCurso] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.planes.compactMap { plan in
            guard subjectKey(plan.asignatura) == subjectKey(selectedSubject) else { return nil }
            if let selectedCourse, plan.curso != selectedCourse { return nil }

            var filtered = plan
            filtered.units = plan.units.filter { unit in
                query.isEmpty ||
                unit.name.localizedCaseInsensitiveContains(query) ||
                plan.curso.localizedCaseInsensitiveContains(query) ||
                plan.asignatura.localizedCaseInsensitiveContains(query)
            }
            return filtered.units.isEmpty ? nil : filtered
        }
        .sorted {
            if $0.curso == $1.curso {
                return $0.asignatura.localizedCaseInsensitiveCompare($1.asignatura) == .orderedAscending
            }
            return $0.curso.localizedStandardCompare($1.curso) == .orderedAscending
        }
    }

    private var visibleUnitCount: Int {
        filteredPlans.reduce(0) { $0 + $1.units.count }
    }

    private var visibleClassCount: Int {
        filteredPlans.reduce(0) { partial, plan in
            partial + plan.units.reduce(0) { count, unit in
                count + (cronograma(for: unit, plan: plan).map { numberOfClasses(in: $0) } ?? 0)
            }
        }
    }

    private var unitsWithoutCronograma: Int {
        filteredPlans.reduce(0) { partial, plan in
            partial + plan.units.filter { cronograma(for: $0, plan: plan) == nil }.count
        }
    }

    private func cronograma(for unit: UnidadPlan, plan: PlanificacionCurso) -> CronogramaUnidadData? {
        let canonicalID = String(unit.id)
        let subjectKey = PlanificacionRepository.cronogramaKey(
            asignatura: plan.asignatura,
            curso: plan.curso,
            unidadId: canonicalID
        )
        let legacyKey = PlanificacionRepository.cronogramaKey(curso: plan.curso, unidadId: canonicalID)
        return viewModel.cronogramasByUnit[subjectKey] ?? viewModel.cronogramasByUnit[legacyKey]
    }

    private func numberOfClasses(in cronograma: CronogramaUnidadData) -> Int {
        max(cronograma.totalClases, cronograma.clases.map(\.numero).max() ?? cronograma.clases.count)
    }

    private func normalizeSelection() {
        if !availableSubjects.contains(where: { subjectKey($0) == subjectKey(selectedSubject) }),
           let first = availableSubjects.first {
            viewModel.selectedSubject = first
        } else if !viewModel.planes.contains(where: {
            subjectKey($0.asignatura) == subjectKey(selectedSubject) && !$0.units.isEmpty
        }), let firstWithUnits = availableSubjects.first(where: { subject in
            viewModel.planes.contains {
                subjectKey($0.asignatura) == subjectKey(subject) && !$0.units.isEmpty
            }
        }) {
            viewModel.selectedSubject = firstWithUnits
        }
        normalizeSelectedCourse()
    }

    private func normalizeSelectedCourse() {
        if let selectedCourse, !availableCourses.contains(selectedCourse) {
            self.selectedCourse = nil
        }
    }

    private func subjectKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
