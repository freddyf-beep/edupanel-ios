import SwiftUI

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
            } else if viewModel.pruebas.isEmpty {
                emptyState
            } else if filteredTests.isEmpty {
                filteredEmptyState
            } else {
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
                value: "\(viewModel.pruebas.count)",
                subtitle: viewModel.selectedCurso,
                icon: "doc.text.fill",
                tint: EPTheme.rose
            )
            EPKPIBox(
                title: "Listas",
                value: "\(viewModel.pruebas.filter { $0.estado == "lista" }.count)",
                subtitle: "para aplicar",
                icon: "checkmark.seal.fill",
                tint: .green
            )
            EPKPIBox(
                title: "Borradores",
                value: "\(viewModel.pruebas.filter { $0.estado.isEmpty || $0.estado == "borrador" }.count)",
                subtitle: "en preparación",
                icon: "pencil.and.outline",
                tint: .orange
            )
            EPKPIBox(
                title: "Con OA",
                value: "\(viewModel.pruebas.filter { !$0.metadatosCurriculares.objetivos.isEmpty }.count)",
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
        return viewModel.pruebas.compactMap { test in
            guard let id = test.unidadId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  seen.insert(id).inserted else { return nil }
            let name = test.unidadNombre?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PruebaUnitFilter(id: id, name: name?.isEmpty == false ? name! : id)
        }
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
