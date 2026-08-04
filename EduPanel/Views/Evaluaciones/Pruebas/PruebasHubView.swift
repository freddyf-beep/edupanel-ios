import SwiftUI
import UIKit
import FirebaseAuth
import ImageIO

struct PruebasHubView: View {
    @Bindable var viewModel: EvaluacionesViewModel

    @State private var searchQuery = ""
    @State private var activeFilter: PruebaHubFilter = .todas
    @State private var selectedUnitId: String?
    @State private var testToDelete: PruebaTemplate?
    @State private var testToDuplicate: PruebaTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.pruebasDesdeCache {
                infoBanner(
                    icon: "icloud.slash.fill",
                    title: "Mostrando datos disponibles sin conexión",
                    message: "El contenido puede no incluir los últimos cambios de EduPanel web.",
                    tint: .orange
                )
            }

            if viewModel.pruebasConAdvertencias > 0 {
                infoBanner(
                    icon: "exclamationmark.triangle.fill",
                    title: "Contenido web preservado",
                    message: "\(viewModel.pruebasConAdvertencias) prueba(s) contienen campos o tipos que iOS muestra sin modificar.",
                    tint: .orange
                )
            }

            metricsGrid
            PruebasUpcomingCard()
            filtersCard

            if viewModel.isLoadingExamForge {
                EvaluacionesLoadingCard(texto: "Consultando el nuevo motor...")
            } else if let error = viewModel.examForgeErrorMessage {
                ExamForgeEngineErrorCard(message: error) {
                    Task { await viewModel.refreshExamForge() }
                }
            } else if !filteredExamForgeTests.isEmpty {
                ExamForgeDocumentsSection(
                    title: "Pruebas del nuevo motor",
                    subtitle: "Formato ExamForge · lectura compatible en iPhone",
                    documents: filteredExamForgeTests,
                    schoolID: viewModel.evaluacionScope.colegioId
                )
            }

