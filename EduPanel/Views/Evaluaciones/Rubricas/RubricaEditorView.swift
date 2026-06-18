import SwiftUI

struct RubricaEditorView: View {
    let rubricaId: String?
    let curso: String
    let asignatura: String
    let dashboardRepository: DashboardRepository

    @State private var rubrica: RubricaTemplate?
    @State private var cursos: [String] = []
    @State private var nivelMapping: [String: String] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saveOk = false
    @State private var errorMessage: String?

    private let repository = EvaluacionesRepository()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    EvaluacionesLoadingCard(texto: "Cargando editor...")
                } else if let errorMessage, rubrica == nil {
                    EvaluacionesErrorBanner(message: errorMessage)
                } else if rubrica != nil {
                    contenidoEditor
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(rubricaId == nil ? "Nueva r\u{00FA}brica" : "Editar r\u{00FA}brica")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await guardar() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(saveOk ? "Guardado" : "Guardar")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(saveOk ? .green : EPTheme.primary)
                    }
                }
                .disabled(isSaving)
            }
        }
        .task { await cargar() }
    }

    @ViewBuilder
    private var contenidoEditor: some View {
        if let errorMessage {
            EvaluacionesErrorBanner(message: errorMessage)
        }

        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Informaci\u{00F3}n general", icon: "doc.text")

                CampoTextoEditor(
                    titulo: "Nombre de la r\u{00FA}brica",
                    placeholder: "Ej: R\u{00FA}brica presentaci\u{00F3}n musical",
                    texto: Binding(
                        get: { rubrica?.nombre ?? "" },
                        set: { rubrica?.nombre = $0 }
                    )
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("CURSO")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    EvaluacionesCursoPicker(
                        cursos: cursos,
                        seleccionado: Binding(
                            get: { rubrica?.curso ?? "" },
                            set: { rubrica?.curso = $0 }
                        )
                    )
                }

                Toggle(isOn: Binding(
                    get: { rubrica?.usaPonderaciones ?? false },
                    set: { rubrica?.usaPonderaciones = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usar ponderaciones")
                            .font(.system(size: 13, weight: .bold))
                        Text("Multiplica el puntaje de cada criterio por su ponderaci\u{00F3}n.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(EPTheme.primary)

                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("PUNTAJE M\u{00C1}XIMO")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("\(Int(RubricaTemplate.calcularPuntajeMaximo(partes: rubrica?.partes ?? []))) pts")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(EPTheme.fuchsia)
                    }
                }
            }
        }

        if let actual = rubrica {
            EvaluacionesCurriculoSection(
                asignatura: actual.asignatura,
                curso: actual.curso,
                nivelMapping: nivelMapping,
                unidadId: Binding(get: { rubrica?.unidadId }, set: { rubrica?.unidadId = $0 }),
                unidadNombre: Binding(get: { rubrica?.unidadNombre }, set: { rubrica?.unidadNombre = $0 }),
                oas: Binding(get: { rubrica?.oas }, set: { rubrica?.oas = $0 })
            )
        }

        if let rubrica {
            ForEach(rubrica.partes) { parte in
                parteCard(parte)
            }
        }

        Button {
            guard var actual = rubrica else { return }
            actual.partes.append(.nueva(numero: actual.partes.count + 1))
            rubrica = actual
        } label: {
            Label("Agregar parte", systemImage: "plus.rectangle.on.rectangle")
                .font(.system(size: 12.5, weight: .black))
                .foregroundStyle(EPTheme.fuchsia)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(EPTheme.fuchsia.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func parteCard(_ parte: RubricaParte) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Nombre de la parte", text: bindingParte(parte.id, \.nombre))
                        .font(.system(size: 14, weight: .black))

                    if (rubrica?.partes.count ?? 0) > 1 {
                        Button {
                            rubrica?.partes.removeAll { $0.id == parte.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.1), in: Circle())
                        }
                    }
                }

                CampoTextoEditor(
                    titulo: "OAs vinculados",
                    placeholder: "Ej: OA 2, OA 4",
                    texto: Binding(
                        get: { parteActual(parte.id)?.oasVinculados.joined(separator: ", ") ?? "" },
                        set: { nuevo in
                            actualizarParte(parte.id) { $0.oasVinculados = Self.parseRefs(nuevo) }
                        }
                    )
                )

                ForEach(parte.criterios) { criterio in
                    criterioCard(parteId: parte.id, criterio: criterio)
                }

                Button {
                    actualizarParte(parte.id) { par in
                        var nuevo = CriterioRubrica.nuevo()
                        nuevo.orden = par.criterios.count + 1
                        par.criterios.append(nuevo)
                    }
                } label: {
                    Label("Agregar criterio", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .black))
                        .foregroundStyle(EPTheme.fuchsia)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(EPTheme.fuchsia.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    private func criterioCard(parteId: String, criterio: CriterioRubrica) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(criterio.orden)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(EPTheme.fuchsia)
                    .frame(width: 24, height: 24)
                    .background(EPTheme.fuchsia.opacity(0.12), in: Circle())

                TextField("Nombre del criterio", text: bindingCriterio(parteId, criterio.id, \.nombre))
                    .font(.system(size: 13, weight: .bold))

                Button {
                    actualizarParte(parteId) { par in
                        guard par.criterios.count > 1 else { return }
                        par.criterios.removeAll { $0.id == criterio.id }
                        for index in par.criterios.indices {
                            par.criterios[index].orden = index + 1
                        }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.systemGray5), in: Circle())
                }
            }

            if rubrica?.usaPonderaciones == true {
                Stepper(value: bindingPonderacion(parteId, criterio.id), in: 1...5) {
                    Text("Ponderaci\u{00F3}n x\(Int(criterio.ponderacion ?? 1))")
                        .font(.system(size: 12, weight: .bold))
                }
            }

            ForEach(NivelRubrica.allCases) { nivel in
                HStack(alignment: .top, spacing: 8) {
                    Text(nivel.etiqueta)
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 22)
                        .background(colorNivel(nivel), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    TextField(
                        "\(nivel.titulo) (\(Int(nivel.rawValue)) pts)...",
                        text: bindingNivel(parteId, criterio.id, nivel),
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func colorNivel(_ nivel: NivelRubrica) -> Color {
        switch nivel {
        case .logrado: return .green
        case .casiLogrado: return .blue
        case .parcialmenteLogrado: return .orange
        case .porLograr: return .red
        }
    }

    // MARK: - Bindings y helpers

    private func parteActual(_ id: String) -> RubricaParte? {
        rubrica?.partes.first { $0.id == id }
    }

    private func actualizarParte(_ id: String, _ transform: (inout RubricaParte) -> Void) {
        guard var actual = rubrica, let index = actual.partes.firstIndex(where: { $0.id == id }) else { return }
        transform(&actual.partes[index])
        rubrica = actual
    }

    private func bindingParte(_ id: String, _ keyPath: WritableKeyPath<RubricaParte, String>) -> Binding<String> {
        Binding(
            get: { parteActual(id)?[keyPath: keyPath] ?? "" },
            set: { nuevo in actualizarParte(id) { $0[keyPath: keyPath] = nuevo } }
        )
    }

    private func actualizarCriterio(_ parteId: String, _ criterioId: String, _ transform: (inout CriterioRubrica) -> Void) {
        actualizarParte(parteId) { parte in
            if let index = parte.criterios.firstIndex(where: { $0.id == criterioId }) {
                transform(&parte.criterios[index])
            }
        }
    }

    private func bindingCriterio(_ parteId: String, _ criterioId: String, _ keyPath: WritableKeyPath<CriterioRubrica, String>) -> Binding<String> {
        Binding(
            get: { parteActual(parteId)?.criterios.first { $0.id == criterioId }?[keyPath: keyPath] ?? "" },
            set: { nuevo in actualizarCriterio(parteId, criterioId) { $0[keyPath: keyPath] = nuevo } }
        )
    }

    private func bindingPonderacion(_ parteId: String, _ criterioId: String) -> Binding<Int> {
        Binding(
            get: { Int(parteActual(parteId)?.criterios.first { $0.id == criterioId }?.ponderacion ?? 1) },
            set: { nuevo in actualizarCriterio(parteId, criterioId) { $0.ponderacion = Double(nuevo) } }
        )
    }

    private func bindingNivel(_ parteId: String, _ criterioId: String, _ nivel: NivelRubrica) -> Binding<String> {
        Binding(
            get: {
                guard let criterio = parteActual(parteId)?.criterios.first(where: { $0.id == criterioId }) else { return "" }
                return nivel.descripcion(en: criterio)
            },
            set: { nuevo in
                actualizarCriterio(parteId, criterioId) { criterio in
                    switch nivel {
                    case .logrado: criterio.niveles.logrado.descripcion = nuevo
                    case .casiLogrado: criterio.niveles.casiLogrado.descripcion = nuevo
                    case .parcialmenteLogrado: criterio.niveles.parcialmenteLogrado.descripcion = nuevo
                    case .porLograr: criterio.niveles.porLograr.descripcion = nuevo
                    }
                }
            }
        )
    }

    private static func parseRefs(_ value: String) -> [String] {
        value.split(whereSeparator: { ",;/|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Datos

    private func cargar() async {
        defer { isLoading = false }
        do {
            let snapshot = try await dashboardRepository.fetchDashboard()
            cursos = snapshot.courses
            nivelMapping = snapshot.nivelMapping

            if let rubricaId {
                guard let existente = try await repository.cargarRubrica(id: rubricaId) else {
                    errorMessage = "R\u{00FA}brica no encontrada."
                    return
                }
                rubrica = existente
            } else {
                let cursoBase = curso.isEmpty ? (cursos.first ?? "") : curso
                rubrica = .nueva(asignatura: asignatura, curso: cursoBase)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func guardar() async {
        guard let actual = rubrica else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await repository.guardarRubrica(actual)
            var refrescada = actual
            refrescada.normalizar()
            if refrescada.fechaActualizacion == nil {
                refrescada.fechaActualizacion = Date()
            }
            rubrica = refrescada
            saveOk = true
            try? await Task.sleep(for: .seconds(1.6))
            saveOk = false
        } catch {
            errorMessage = "No se pudo guardar la r\u{00FA}brica. Intenta nuevamente."
        }
    }
}
