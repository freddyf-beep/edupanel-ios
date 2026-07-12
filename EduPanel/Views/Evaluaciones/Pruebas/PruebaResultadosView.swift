import SwiftUI
import UniformTypeIdentifiers

struct PruebaResultadosView: View {
    let pruebaId: String
    let scope: EvaluacionScope
    let repository: EvaluacionesRepository

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var prueba: PruebaTemplate?
    @State private var draft: PruebaApplicationDraft?
    @State private var roster: [EstudiantePerfil] = []
    @State private var selectedStudentId: String?
    @State private var search = ""
    @State private var filter: ResultFilter = .all
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var lastSavedAt: Date?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var showReloadConfirmation = false
    @State private var showProjection = false
    @State private var showExporter = false

    private var hasChanges: Bool {
        draft?.hasUnsavedChanges == true
    }

    private var selectedIndex: Int? {
        guard let draft else { return nil }
        if let selectedStudentId,
           let index = draft.resultados.firstIndex(where: { $0.id == selectedStudentId }) {
            return index
        }
        return draft.resultados.indices.first
    }

    private var filteredResults: [PruebaStudentResultDraft] {
        guard let draft else { return [] }
        return draft.resultados.filter { result in
            let matchesSearch = search.isEmpty || result.nombre.localizedCaseInsensitiveContains(search)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .pending: matchesFilter = !result.completado && !result.ausente
            case .completed: matchesFilter = result.completado && !result.ausente
            case .absent: matchesFilter = result.ausente
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading, prueba == nil {
                    EvaluacionesLoadingCard(texto: "Cargando aplicación y resultados...")
                } else if let errorMessage, draft == nil {
                    EvaluacionesRetryCard(
                        title: "No se pudieron abrir los resultados",
                        message: errorMessage,
                        isLoading: isLoading
                    ) {
                        Task { await load() }
                    }
                } else if let prueba, draft != nil {
                    content(prueba)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(EPTheme.background)
        .navigationTitle("Aplicar y corregir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Guardando resultados")
                } else if hasChanges {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Cambios pendientes")
                } else if lastSavedAt != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Resultados guardados")
                }

                Button {
                    autosaveTask?.cancel()
                    Task { await save(showSuccess: true) }
                } label: {
                    Label("Guardar", systemImage: "square.and.arrow.down")
                }
                .disabled(isLoading || isSaving || !hasChanges)
            }
        }
        .confirmationDialog(
            "¿Recargar resultados?",
            isPresented: $showReloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Recargar y descartar cambios", role: .destructive) {
                Task { await load(force: true) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se descargará la versión más reciente del colegio activo.")
        }
        .fullScreenCover(isPresented: $showProjection) {
            if let prueba {
                PruebaProjectionView(prueba: prueba)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: PruebaCSVDocument(text: csvText),
            contentType: .commaSeparatedText,
            defaultFilename: csvFilename
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: draft) { oldValue, newValue in
            guard didLoad, oldValue != nil, newValue?.hasUnsavedChanges == true else { return }
            scheduleAutosave()
        }
        .task { await load() }
        .onDisappear {
            autosaveTask?.cancel()
        }
    }

    @ViewBuilder
    private func content(_ prueba: PruebaTemplate) -> some View {
        if let errorMessage {
            EvaluacionesErrorBanner(message: errorMessage)
            Button { showReloadConfirmation = true } label: {
                Label("Recargar desde EduPanel", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.black))
            }
            .buttonStyle(.bordered)
            .tint(EPTheme.rose)
        }

        header(prueba)
        statistics
        actions

        if draft?.resultados.isEmpty == true {
            EPWebCard {
                EPEmptyState(
                    icon: "person.3.sequence.fill",
                    title: "Curso sin estudiantes",
                    message: "Agrega estudiantes al curso para registrar respuestas. Si la web ya tenía resultados, estos aparecerían aunque el roster actual esté vacío."
                )
            }
        } else {
            filters
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 14) {
                    resultSidebar
                        .frame(width: 275)
                    selectedStudentEditor(prueba)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                studentChips
                selectedStudentEditor(prueba)
            }
        }

        if let draft {
            let completedNotes = draft.resultados
                .filter { $0.completado && !$0.ausente }
                .compactMap(\.nota)
            HistogramaNotasView(bins: NotaBin.bins(notas: completedNotes))

            SincronizarCalificacionesButton { overwrite in
                try await persistCurrent()
                guard let latest = self.draft else { throw CancellationError() }
                return try await repository.sincronizarPruebaConCalificaciones(
                    prueba: prueba,
                    aplicacion: latest,
                    roster: roster,
                    scope: scope,
                    sobrescribir: overwrite
                )
            }
        }
    }

    private func header(_ prueba: PruebaTemplate) -> some View {
        EPModuleHeader(
            eyebrow: "Prueba · \(prueba.curso)",
            title: prueba.nombre.isEmpty ? "Sin nombre" : prueba.nombre,
            subtitle: "\(prueba.asignatura) · \(prueba.totalItems) ítems · \(score(prueba.puntajeMaximo)) puntos",
            icon: "checkmark.rectangle.stack.fill",
            accent: .evaluaciones
        ) {
            ReplicaFlowLayout(spacing: 7) {
                EPStatusPill(text: "Aplicación apl_\(prueba.id)", tint: .blue)
                if prueba.isApplied {
                    EPStatusPill(text: "Estructura aplicada", icon: "lock.fill", tint: .green)
                }
                if let lastSavedAt {
                    EPStatusPill(
                        text: "Guardado \(lastSavedAt.formatted(date: .omitted, time: .shortened))",
                        icon: "checkmark.circle.fill",
                        tint: .green
                    )
                }
            }
        }
    }

    private var statistics: some View {
        let stats = draft?.stats ?? PruebaApplicationStats(
            promedio: 0,
            aprobados: 0,
            reprobados: 0,
            completados: 0,
            sinResolver: 0,
            ausentes: 0,
            mayor: 0,
            menor: 0
        )
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 9)], spacing: 9) {
            EPKPIBox(title: "Promedio", value: stats.completados > 0 ? score(stats.promedio) : "—", subtitle: "curso", icon: "chart.line.uptrend.xyaxis", tint: .blue)
            EPKPIBox(title: "Aprobados", value: "\(stats.aprobados)", subtitle: "nota ≥ 4,0", icon: "checkmark.circle.fill", tint: .green)
            EPKPIBox(title: "Reprobados", value: "\(stats.reprobados)", subtitle: "nota < 4,0", icon: "xmark.circle.fill", tint: .red)
            EPKPIBox(title: "Pendientes", value: "\(stats.sinResolver)", subtitle: "sin corregir", icon: "clock.fill", tint: .orange)
        }
    }

    private var actions: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(
                    title: "Herramientas de aplicación",
                    subtitle: "Proyecta preguntas, exporta el consolidado o fuerza el guardado.",
                    icon: "wrench.and.screwdriver.fill"
                )
                HStack(spacing: 8) {
                    actionButton("Proyectar", icon: "rectangle.inset.filled.and.person.filled") {
                        showProjection = true
                    }
                    actionButton("Exportar CSV", icon: "arrow.down.doc.fill") {
                        showExporter = true
                    }
                    actionButton(isSaving ? "Guardando" : "Guardar", icon: "square.and.arrow.down") {
                        autosaveTask?.cancel()
                        Task { await save(showSuccess: true) }
                    }
                    .disabled(isSaving || !hasChanges)
                }

                Text("Los cambios se guardan automáticamente tras una breve pausa. El primer guardado marca la estructura como aplicada, igual que EduPanel web.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                Text(title)
                    .font(.system(size: 10.5, weight: .black))
                    .lineLimit(1)
            }
            .foregroundStyle(EPTheme.rose)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(EPTheme.rose.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var filters: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("Buscar estudiante...", text: $search)
                    .font(.system(size: 12.5))
                    .textInputAutocapitalization(.words)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color(.systemGray6), in: Capsule())

            Menu {
                ForEach(ResultFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        if filter == option { Label(option.label, systemImage: "checkmark") }
                        else { Text(option.label) }
                    }
                }
            } label: {
                Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11.5, weight: .black))
                    .foregroundStyle(EPTheme.rose)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(EPTheme.rose.opacity(0.1), in: Capsule())
            }
        }
    }

    private var resultSidebar: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 8) {
                EPSectionHeader(
                    title: "Estudiantes",
                    subtitle: "\(filteredResults.count) visibles",
                    icon: "person.3.fill"
                )
                if filteredResults.isEmpty {
                    Text("No hay estudiantes para este filtro.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(filteredResults) { result in
                        studentRow(result)
                    }
                }
            }
        }
    }

    private var studentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(filteredResults) { result in
                    Button {
                        selectedStudentId = result.id
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusTint(result))
                                .frame(width: 7, height: 7)
                            Text(firstName(result.nombre))
                                .font(.system(size: 11.5, weight: .black))
                            if result.hasPie {
                                Text("PIE").font(.system(size: 8, weight: .black))
                            }
                        }
                        .foregroundStyle(selectedStudentId == result.id ? .white : .primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            selectedStudentId == result.id ? EPTheme.rose : Color(.secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func studentRow(_ result: PruebaStudentResultDraft) -> some View {
        Button {
            selectedStudentId = result.id
        } label: {
            HStack(spacing: 9) {
                Image(systemName: result.ausente ? "person.crop.circle.badge.xmark" : "person.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(statusTint(result))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(result.nombre)
                            .font(.system(size: 11.5, weight: .black))
                            .lineLimit(1)
                        if result.hasPie {
                            Text("PIE")
                                .font(.system(size: 7.5, weight: .black))
                                .foregroundStyle(.purple)
                        }
                    }
                    Text(result.ausente ? "Ausente" : "\(score(result.puntajeTotal)) pts · Nota \(score(result.nota ?? 1))")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if result.completado {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(9)
            .background(
                selectedStudentId == result.id ? EPTheme.rose.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectedStudentEditor(_ prueba: PruebaTemplate) -> some View {
        if let index = selectedIndex, draft?.resultados.indices.contains(index) == true {
            PruebaStudentCorrectionView(
                prueba: prueba,
                result: studentBinding(at: index),
                position: index + 1,
                total: draft?.resultados.count ?? 0,
                onPrevious: index > 0 ? { selectStudent(at: index - 1) } : nil,
                onNext: (draft?.resultados.indices.contains(index + 1) == true)
                    ? { selectStudent(at: index + 1) } : nil
            )
        } else {
            EPWebCard {
                EPEmptyState(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Sin estudiante seleccionado",
                    message: "Elige un estudiante para registrar y corregir sus respuestas."
                )
            }
        }
    }

    private func studentBinding(at index: Int) -> Binding<PruebaStudentResultDraft> {
        Binding(
            get: {
                guard let draft, draft.resultados.indices.contains(index) else {
                    return PruebaStudentResultDraft.new(
                        EstudiantePerfil(
                            id: "missing",
                            nombre: "Estudiante",
                            orden: 1,
                            pie: false,
                            pieDiagnostico: "",
                            pieEspecialista: "",
                            pieNotas: ""
                        )
                    )
                }
                return draft.resultados[index]
            },
            set: { value in
                guard var current = draft, current.resultados.indices.contains(index), let prueba else { return }
                current.resultados[index] = value
                current.resultados[index].recalculate(with: prueba)
                draft = current
            }
        )
    }

    private func selectStudent(at index: Int) {
        guard let draft, draft.resultados.indices.contains(index) else { return }
        selectedStudentId = draft.resultados[index].id
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.1))
                try Task.checkCancellation()
                await save(showSuccess: false)
            } catch {
                return
            }
        }
    }

    @MainActor
    private func persistCurrent() async throws {
        guard !isSaving else { throw PruebaResultsError.saveInProgress }
        guard var snapshot = draft, let prueba else { throw PruebaResultsError.missingData }
        snapshot.recalculate(with: prueba)
        guard snapshot.hasUnsavedChanges else { return }

        isSaving = true
        defer { isSaving = false }
        try await repository.guardarAplicacionPrueba(snapshot, prueba: prueba, scope: scope)

        var savedSnapshot = snapshot
        savedSnapshot.markSaved()

        guard var current = draft else { return }
        current.recalculate(with: prueba)
        if current.editableFingerprint == snapshot.editableFingerprint {
            draft = savedSnapshot
        } else {
            // Hubo una edición mientras Firestore guardaba. La nueva base remota es
            // el snapshot enviado; el siguiente debounce persiste el cambio posterior.
            current.isNew = false
            current.baselineFingerprint = savedSnapshot.editableFingerprint
            draft = current
            scheduleAutosave()
        }
        lastSavedAt = Date()
        errorMessage = nil
    }

    @MainActor
    private func save(showSuccess: Bool) async {
        do {
            try await persistCurrent()
            if showSuccess { lastSavedAt = Date() }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func load(force: Bool = false) async {
        if isLoading, didLoad, !force { return }
        autosaveTask?.cancel()
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }

        do {
            guard let loadedTest = try await repository.cargarPrueba(id: pruebaId, scope: scope) else {
                prueba = nil
                draft = nil
                errorMessage = "La prueba no existe en el colegio seleccionado."
                return
            }
            async let applicationTask = repository.cargarAplicacionPrueba(pruebaId: pruebaId, scope: scope)
            async let rosterTask = repository.cargarEstudiantesPrueba(curso: loadedTest.curso, scope: scope)
            let (application, loadedRoster) = try await (applicationTask, rosterTask)
            try Task.checkCancellation()

            let loadedDraft = PruebaApplicationDraft.build(
                prueba: loadedTest,
                application: application,
                roster: loadedRoster
            )
            prueba = loadedTest
            roster = loadedRoster
            draft = loadedDraft
            selectedStudentId = loadedDraft.resultados.first?.id
            lastSavedAt = application?.fechaActualizacion
        } catch is CancellationError {
            return
        } catch {
            if force {
                prueba = nil
                draft = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    private var csvText: String {
        guard let prueba, let draft else { return "" }
        let rows: [[String]] = [
            ["Estudiante", "PIE", "Estado", "Puntaje", "Puntaje maximo", "Nota", "Observaciones"]
        ] + draft.resultados.map { result in
            [
                result.nombre,
                result.hasPie ? "Si" : "No",
                result.ausente ? "Ausente" : result.completado ? "Completado" : "Sin resolver",
                score(result.puntajeTotal),
                score(prueba.puntajeMaximo),
                result.nota.map { score($0) } ?? "",
                result.observaciones
            ]
        }
        return "\u{FEFF}" + rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n")
    }

    private var csvFilename: String {
        let base = (prueba?.nombre.isEmpty == false ? prueba!.nombre : "resultados")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_CL"))
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]+", with: "-", options: .regularExpression)
        return "\(base)-resultados.csv"
    }

    private func csvCell(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func score(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "es_CL")).precision(.fractionLength(1)))
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private func statusTint(_ result: PruebaStudentResultDraft) -> Color {
        if result.ausente { return .orange }
        if result.completado { return result.nota.map { $0 >= 4 ? Color.green : Color.red } ?? .green }
        return .gray
    }
}

private enum ResultFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case completed
    case absent

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Todos"
        case .pending: return "Pendientes"
        case .completed: return "Corregidos"
        case .absent: return "Ausentes"
        }
    }
}

private enum PruebaResultsError: LocalizedError {
    case saveInProgress
    case missingData

    var errorDescription: String? {
        switch self {
        case .saveInProgress: return "Ya hay un guardado de resultados en curso."
        case .missingData: return "La prueba o su aplicación ya no está disponible."
        }
    }
}

private struct PruebaStudentCorrectionView: View {
    let prueba: PruebaTemplate
    @Binding var result: PruebaStudentResultDraft
    let position: Int
    let total: Int
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                header

                if result.ausente {
                    Label("Estudiante ausente. Su nota no se enviará a Calificaciones.", systemImage: "person.crop.circle.badge.xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(Array(prueba.secciones.enumerated()), id: \.element.id) { _, section in
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.titulo.isEmpty ? "Sección \(section.orden)" : section.titulo)
                                    .font(.system(size: 13, weight: .black))
                                if !section.instrucciones.isEmpty {
                                    Text(section.instrucciones)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                                PruebaResponseEditor(
                                    item: item,
                                    number: itemIndex + 1,
                                    response: item.sourceId.flatMap { result.respuestas[$0] },
                                    isDisabled: false
                                ) { response in
                                    result.respuestas[response.id] = response
                                    result.preservedResponseKeys.insert(response.id)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Observaciones")
                            .font(.caption.weight(.black))
                        TextEditor(text: $result.observaciones)
                            .font(.system(size: 12.5))
                            .frame(minHeight: 76)
                            .padding(6)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            }
                    }
                }

                navigation
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.nombre)
                            .font(.system(size: 17, weight: .black))
                        if result.hasPie {
                            EPStatusPill(text: "PIE", tint: .purple)
                        }
                    }
                    if !result.ausente {
                        Text("\(score(result.puntajeTotal)) / \(score(prueba.puntajeMaximo)) pts · Nota \(score(result.nota ?? 1))")
                            .font(.caption.weight(.black))
                            .foregroundStyle((result.nota ?? 1) >= 4 ? .green : .red)
                    }
                }
                Spacer()
                Text("\(position) / \(total)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Toggle("Ausente", isOn: $result.ausente)
                    .toggleStyle(.switch)
                    .tint(.orange)
                Toggle("Listo / corregido", isOn: $result.completado)
                    .toggleStyle(.switch)
                    .tint(.green)
            }
            .font(.caption.weight(.bold))
        }
    }

    private var navigation: some View {
        HStack {
            Button(action: { onPrevious?() }) {
                Label("Anterior", systemImage: "chevron.left")
            }
            .disabled(onPrevious == nil)
            Spacer()
            Button(action: { onNext?() }) {
                Label("Siguiente", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(onNext == nil)
        }
        .font(.caption.weight(.black))
        .buttonStyle(.bordered)
        .tint(EPTheme.rose)
    }

    private func score(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "es_CL")).precision(.fractionLength(1)))
    }
}