            if viewModel.isLoadingContenido {
                EvaluacionesLoadingCard(texto: "Cargando pruebas...")
            } else if let error = viewModel.pruebasErrorMessage {
                EvaluacionesRetryCard(
                    title: "No se pudieron cargar las pruebas",
                    message: error,
                    isLoading: viewModel.isLoadingContenido
                ) {
                    Task { await viewModel.loadContenido() }
                }
            } else if viewModel.pruebas.isEmpty && examForgeTestsForCourse.isEmpty {
                emptyState
            } else if filteredTests.isEmpty && filteredExamForgeTests.isEmpty
                        && !(viewModel.pruebas.isEmpty && examForgeTestsForCourse.isEmpty) {
                filteredEmptyState
            } else if !filteredTests.isEmpty {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedTests) { group in
                        testGroup(group)
                    }
                }
            }
        }
        .confirmationDialog(
            "\u{00BF}Eliminar esta prueba?",
            isPresented: Binding(get: { testToDelete != nil }, set: { if !$0 { testToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let test = testToDelete { Task { await viewModel.eliminarPrueba(test) } }
                testToDelete = nil
            }
            Button("Cancelar", role: .cancel) { testToDelete = nil }
        } message: {
            Text("Se eliminar\u{00E1} la prueba y su aplicaci\u{00F3}n del colegio activo. Esta acci\u{00F3}n no se puede deshacer.")
        }
        .confirmationDialog(
            "Duplicar prueba en...",
            isPresented: Binding(get: { testToDuplicate != nil }, set: { if !$0 { testToDuplicate = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(viewModel.cursos, id: \.self) { course in
                Button(course) {
                    if let test = testToDuplicate { Task { await viewModel.duplicarPrueba(test, cursoDestino: course) } }
                    testToDuplicate = nil
                }
            }
            Button("Cancelar", role: .cancel) { testToDuplicate = nil }
        }
        .onChange(of: viewModel.selectedCurso) { _, _ in selectedUnitId = nil }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            EPSectionHeader(
                title: "Pruebas",
                subtitle: "Sumativas, formativas y diagnósticas sincronizadas con EduPanel web.",
                icon: "doc.text.fill"
            )
            Spacer(minLength: 4)
            NavigationLink(value: AppRoute.pruebaEditor(
                pruebaId: nil,
                curso: viewModel.selectedCurso,
                asignatura: viewModel.activeSubject,
                scope: viewModel.evaluacionScope
            )) {
                Label("Nueva prueba", systemImage: "plus")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(EPTheme.rose, in: Capsule())
            }
            .disabled(viewModel.selectedCurso.isEmpty)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 9)], spacing: 9) {
            EPKPIBox(
                title: "Total",
                value: "\(viewModel.pruebas.count + examForgeTestsForCourse.count)",
                subtitle: viewModel.selectedCurso,
                icon: "doc.text.fill",
                tint: EPTheme.rose
            )
            EPKPIBox(
                title: "Listas",
                value: "\(viewModel.pruebas.filter { $0.estado == "lista" }.count + examForgeTestsForCourse.filter { $0.status == .ready }.count)",
                subtitle: "para aplicar",
                icon: "checkmark.seal.fill",
                tint: .green
            )
            EPKPIBox(
                title: "Borradores",
                value: "\(viewModel.pruebas.filter { $0.estado.isEmpty || $0.estado == "borrador" }.count + examForgeTestsForCourse.filter { $0.status == .draft }.count)",
                subtitle: "en preparación",
                icon: "pencil.and.outline",
                tint: .orange
            )
            EPKPIBox(
                title: "Con OA",
                value: "\(viewModel.pruebas.filter { !$0.metadatosCurriculares.objetivos.isEmpty }.count + examForgeTestsForCourse.filter { $0.metadata.objectivesCount > 0 }.count)",
                subtitle: "vinculadas",
                icon: "link.circle.fill",
                tint: .blue
            )
        }
    }

    private var filtersCard: some View {
        EPWebCard(padding: 12) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Buscar prueba, unidad u OA", text: $searchQuery)
                        .font(.system(size: 13, weight: .semibold))
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Limpiar búsqueda")
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(PruebaHubFilter.allCases) { filter in
                            Button {
                                withAnimation(EPTheme.spring) {
                                    activeFilter = filter
                                }
                            } label: {
                                Text(filter.label)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(activeFilter == filter ? .white : filter.tint)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(
                                        activeFilter == filter ? filter.tint : filter.tint.opacity(0.11),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(activeFilter == filter ? "Seleccionado" : "")
                        }
                    }
                    .padding(.vertical, 1)
                }

                if !availableUnits.isEmpty {
                    Menu {
                        Button("Todas las unidades") {
                            selectedUnitId = nil
                        }
                        ForEach(availableUnits) { unit in
                            Button {
                                selectedUnitId = unit.id
                            } label: {
                                if selectedUnitId == unit.id {
                                    Label(unit.name, systemImage: "checkmark")
                                } else {
                                    Text(unit.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "square.stack.3d.up.fill")
                            Text(selectedUnitName ?? "Todas las unidades")
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .font(.caption.weight(.black))
                        .foregroundStyle(EPTheme.rose)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(EPTheme.rose.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
            }
        }
    }

    private func testGroup(_ group: PruebaSubjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.subject.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.tests.count) \(group.tests.count == 1 ? "prueba" : "pruebas")")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)

            ForEach(group.tests) { test in
                PruebaCardView(
                    test: test,
                    onDuplicate: { testToDuplicate = test },
                    onDelete: { testToDelete = test }
                )
            }
        }
    }

    private var emptyState: some View {
        EPWebCard {
            EPEmptyState(
                icon: "doc.text",
                title: "Aún no hay pruebas para \(viewModel.selectedCurso)",
                message: "Crea una prueba nativa o abre aquí las que ya existen en EduPanel web."
            )
        }
    }

    private var filteredEmptyState: some View {
        EPWebCard {
            VStack(spacing: 10) {
                EPEmptyState(
                    icon: "magnifyingglass",
                    title: "No hay pruebas que coincidan",
                    message: "Ajusta la búsqueda, el tipo o la unidad seleccionada."
                )
                Button("Limpiar filtros") {
                    searchQuery = ""
                    activeFilter = .todas
                    selectedUnitId = nil
                }
                .font(.footnote.weight(.black))
                .buttonStyle(.bordered)
                .tint(EPTheme.rose)
            }
        }
    }

    private func infoBanner(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.black))
                Text(message)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Filtros

    private var filteredTests: [PruebaTemplate] {
        let query = normalized(searchQuery)
        return viewModel.pruebas.filter { test in
            if let selectedUnitId, test.unidadId != selectedUnitId { return false }
            guard activeFilter.matches(test) else { return false }
            guard !query.isEmpty else { return true }
            let haystack = [
                test.nombre,
                test.asignatura,
                test.curso,
                test.unidadNombre ?? "",
                test.metadatosCurriculares.objetivos.joined(separator: " ")
            ].joined(separator: " ")
            return normalized(haystack).contains(query)
        }
    }

    private var examForgeTestsForCourse: [ExamForgeExamSummary] {
        viewModel.examForgeTests.filter {
            $0.matches(courseID: viewModel.selectedCourseID, courseName: viewModel.selectedCurso)
                && $0.matches(subjectID: viewModel.selectedSubjectID, subjectName: viewModel.activeSubject)
        }
    }

    private var filteredExamForgeTests: [ExamForgeExamSummary] {
        let query = normalized(searchQuery)
        return examForgeTestsForCourse.filter { document in
            if let selectedUnitId,
               !document.matches(unitID: selectedUnitId, unitName: selectedUnitName) { return false }
            guard activeFilter.matches(document) else { return false }
            guard !query.isEmpty else { return true }
            return normalized(document.searchableText).contains(query)
        }
    }

    private var groupedTests: [PruebaSubjectGroup] {
        Dictionary(grouping: filteredTests) { test in
            test.asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Sin asignatura"
                : test.asignatura
        }
        .map { subject, tests in
            PruebaSubjectGroup(subject: subject, tests: tests)
        }
        .sorted { $0.subject.localizedCaseInsensitiveCompare($1.subject) == .orderedAscending }
    }

    private var availableUnits: [PruebaUnitFilter] {
        var seen = Set<String>()
        var units: [PruebaUnitFilter] = viewModel.pruebas.compactMap { test -> PruebaUnitFilter? in
            guard let id = test.unidadId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  seen.insert(id).inserted else { return nil }
            let name = test.unidadNombre?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PruebaUnitFilter(id: id, name: name?.isEmpty == false ? name! : id)
        }
        for document in examForgeTestsForCourse {
            guard let integration = document.integration,
                  let id = integration.unitId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  seen.insert(id).inserted else { continue }
            let name = integration.unitLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            units.append(PruebaUnitFilter(id: id, name: name.isEmpty ? id : name))
        }
        return units
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedUnitName: String? {
        availableUnits.first { $0.id == selectedUnitId }?.name
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PruebaCardView: View {
    let test: PruebaTemplate
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationLink(value: AppRoute.pruebaDetalle(pruebaId: test.id, scope: test.scope)) {
            EPWebCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(EPTheme.rose)
                            .frame(width: 38, height: 38)
                            .background(EPTheme.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            ReplicaFlowLayout(spacing: 6) {
                                EPStatusPill(text: test.typeLabel, tint: EPTheme.rose)
                                EPStatusPill(text: test.stateLabel, tint: test.stateTint)
                                if test.tieneContenidoDesconocido || !test.issues.isEmpty {
                                    EPStatusPill(text: "Compatibilidad", icon: "exclamationmark.triangle.fill", tint: .orange)
                                }
                            }
                            Text(test.nombre.isEmpty ? "Sin nombre" : test.nombre)
                                .font(.system(size: 15.5, weight: .black))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text([test.asignatura, test.curso, test.unidadNombre ?? ""]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 12)
                    }

                    HStack(spacing: 12) {
                        miniStat("Secs", value: "\(test.secciones.count)")
                        miniStat("Ítems", value: "\(test.totalItems)")
                        miniStat("Pts", value: test.puntajeMaximo.formatted(.number.precision(.fractionLength(0...1))))
                        if let minutes = test.tiempoMinutos {
                            miniStat("Min", value: "\(minutes)")
                        }
                        Spacer(minLength: 0)
                    }

                    if let date = test.fechaActualizacion ?? test.fechaCreacion {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Menu {
                NavigationLink(value: AppRoute.pruebaResultados(pruebaId: test.id, scope: test.scope)) {
                    Label(test.isApplied ? "Corregir / resultados" : "Aplicar", systemImage: "checkmark.rectangle.stack")
                }
                NavigationLink(value: AppRoute.pruebaEditor(
                    pruebaId: test.id,
                    curso: test.curso,
                    asignatura: test.asignatura,
                    scope: test.scope
                )) {
                    Label("Editar", systemImage: "pencil")
                }
                Button("Duplicar", systemImage: "doc.on.doc", action: onDuplicate)
                Button("Eliminar", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(12)
        }
        .accessibilityLabel("Ver detalle de \(test.nombre.isEmpty ? "prueba sin nombre" : test.nombre)")
    }

    private func miniStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

private enum PruebaHubFilter: String, CaseIterable, Identifiable {
    case todas
    case sumativa
    case formativa
    case diagnostica
    case borrador

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todas: return "Todas"
        case .sumativa: return "Sumativas"
        case .formativa: return "Formativas"
        case .diagnostica: return "Diagnósticas"
        case .borrador: return "Borradores"
        }
    }

    var tint: Color {
        switch self {
        case .todas: return EPTheme.rose
        case .sumativa: return .green
        case .formativa: return .blue
        case .diagnostica: return .orange
        case .borrador: return .gray
        }
    }

    func matches(_ test: PruebaTemplate) -> Bool {
        switch self {
        case .todas: return true
        case .sumativa, .formativa, .diagnostica: return test.tipoEvaluacion == rawValue
        case .borrador: return test.estado.isEmpty || test.estado == "borrador"
        }
    }

    func matches(_ document: ExamForgeExamSummary) -> Bool {
        switch self {
        case .todas: return true
        case .sumativa, .formativa, .diagnostica:
            return document.integration?.evaluationType == rawValue
        case .borrador:
            return document.status == .draft
        }
    }
}

extension ExamForgeExamSummary {
    func matches(courseID: String?, courseName: String) -> Bool {
        guard let integration else { return true }
        let expected = [courseID, courseName]
            .compactMap { $0 }
            .map(Self.normalizedContextValue)
            .filter { !$0.isEmpty }
        guard !expected.isEmpty else { return false }
        let candidates = [integration.courseId, integration.courseLabel]
            .compactMap { $0 }
            .map(Self.normalizedContextValue)
            .filter { !$0.isEmpty }
        return candidates.contains { candidate in
            expected.contains(candidate) || expected.contains { value in
                candidate.count >= 4 && value.count >= 4 && (candidate.contains(value) || value.contains(candidate))
            }
        }
    }

    var searchableText: String {
        [
            title,
            integration?.courseLabel,
            integration?.subjectLabel,
            integration?.unitLabel,
            integration?.evaluationType,
            integration?.guideType,
            metadata.objectiveIds?.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    func matches(unitID: String, unitName: String?) -> Bool {
        guard let integration else { return false }
        let expected = [unitID, unitName].compactMap { $0 }.flatMap(Self.unitAliases)
        let candidates = [integration.unitId, integration.unitLabel].compactMap { $0 }.flatMap(Self.unitAliases)
        return !Set(expected).isDisjoint(with: candidates)
    }

    func matches(subjectID: String?, subjectName: String) -> Bool {
        guard let integration else { return true }
        let expected = [subjectID, subjectName]
            .compactMap { $0 }
            .map(Self.normalizedContextValue)
            .filter { !$0.isEmpty }
        guard !expected.isEmpty else { return false }

        let candidates = [integration.subjectId, integration.subjectLabel]
            .compactMap { $0 }
            .map(Self.normalizedContextValue)
            .filter { !$0.isEmpty }
        // Los primeros documentos no siempre tenían asignatura. Se mantienen
        // visibles; cuando sí existe contexto, debe coincidir con el selector.
        guard !candidates.isEmpty else { return true }
        return candidates.contains { candidate in
            expected.contains(candidate) || expected.contains { value in
                candidate.count >= 4 && value.count >= 4 && (candidate.contains(value) || value.contains(candidate))
            }
        }
    }

    var contextLine: String {
        [integration?.subjectLabel, integration?.courseLabel, integration?.unitLabel]
            .compactMap { value in
                let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return clean.isEmpty ? nil : clean
            }
            .joined(separator: " · ")
    }

    private static func normalizedContextValue(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func unitAliases(_ value: String) -> [String] {
        let normalized = normalizedContextValue(value)
        guard !normalized.isEmpty else { return [] }
        var aliases = [normalized]
        if normalized.allSatisfy(\.isNumber) { aliases.append("unidad\(normalized)") }
        if normalized.hasPrefix("unidad") {
            let suffix = String(normalized.dropFirst("unidad".count))
            if !suffix.isEmpty { aliases.append(suffix) }
        }
        return aliases
    }
}

struct ExamForgeEngineErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        EPWebCard(padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nuevo motor no disponible")
                        .font(.caption.weight(.black))
                    Text(message)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Reintentar", action: retry)
                    .font(.caption.weight(.black))
                    .buttonStyle(.bordered)
                    .tint(.orange)
            }
        }
    }
}

struct ExamForgeDocumentsSection: View {
    let title: String
    let subtitle: String
    let documents: [ExamForgeExamSummary]
    let schoolID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EPSectionHeader(title: title, subtitle: subtitle, icon: "sparkles.rectangle.stack.fill")
            ForEach(documents) { document in
                ExamForgeSummaryCard(document: document, schoolID: schoolID)
            }
        }
    }
}

private struct ExamForgeSummaryCard: View {
    let document: ExamForgeExamSummary
    let schoolID: String?

    private var tint: Color { document.kind == .guia ? .purple : EPTheme.rose }

    var body: some View {
        NavigationLink(value: AppRoute.examForgeDocument(id: document.id, kind: document.kind, schoolID: schoolID)) {
            EPWebCard(padding: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: document.kind == .guia ? "book.pages.fill" : "doc.text.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(tint)
                            .frame(width: 38, height: 38)
                            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            ReplicaFlowLayout(spacing: 6) {
                                EPStatusPill(text: "Nuevo formato", icon: "sparkles", tint: tint)
                                EPStatusPill(text: document.status.label, tint: document.status == .ready ? .green : .orange)
                            }
                            Text(document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Documento sin título" : document.title)
                                .font(.system(size: 15.5, weight: .black))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if !document.contextLine.isEmpty {
                                Text(document.contextLine)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 13) {
                        Label("\(document.metadata.objectivesCount) OA", systemImage: "target")
                        if let points = document.metadata.totalPoints {
                            Label(points.formatted(.number.precision(.fractionLength(0...1))) + " pts", systemImage: "star.fill")
                        }
                        if let minutes = document.metadata.durationMinutes {
                            Label("\(minutes) min", systemImage: "clock")
                        }
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir \(document.kind == .guia ? "guía" : "prueba") \(document.title)")
    }
}

private struct PruebaSubjectGroup: Identifiable {
    let subject: String
    let tests: [PruebaTemplate]
    var id: String { subject }
}

private struct PruebaUnitFilter: Identifiable {
    let id: String
    let name: String
}

private extension PruebaTemplate {
    var typeLabel: String {
        switch tipoEvaluacion {
        case "formativa": return "Formativa"
        case "diagnostica": return "Diagnóstica"
        case "sumativa", "": return "Sumativa"
        default: return tipoEvaluacion.capitalized
        }
    }

    var stateLabel: String {
        switch estado {
        case "lista": return "Lista"
        case "aplicada": return "Aplicada"
        case "archivada": return "Archivada"
        case "borrador", "": return "Borrador"
        default: return estado.capitalized
        }
    }

    var stateTint: Color {
        switch estado {
        case "lista": return .green
        case "aplicada": return .blue
        case "archivada": return .gray
        default: return .orange
        }
    }
}

// MARK: - Lectura de documentos ExamForge

struct ExamForgeDocumentDetailView: View {
    let documentID: String
    let expectedKind: ExamForgeDocumentKind
    let schoolID: String?
    let repository: ExamForgeRepository

    @State private var document: ExamForgeExamRecord?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reloadToken = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                if isLoading && document == nil {
                    EvaluacionesLoadingCard(texto: "Abriendo documento...")
                } else if let errorMessage, document == nil {
                    EvaluacionesRetryCard(
                        title: "No se pudo abrir el documento",
                        message: errorMessage,
                        isLoading: isLoading
                    ) {
                        reloadToken += 1
                    }
                } else if let document {
                    detailContent(document)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .tabBarPageBottomPadding()
        }
        .reportsTabBarScroll()
        .background(EPTheme.background)
        .navigationTitle(expectedKind == .guia ? "Guía" : "Prueba")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await load() }
    }

    @ViewBuilder
    private func detailContent(_ record: ExamForgeExamRecord) -> some View {
        let metadata = record.document.metadata
        EPPageHeader(
            eyebrow: expectedKind == .guia ? "Guía · nuevo formato" : "Prueba · nuevo formato",
            title: metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.title : metadata.title,
            subtitle: [metadata.subject, metadata.course].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
            icon: expectedKind == .guia ? "book.pages.fill" : "doc.text.fill"
        )

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vista de lectura")
                    .font(.caption.weight(.black))
                Text("Puedes revisar este documento del nuevo motor. La edición y exportación continúan en EduPanel web mientras el formato termina de estabilizarse.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        ExamForgeMetadataCard(metadata: metadata, status: record.status, schemaVersion: record.schemaVersion)

        let instructions = metadata.instructions.richPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            EPWebCard {
                VStack(alignment: .leading, spacing: 8) {
                    EPSectionHeader(title: "Instrucciones", subtitle: "Indicaciones generales del documento", icon: "list.bullet.clipboard.fill")
                    Text(instructions)
                        .font(.subheadline)
                        .lineSpacing(3)
                }
            }
        }

        if !metadata.objectives.isEmpty {
            EPWebCard {
                VStack(alignment: .leading, spacing: 9) {
                    EPSectionHeader(title: "Objetivos vinculados", subtitle: "\(metadata.objectives.count) objetivos", icon: "target")
                    ForEach(metadata.objectives) { objective in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                            Text(objective.text)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }

        let regions = record.document.regions
        let headerBlocks = regions.header.enabled == false ? [] : regions.header.blocks
        let bodyBlocks = regions.body.blocks
        let footerBlocks = regions.footer.enabled == false ? [] : regions.footer.blocks
        if headerBlocks.isEmpty && bodyBlocks.isEmpty && footerBlocks.isEmpty {
            EPWebCard {
                EPEmptyState(
                    icon: "doc.text",
                    title: "Documento sin contenido",
                    message: "El nuevo motor todavía no tiene bloques para mostrar."
                )
            }
        } else {
            regionSection(title: "Encabezado", icon: "rectangle.topthird.inset.filled", blocks: headerBlocks)
            regionSection(title: "Contenido", icon: "rectangle.3.group.fill", blocks: bodyBlocks)
            regionSection(title: "Pie de página", icon: "rectangle.bottomthird.inset.filled", blocks: footerBlocks)
        }
    }

    @ViewBuilder
    private func regionSection(title: String, icon: String, blocks: [ExamForgeBlock]) -> some View {
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(title: title, subtitle: "\(blocks.count) bloques en orden", icon: icon)
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    let questionPosition = blocks.prefix(index + 1).filter { $0.type == "question" }.count
                    ExamForgeBlockView(
                        block: block,
                        position: block.type == "question" ? max(questionPosition, 1) : index + 1,
                        schoolID: schoolID,
                        repository: repository
                    )
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            document = try await repository.loadDocument(id: documentID, schoolID: schoolID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExamForgeMetadataCard: View {
    let metadata: ExamForgeDocumentMetadata
    let status: ExamForgeStatus
    let schemaVersion: String

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 11) {
                ReplicaFlowLayout(spacing: 7) {
                    EPStatusPill(text: status.label, tint: status == .ready ? .green : .orange)
                    EPStatusPill(text: "Esquema \(schemaVersion)", icon: "checkmark.shield.fill", tint: .blue)
                }

                if let subtitle = clean(metadata.subtitle) {
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                }

                ReplicaFlowLayout(spacing: 8) {
                    if let teacher = clean(metadata.teacher) { Label(teacher, systemImage: "person.fill") }
                    if let date = clean(metadata.date) { Label(date, systemImage: "calendar") }
                    if let minutes = metadata.durationMinutes { Label("\(minutes) min", systemImage: "clock") }
                    if let points = metadata.totalPoints {
                        Label(points.formatted(.number.precision(.fractionLength(0...1))) + " pts", systemImage: "star.fill")
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func clean(_ value: String?) -> String? {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? nil : clean
    }
}

private struct ExamForgeBlockView: View {
    let block: ExamForgeBlock
    let position: Int
    let schoolID: String?
    let repository: ExamForgeRepository

    var body: some View {
        switch block.type {
        case "text":
            readableCard(title: "Texto", icon: "text.alignleft", text: block.richText("content"))
        case "section":
            sectionCard
        case "question":
            questionCard
        case "image":
            imageCard
        case "separator":
            Divider().padding(.vertical, 5).accessibilityHidden(true)
        case "answer-space":
            answerSpaceCard
        case "page-break":
            Label("Salto de página", systemImage: "arrow.down.to.line.compact")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case "header":
            headerCard
        case "footer":
            footerCard
        default:
            unsupportedCard
        }
    }

    private var sectionCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sección", systemImage: "rectangle.3.group.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.purple)
                Text(block.richText("title").nonEmpty ?? "Sección sin título")
                    .font(.headline.weight(.black))
                if let instructions = block.richText("instructions").nonEmpty {
                    Text(instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var questionCard: some View {
        let prompt = block.richText("prompt")
        let points = block.number("points")
        let type = block.string("questionType") ?? "question"
        let answer = block.object("answer")
        let numbering = block.object("numbering")
        let fixedNumber = numbering?["mode"]?.stringValue == "fixed" ? numbering?["value"]?.numberValue.flatMap(Int.init(exactly:)) : nil
        let questionNumber = fixedNumber ?? position

        return EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    EPStatusPill(text: "Pregunta \(questionNumber)", icon: "questionmark.circle.fill", tint: EPTheme.rose)
                    EPStatusPill(text: questionTypeLabel(type), tint: .blue)
                    Spacer(minLength: 4)
                    if let points {
                        Text(points.formatted(.number.precision(.fractionLength(0...1))) + " pts")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(prompt.nonEmpty ?? "Pregunta sin enunciado")
                    .font(.subheadline.weight(.semibold))
                    .lineSpacing(3)

                if let options = answer?["options"]?.arrayValue, !options.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            let optionData = option.objectValue ?? [:]
                            let text = optionData["content"]?.richPlainText.nonEmpty ?? "Opción \(index + 1)"
                            let isCorrect = optionData["isCorrect"]?.boolValue == true
                            HStack(alignment: .top, spacing: 8) {
                                Text(optionLabel(for: index, style: answer?["optionLabelStyle"]?.stringValue))
                                    .font(.caption.weight(.black))
                                    .frame(width: 24, height: 24)
                                    .background((isCorrect ? Color.green : Color.secondary).opacity(0.12), in: Circle())
                                Text(text).font(.subheadline)
                                Spacer(minLength: 4)
                                if isCorrect {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        .accessibilityLabel("Respuesta correcta")
                                }
                            }
                        }
                    }
                } else if let correct = answer?["correctAnswer"]?.boolValue {
                    Label(correct ? "Respuesta: Verdadero" : "Respuesta: Falso", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)

                    if let justification = answer?["justification"]?.richPlainText.nonEmpty {
                        responseSection(title: "Justificación", text: justification)
                    }
                } else if let accepted = answer?["acceptedAnswers"]?.arrayValue {
                    let values = accepted.compactMap(\.stringValue)
                    if !values.isEmpty {
                        Text("Respuestas aceptadas: \(values.joined(separator: ", "))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    responseLines(answer?["lines"]?.numberValue)
                } else if type == "essay" {
                    if let rubric = answer?["rubric"]?.richPlainText.nonEmpty {
                        responseSection(title: "Rúbrica", text: rubric)
                    }
                    responseLines(answer?["lines"]?.numberValue)
                }
            }
        }
    }

    @ViewBuilder
    private func responseSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.black)).foregroundStyle(.secondary)
            Text(text).font(.subheadline).lineSpacing(3)
        }
    }

    @ViewBuilder
    private func responseLines(_ rawLines: Double?) -> some View {
        if let rawLines, let lines = Int(exactly: rawLines), lines > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Espacio de respuesta · \(lines) líneas")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                ForEach(0..<min(lines, 8), id: \.self) { _ in Divider() }
                if lines > 8 {
                    Text("+ \(lines - 8) líneas en el documento")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func optionLabel(for index: Int, style: String?) -> String {
        switch style {
        case "lowercase-letter":
            return UnicodeScalar(97 + index).map(String.init) ?? String(index + 1)
        case "number":
            return String(index + 1)
        default:
            return UnicodeScalar(65 + index).map(String.init) ?? String(index + 1)
        }
    }

    private var headerCard: some View {
        let schoolName = block.string("schoolName")?.nonEmpty
        let logoAssetID = block.string("logoAssetId")?.nonEmpty
        let showStudentFields = block.fields["showStudentFields"]?.boolValue == true
        return EPWebCard {
            VStack(alignment: .leading, spacing: 9) {
                Label("Encabezado", systemImage: "building.columns.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.blue)
                if let schoolName { Text(schoolName).font(.headline.weight(.bold)) }
                if let logoAssetID {
                    ExamForgeAssetView(assetID: logoAssetID, alt: "Logo del establecimiento", schoolID: schoolID, repository: repository)
                }
                if showStudentFields {
                    Text("Nombre: ____________________   Curso: __________   Fecha: __________")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Campos para nombre, curso y fecha del estudiante")
                }
                if schoolName == nil && logoAssetID == nil && !showStudentFields {
                    Text("Encabezado sin elementos visibles").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footerCard: some View {
        let text = block.string("leftText")?.nonEmpty
        let showPageNumber = block.fields["showPageNumber"]?.boolValue == true
        return EPWebCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(text ?? "Pie de página", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                if showPageNumber {
                    Label("Número de página", systemImage: "number")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var imageCard: some View {
        let assetID = block.string("assetId") ?? ""
        let alt = block.string("alt")?.nonEmpty ?? "Imagen del documento"
        return EPWebCard {
            VStack(alignment: .leading, spacing: 9) {
                Label("Imagen", systemImage: "photo.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.blue)
                ExamForgeAssetView(assetID: assetID, alt: alt, schoolID: schoolID, repository: repository)
            }
        }
    }

    private var answerSpaceCard: some View {
        let lines = block.number("lines").flatMap { Int(exactly: $0) } ?? 1
        return EPWebCard {
            VStack(alignment: .leading, spacing: 7) {
                Label("Espacio de respuesta · \(max(lines, 1)) líneas", systemImage: "pencil.line")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                ForEach(0..<min(max(lines, 1), 8), id: \.self) { _ in Divider() }
            }
        }
    }

    private var unsupportedCard: some View {
        EPWebCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bloque “\(block.type)” preservado")
                        .font(.caption.weight(.black))
                    Text("Este bloque pertenece a una extensión nueva. Puedes verlo y editarlo en EduPanel web; iOS no lo modifica.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func readableCard(title: String, icon: String, text: String) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.blue)
                Text(text.nonEmpty ?? "Sin contenido legible")
                    .font(.subheadline)
                    .lineSpacing(3)
            }
        }
    }

    private func questionTypeLabel(_ type: String) -> String {
        switch type {
        case "multiple-choice": return "Alternativas"
        case "true-false": return "Verdadero/Falso"
        case "short-answer": return "Respuesta breve"
        case "essay": return "Desarrollo"
        default: return "Pregunta"
        }
    }
}

private struct ExamForgeAssetView: View {
    let assetID: String
    let alt: String
    let schoolID: String?
    let repository: ExamForgeRepository

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(alt)
            } else if isLoading {
                ProgressView("Cargando imagen...")
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(errorMessage ?? alt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task(id: assetID) { await load() }
    }

    private func load() async {
        guard !assetID.isEmpty else {
            errorMessage = "La imagen no tiene una referencia válida."
            return
        }
        let principalID = Auth.auth().currentUser?.uid ?? "sin-sesion"
        let cacheKey = [principalID, schoolID ?? "principal", assetID].joined(separator: "|")
        if let cached = ExamForgeImageCache.shared.image(for: cacheKey) {
            image = cached
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await repository.loadAsset(id: assetID, schoolID: schoolID)
            guard response.data.count <= 12_000_000,
                  response.mimeType?.lowercased().hasPrefix("image/") != false,
                  let decoded = Self.downsampledImage(from: response.data) else {
                throw APIClientError.invalidResponse
            }
            ExamForgeImageCache.shared.insert(decoded, for: cacheKey)
            image = decoded
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "No se pudo cargar esta imagen."
        }
    }

    /// ExamForge admite originales de alta resolución. La vista móvil conserva
    /// detalle suficiente para Retina sin decodificar decenas de megapíxeles.
    private static func downsampledImage(from data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }

        let pixelWidth = width.doubleValue
        let pixelHeight = height.doubleValue
        guard pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= 40_000, pixelHeight <= 40_000,
              pixelWidth * pixelHeight <= 40_000_000 else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image)
    }
}

@MainActor
private final class ExamForgeImageCache {
    static let shared = ExamForgeImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 30
        cache.totalCostLimit = 24_000_000
    }

    func image(for id: String) -> UIImage? { cache.object(forKey: id as NSString) }
    func insert(_ image: UIImage, for id: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: id as NSString, cost: cost)
    }
}

private extension ExamForgeBlock {
    var fields: [String: ExamForgeJSONValue] { data.objectValue ?? [:] }
    func string(_ key: String) -> String? { fields[key]?.stringValue }
    func number(_ key: String) -> Double? { fields[key]?.numberValue }
    func object(_ key: String) -> [String: ExamForgeJSONValue]? { fields[key]?.objectValue }
    func richText(_ key: String) -> String { fields[key]?.richPlainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var fallbackText: String { data.richPlainText.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension String {
    var nonEmpty: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
