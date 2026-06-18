import SwiftUI

struct ListaCotejoEditorView: View {
    let listaId: String?
    let curso: String
    let asignatura: String
    let dashboardRepository: DashboardRepository

    @State private var lista: ListaCotejoTemplate?
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
                } else if let errorMessage, lista == nil {
                    EvaluacionesErrorBanner(message: errorMessage)
                } else if lista != nil {
                    contenidoEditor
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(listaId == nil ? "Nueva lista" : "Editar lista")
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
                    titulo: "Nombre de la lista",
                    placeholder: "Ej: Lista de cotejo Unidad 2",
                    texto: bindingLista(\.nombre)
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("CURSO")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    EvaluacionesCursoPicker(cursos: cursos, seleccionado: bindingLista(\.curso))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("INSTRUCCIONES METODOL\u{00D3}GICAS")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    TextField(
                        "Describe c\u{00F3}mo aplicar\u{00E1}s esta lista...",
                        text: Binding(
                            get: { lista?.instruccionesMetodologicas ?? "" },
                            set: { lista?.instruccionesMetodologicas = $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .font(.system(size: 13.5))
                    .padding(10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ESCALA DICOT\u{00D3}MICA")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        escalaCampo(titulo: "Logrado", icono: "checkmark", tint: .green, texto: bindingEscala(0, def: "S\u{00ED}"))
                        escalaCampo(titulo: "No logrado", icono: "xmark", tint: .red, texto: bindingEscala(1, def: "No"))
                    }
                }

                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("PUNTAJE M\u{00C1}XIMO")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("\(lista.map { Int(Double($0.indicadoresTotales.count) * max($0.puntajePorSi, 1)) } ?? 0) pts")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(EPTheme.primary)
                    }
                }
            }
        }

        if let actual = lista {
            EvaluacionesCurriculoSection(
                asignatura: actual.asignatura,
                curso: actual.curso,
                nivelMapping: nivelMapping,
                unidadId: Binding(get: { lista?.unidadId }, set: { lista?.unidadId = $0 }),
                unidadNombre: Binding(get: { lista?.unidadNombre }, set: { lista?.unidadNombre = $0 }),
                oas: Binding(get: { lista?.oas }, set: { lista?.oas = $0 })
            )
        }

        if let lista {
            ForEach(lista.secciones) { seccion in
                seccionCard(seccion)
            }
        }

        Button {
            guard var actual = lista else { return }
            actual.secciones.append(.nueva(numero: actual.secciones.count + 1))
            lista = actual
        } label: {
            Label("Agregar secci\u{00F3}n", systemImage: "plus.rectangle.on.rectangle")
                .font(.system(size: 12.5, weight: .black))
                .foregroundStyle(EPTheme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(EPTheme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func seccionCard(_ seccion: SeccionListaCotejo) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Nombre de la secci\u{00F3}n", text: bindingSeccion(seccion.id, \.nombre))
                        .font(.system(size: 14, weight: .black))

                    if (lista?.secciones.count ?? 0) > 1 {
                        Button {
                            lista?.secciones.removeAll { $0.id == seccion.id }
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
                        get: { seccionActual(seccion.id)?.oasVinculados.joined(separator: ", ") ?? "" },
                        set: { nuevo in
                            actualizarSeccion(seccion.id) { $0.oasVinculados = Self.parseRefs(nuevo) }
                        }
                    )
                )

                ForEach(seccion.indicadores) { indicador in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(indicador.orden)")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(EPTheme.primary)
                                .frame(width: 24, height: 24)
                                .background(EPTheme.primary.opacity(0.1), in: Circle())

                            TextField(
                                "Indicador observable (ej: nombra, se\u{00F1}ala, ejecuta...)",
                                text: bindingIndicador(seccion.id, indicador.id),
                                axis: .vertical
                            )
                            .lineLimit(1...4)
                            .font(.system(size: 13))
                            .padding(9)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                            Button {
                                actualizarSeccion(seccion.id) { sec in
                                    guard sec.indicadores.count > 1 else { return }
                                    sec.indicadores.removeAll { $0.id == indicador.id }
                                    for index in sec.indicadores.indices {
                                        sec.indicadores[index].orden = index + 1
                                    }
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(Color(.systemGray6), in: Circle())
                            }
                            .padding(.top, 5)
                        }

                        if let aviso = Self.avisoVerbo(indicador.texto) {
                            Label(aviso, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.leading, 32)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 6) {
                            indicadorChip("Transversal", "arrow.triangle.branch", activo: indicador.esTransversal == true, tint: .purple) {
                                actualizarIndicadorCampo(seccion.id, indicador.id) { $0.esTransversal = !($0.esTransversal ?? false) }
                            }
                            indicadorChip("Puedo filmarlo", "video.fill", activo: indicador.puedoFilmarloConfirmado == true, tint: .blue) {
                                actualizarIndicadorCampo(seccion.id, indicador.id) { $0.puedoFilmarloConfirmado = !($0.puedoFilmarloConfirmado ?? false) }
                            }
                            indicadorChip("Foco PIE", "target", activo: indicador.focoDiferenciadoActivo == true, tint: EPTheme.primary) {
                                actualizarIndicadorCampo(seccion.id, indicador.id) { $0.focoDiferenciadoActivo = !($0.focoDiferenciadoActivo ?? false) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 32)

                        if indicador.focoDiferenciadoActivo == true {
                            TextField(
                                "Foco diferenciado para estudiantes PIE...",
                                text: bindingFocoTexto(seccion.id, indicador.id),
                                axis: .vertical
                            )
                            .lineLimit(1...3)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(EPTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.leading, 32)
                        }
                    }
                }

                Button {
                    actualizarSeccion(seccion.id) { sec in
                        var nuevo = IndicadorListaCotejo.nuevo()
                        nuevo.orden = sec.indicadores.count + 1
                        sec.indicadores.append(nuevo)
                    }
                } label: {
                    Label("Agregar indicador", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .black))
                        .foregroundStyle(EPTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(EPTheme.primary.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    // MARK: - Bindings y helpers

    private func bindingLista(_ keyPath: WritableKeyPath<ListaCotejoTemplate, String>) -> Binding<String> {
        Binding(
            get: { lista?[keyPath: keyPath] ?? "" },
            set: { lista?[keyPath: keyPath] = $0 }
        )
    }

    private func seccionActual(_ id: String) -> SeccionListaCotejo? {
        lista?.secciones.first { $0.id == id }
    }

    private func actualizarSeccion(_ id: String, _ transform: (inout SeccionListaCotejo) -> Void) {
        guard var actual = lista, let index = actual.secciones.firstIndex(where: { $0.id == id }) else { return }
        transform(&actual.secciones[index])
        lista = actual
    }

    private func bindingSeccion(_ id: String, _ keyPath: WritableKeyPath<SeccionListaCotejo, String>) -> Binding<String> {
        Binding(
            get: { seccionActual(id)?[keyPath: keyPath] ?? "" },
            set: { nuevo in actualizarSeccion(id) { $0[keyPath: keyPath] = nuevo } }
        )
    }

    private func bindingIndicador(_ seccionId: String, _ indicadorId: String) -> Binding<String> {
        Binding(
            get: { seccionActual(seccionId)?.indicadores.first { $0.id == indicadorId }?.texto ?? "" },
            set: { nuevo in
                actualizarSeccion(seccionId) { sec in
                    if let index = sec.indicadores.firstIndex(where: { $0.id == indicadorId }) {
                        sec.indicadores[index].texto = nuevo
                    }
                }
            }
        )
    }

    private func actualizarIndicadorCampo(_ seccionId: String, _ indicadorId: String, _ transform: (inout IndicadorListaCotejo) -> Void) {
        actualizarSeccion(seccionId) { sec in
            if let index = sec.indicadores.firstIndex(where: { $0.id == indicadorId }) {
                transform(&sec.indicadores[index])
            }
        }
    }

    private func bindingFocoTexto(_ seccionId: String, _ indicadorId: String) -> Binding<String> {
        Binding(
            get: { seccionActual(seccionId)?.indicadores.first { $0.id == indicadorId }?.focoDiferenciadoTexto ?? "" },
            set: { nuevo in actualizarIndicadorCampo(seccionId, indicadorId) { $0.focoDiferenciadoTexto = nuevo } }
        )
    }

    private func indicadorChip(_ titulo: String, _ icono: String, activo: Bool, tint: Color, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 4) {
                Image(systemName: icono)
                    .font(.system(size: 8.5, weight: .black))
                Text(titulo)
                    .font(.system(size: 9.5, weight: .black))
            }
            .foregroundStyle(activo ? .white : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(activo ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private static func parseRefs(_ value: String) -> [String] {
        value.split(whereSeparator: { ",;/|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func escalaCampo(titulo: String, icono: String, tint: Color, texto: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(titulo, systemImage: icono)
                .font(.system(size: 9.5, weight: .black))
                .foregroundStyle(tint)
            TextField(titulo, text: texto)
                .font(.system(size: 13, weight: .bold))
                .padding(9)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func bindingEscala(_ index: Int, def: String) -> Binding<String> {
        Binding(
            get: {
                let escala = lista?.escalaDicotomica ?? ["S\u{00ED}", "No"]
                return index < escala.count ? escala[index] : def
            },
            set: { nuevo in
                var escala = lista?.escalaDicotomica ?? ["S\u{00ED}", "No"]
                while escala.count < 2 { escala.append(escala.isEmpty ? "S\u{00ED}" : "No") }
                escala[index] = nuevo
                lista?.escalaDicotomica = escala
            }
        )
    }

    /// Verbos cognitivos inobservables: en una lista de cotejo conviene evitarlos (igual que la web).
    private static let verbosMentalistas: Set<String> = [
        "comprende", "comprender", "comprenden", "comprendio",
        "entiende", "entender", "entienden", "entendio",
        "sabe", "saber", "saben", "sabia",
        "conoce", "conocer", "conocen", "conocio",
        "reflexiona", "reflexionar", "reflexionan",
        "valora", "valorar", "valoran", "valoro",
        "aprecia", "apreciar", "aprecian",
        "asimila", "asimilar", "asimilacion",
        "piensa", "pensar", "piensan",
        "razona", "razonar", "razonan"
    ]

    static func avisoVerbo(_ texto: String) -> String? {
        let limpio = texto.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_CL")).lowercased()
        let palabras = limpio.split { !($0.isLetter) }.map(String.init)
        guard let coincidencia = palabras.first(where: { verbosMentalistas.contains($0) }) else { return nil }
        return "Evita verbos no observables como \u{201C}\(coincidencia)\u{201D}. Usa verbos observables (nombra, se\u{00F1}ala, ejecuta...)."
    }

    // MARK: - Datos

    private func cargar() async {
        defer { isLoading = false }
        do {
            let snapshot = try await dashboardRepository.fetchDashboard()
            cursos = snapshot.courses
            nivelMapping = snapshot.nivelMapping

            if let listaId {
                guard let existente = try await repository.cargarListaCotejo(id: listaId) else {
                    errorMessage = "Lista de cotejo no encontrada."
                    return
                }
                lista = existente
            } else {
                let cursoBase = curso.isEmpty ? (cursos.first ?? "") : curso
                lista = .nueva(asignatura: asignatura, curso: cursoBase)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func guardar() async {
        guard let actual = lista else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await repository.guardarListaCotejo(actual)
            var refrescada = actual
            refrescada.normalizar()
            if refrescada.fechaActualizacion == nil {
                refrescada.fechaActualizacion = Date()
            }
            lista = refrescada
            saveOk = true
            try? await Task.sleep(for: .seconds(1.6))
            saveOk = false
        } catch {
            errorMessage = "No se pudo guardar la lista. Intenta nuevamente."
        }
    }
}

struct CampoTextoEditor: View {
    let titulo: String
    let placeholder: String
    @Binding var texto: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $texto)
                .font(.system(size: 13.5))
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
