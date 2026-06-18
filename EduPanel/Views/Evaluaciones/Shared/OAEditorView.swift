import SwiftUI

private let oaColors: [Color] = [
    Color(hex6: 0xF59E0B), Color(hex6: 0x3B82F6), Color(hex6: 0xEF4444),
    Color(hex6: 0x22C55E), Color(hex6: 0x8B5CF6), Color(hex6: 0xF97316),
    Color(hex6: 0x06B6D4), Color(hex6: 0xD97706), Color(hex6: 0xEC4899),
    Color(hex6: 0x10B981)
]

private func colorParaOA(_ oa: OAEditado, index: Int) -> Color {
    if let numero = oa.numero {
        return oaColors[(numero - 1 + oaColors.count) % oaColors.count]
    }
    return oaColors[index % oaColors.count]
}

private func etiquetaOA(_ oa: OAEditado) -> String {
    let base = oa.tipo == "oat" ? "OAA" : "OA"
    if oa.esPropio == true {
        if let numero = oa.numero { return "\(base) \(numero) Propio" }
        return "\(base) Propio"
    }
    if let numero = oa.numero { return "\(base) \(numero)" }
    return base
}

struct OAEditorView: View {
    @Binding var oas: [OAEditado]
    var asignatura: String
    var cargando: Bool