private struct PruebaCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct PruebaProjectionView: View {
    @Environment(\.dismiss) private var dismiss
    let prueba: PruebaTemplate

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prueba.nombre.isEmpty ? "Prueba" : prueba.nombre)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Text("\(prueba.asignatura) · \(prueba.curso)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(prueba.secciones.sorted { $0.orden < $1.orden }) { section in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(section.titulo)
                                .font(.title2.weight(.black))
                            if !section.instrucciones.isEmpty {
                                Text(section.instrucciones)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                projectedItem(item, number: index + 1)
                            }
                        }
                        .padding(22)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(24)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Modo proyección")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .fontWeight(.black)
                }
            }
        }
    }

    private func projectedItem(_ item: PruebaItem, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(EPTheme.rose, in: Circle())
                Text(item.enunciado)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(item.recursos) { resource in
                if resource.kind == .imagen, let urlString = resource.url, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if resource.kind == .texto, let html = resource.html, !html.isEmpty {
                    Text(html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                        .font(.body)
                }
            }

            switch item.kind {
            case .seleccionMultiple:
                ForEach(Array(item.alternativas.enumerated()), id: \.element.id) { index, option in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(Character(UnicodeScalar(65 + index)!)).")
                            .fontWeight(.black)
                        Text(option.texto)
                    }
                    .font(.headline)
                }
            case .verdaderoFalso:
                Text("Verdadero     /     Falso").font(.headline.weight(.black))
            case .pareados:
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(item.columnaA.enumerated()), id: \.element.id) { index, value in
                            Text("\(index + 1). \(value.texto)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(item.columnaB.enumerated()), id: \.element.id) { index, value in
                            Text("\(Character(UnicodeScalar(65 + index)!)). \(value.texto)")
                        }
                    }
                }
                .font(.headline)
            case .ordenar:
                ForEach(item.pasos) { step in
                    Text("□  \(step.texto)").font(.headline)
                }
            case .completar:
                Text(item.textoConBlancos ?? "").font(.headline)
            case .respuestaCorta, .desarrollo:
                ForEach(0..<max(2, item.lineasRespuesta ?? 3), id: \.self) { _ in
                    Divider().padding(.top, 12)
                }
            case .unknown:
                Text("Tipo de ítem no compatible con proyección.")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 8)
    }
}
