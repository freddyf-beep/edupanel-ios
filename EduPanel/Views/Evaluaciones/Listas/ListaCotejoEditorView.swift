import SwiftUI

struct ListaCotejoEditorView: View {
    let listaId: String?
    let curso: String
    let asignatura: String
    let dashboardRepository: DashboardRepository

    @State private var lista: ListaCotejoTemplate?
    @State private var cursos: [String] = []
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

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ESCALA")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            EPStatusPill(text: lista?.etiquetaSi ?? "S\u{00ED}", icon: "checkmark", tint: .green)
                            EPStatusPill(text: lista?.etiquetaNo ?? "No", icon: "xmark", tint: .red)
                        }
                    }

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