    @State private var expandidos: Set<String> = []
    @State private var mostrarNuevoOA = false
    @State private var nuevoOATexto = ""
    @State private var nuevoOANumero = ""
    @State private var nuevoOATipo = "oa"
    @State private var nuevoIndicadorTexto: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if cargando {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Cargando OA del curr\u{00ED}culum...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if oas.isEmpty {
                Text("Selecciona una unidad curricular arriba para cargar los OA autom\u{00E1}ticamente.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Color(.separator))
                    )
            } else {
                ForEach(Array(oas.enumerated()), id: \.element.id) { index, oa in
                    oaCard(oa: oa, index: index)
                }
            }

            if !cargando {
                nuevoOASection
            }
        }
    }

    private func oaCard(oa: OAEditado, index: Int) -> some View {
        let color = colorParaOA(oa, index: index)
        let expandido = expandidos.contains(oa.id)
        let seleccionados = oa.indicadores.filter(\.seleccionado).count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    actualizarOA(oa.id) { $0.seleccionado.toggle() }
                } label: {
                    Circle()
                        .fill(oa.seleccionado ? color : Color.clear)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(oa.seleccionado ? color : Color.gray, lineWidth: 2))
                        .overlay {
                            if oa.seleccionado {
                                Circle().fill(.white).frame(width: 5, height: 5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(etiquetaOA(oa))
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(color)
                        if oa.tipo == "oat" {
                            Text("Transversal")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(.purple)
                        } else if oa.esPropio == true {
                            Text("Propio")
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(EPTheme.primary.opacity(0.12), in: Capsule())
                                .foregroundStyle(EPTheme.primary)
                        }
                    }

                    TextField("Descripci\u{00F3}n del objetivo", text: bindingDescripcion(oa.id), axis: .vertical)
                        .font(.system(size: 12.5))
                        .lineLimit(1...4)

                    Button {
                        toggleExpand(oa.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expandido ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .black))
                            Text(oa.indicadores.isEmpty ? "Agregar indicadores" : "\(seleccionados)/\(oa.indicadores.count) indicadores")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }

                if oa.esPropio == true {
                    Button {
                        oas.removeAll { $0.id == oa.id }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            if expandido {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(oa.indicadores) { indicador in
                        indicadorFila(oaId: oa.id, color: color, indicador: indicador)
                    }
                    HStack(spacing: 8) {
                        TextField("Agregar indicador propio...", text: bindingNuevoIndicador(oa.id))
                            .font(.system(size: 11.5))
                            .padding(7)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .onSubmit { agregarIndicador(oaId: oa.id) }
                        Button {
                            agregarIndicador(oaId: oa.id)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(EPTheme.primary)
                                .frame(width: 30, height: 30)
                                .background(EPTheme.primary.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6).opacity(0.5))
            }
        }
        .background(EPTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 1)
        )
        .opacity(oa.seleccionado ? 1 : 0.55)
    }

    private func indicadorFila(oaId: String, color: Color, indicador: IndicadorEditado) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                actualizarIndicador(oaId: oaId, indicadorId: indicador.id) { $0.seleccionado.toggle() }
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(indicador.seleccionado ? color : Color.clear)
                    .frame(width: 15, height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(indicador.seleccionado ? color : Color.gray, lineWidth: 2))
                    .overlay {
                        if indicador.seleccionado {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            TextField("Indicador", text: bindingIndicadorTexto(oaId: oaId, indicadorId: indicador.id), axis: .vertical)
                .font(.system(size: 11.5))
                .lineLimit(1...3)
                .strikethrough(!indicador.seleccionado)
                .foregroundStyle(indicador.seleccionado ? .primary : .secondary)

            if indicador.esPropio == true {
                Button {
                    actualizarOA(oaId) { $0.indicadores.removeAll { $0.id == indicador.id } }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var nuevoOASection: some View {
        Group {
            if mostrarNuevoOA {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Nuevo objetivo propio")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Tipo", selection: $nuevoOATipo) {
                            Text("OA").tag("oa")
                            Text("OAA").tag("oat")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                    }
                    HStack(spacing: 8) {
                        Text("N\u{00FA}mero (opcional)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("Ej: 5", text: $nuevoOANumero)
                            .keyboardType(.numberPad)
                            .font(.system(size: 12))
                            .frame(width: 60)
                            .padding(7)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    TextField("Descripci\u{00F3}n del objetivo...", text: $nuevoOATexto, axis: .vertical)
                        .font(.system(size: 12.5))
                        .lineLimit(2...4)
                        .padding(8)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    HStack(spacing: 8) {
                        Button {
                            agregarOA()
                        } label: {
                            Text("Agregar \(nuevoOATipo == "oat" ? "OAA" : "OA")")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(nuevoOATipo == "oat" ? Color.purple : EPTheme.primary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            resetNuevoOA()
                        } label: {
                            Text("Cancelar")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color(.systemGray6), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EPTheme.primary.opacity(0.3), lineWidth: 1)
                )
            } else {
                Button {
                    mostrarNuevoOA = true
                } label: {
                    Label("Agregar OA propio", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(Color(.separator))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Mutaciones

    private func toggleExpand(_ id: String) {
        if expandidos.contains(id) { expandidos.remove(id) } else { expandidos.insert(id) }
    }

    private func actualizarOA(_ id: String, _ transform: (inout OAEditado) -> Void) {
        guard let index = oas.firstIndex(where: { $0.id == id }) else { return }
        transform(&oas[index])
    }

    private func actualizarIndicador(oaId: String, indicadorId: String, _ transform: (inout IndicadorEditado) -> Void) {
        actualizarOA(oaId) { oa in
            if let index = oa.indicadores.firstIndex(where: { $0.id == indicadorId }) {
                transform(&oa.indicadores[index])
            }
        }
    }

    private func agregarIndicador(oaId: String) {
        let texto = (nuevoIndicadorTexto[oaId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        actualizarOA(oaId) { $0.indicadores.append(CurriculoOA.nuevoIndicadorPropio(oaId: oaId, texto: texto)) }
        nuevoIndicadorTexto[oaId] = ""
    }

    private func agregarOA() {
        let texto = nuevoOATexto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        let numero = Int(nuevoOANumero.trimmingCharacters(in: .whitespacesAndNewlines))
        let nuevo = CurriculoOA.nuevoOAPropio(numero: numero.flatMap { $0 > 0 ? $0 : nil }, tipo: nuevoOATipo, descripcion: texto, asignatura: asignatura)
        oas.append(nuevo)
        expandidos.insert(nuevo.id)
        resetNuevoOA()
    }

    private func resetNuevoOA() {
        mostrarNuevoOA = false
        nuevoOATexto = ""
        nuevoOANumero = ""
        nuevoOATipo = "oa"
    }

    // MARK: - Bindings

    private func bindingDescripcion(_ id: String) -> Binding<String> {
        Binding(
            get: { oas.first { $0.id == id }?.descripcion ?? "" },
            set: { nuevo in actualizarOA(id) { $0.descripcion = nuevo } }
        )
    }

    private func bindingNuevoIndicador(_ oaId: String) -> Binding<String> {
        Binding(
            get: { nuevoIndicadorTexto[oaId] ?? "" },
            set: { nuevoIndicadorTexto[oaId] = $0 }
        )
    }

    private func bindingIndicadorTexto(oaId: String, indicadorId: String) -> Binding<String> {
        Binding(
            get: { oas.first { $0.id == oaId }?.indicadores.first { $0.id == indicadorId }?.texto ?? "" },
            set: { nuevo in actualizarIndicador(oaId: oaId, indicadorId: indicadorId) { $0.texto = nuevo } }
        )
    }
}

extension Color {
    init(hex6: UInt32) {
        self.init(
            red: Double((hex6 >> 16) & 0xFF) / 255,
            green: Double((hex6 >> 8) & 0xFF) / 255,
            blue: Double(hex6 & 0xFF) / 255
        )
    }
}
