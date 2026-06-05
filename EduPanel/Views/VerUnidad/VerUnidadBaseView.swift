import SwiftUI

struct VerUnidadBaseView: View {
    var viewModel: VerUnidadViewModel
    
    @State private var newHabilidad = ""
    @State private var newConocimiento = ""
    @State private var newActitud = ""

    var body: some View {
        if let verUnidad = viewModel.verUnidad {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // SECTION 1: FOCO PEDAGOGICO
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FOCO PEDAGÓGICO")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.1)
                        
                        // Propósito
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Propósito de la Unidad")
                                .font(.caption.bold())
                            TextEditor(text: Binding(
                                get: { verUnidad.descripcion },
                                set: { viewModel.verUnidad?.descripcion = $0 }
                            ))
                            .frame(minHeight: 80)
                            .padding(6)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        
                        // Contexto Docente
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Contexto Docente (Particularidades del curso)")
                                .font(.caption.bold())
                            TextEditor(text: Binding(
                                get: { verUnidad.contextoDocente },
                                set: { viewModel.verUnidad?.contextoDocente = $0 }
                            ))
                            .frame(minHeight: 70)
                            .padding(6)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        
                        // Meta Docente
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meta Docente (Objetivo del profesor)")
                                .font(.caption.bold())
                            TextEditor(text: Binding(
                                get: { verUnidad.objetivoDocente },
                                set: { viewModel.verUnidad?.objetivoDocente = $0 }
                            ))
                            .frame(minHeight: 70)
                            .padding(6)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                    // SECTION 2: OBJETIVOS DE APRENDIZAJE (OA)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("OBJETIVOS DE APRENDIZAJE PRIORIZADOS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.1)
                        
                        ForEach(Array(verUnidad.oas.enumerated()), id: \.element.id) { oIdx, oa in
                            VStack(alignment: .leading, spacing: 10) {
                                // OA Header Checkbox
                                Button {
                                    viewModel.verUnidad?.oas[oIdx].seleccionado.toggle()
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: oa.seleccionado ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(oa.seleccionado ? Color(hex: "#F03E6E") : .secondary)
                                            .font(.body)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(oa.numero != nil ? "OA \(oa.numero!)" : "Objetivo Propio")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(Color(.label))
                                            Text(oa.descripcion)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                if oa.seleccionado {
                                    // Indicators list
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Indicadores de Evaluación:")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 26)
                                        
                                        ForEach(Array(oa.indicadores.enumerated()), id: \.element.id) { iIdx, ind in
                                            Button {
                                                viewModel.verUnidad?.oas[oIdx].indicadores[iIdx].seleccionado.toggle()
                                            } label: {
                                                HStack(alignment: .top, spacing: 8) {
                                                    Image(systemName: ind.seleccionado ? "checkmark.circle.fill" : "circle")
                                                        .foregroundStyle(ind.seleccionado ? Color(hex: "#F03E6E").opacity(0.8) : .secondary)
                                                        .font(.footnote)
                                                    
                                                    Text(ind.texto)
                                                        .font(.caption)
                                                        .foregroundStyle(ind.seleccionado ? Color(.label) : .secondary)
                                                        .multilineTextAlignment(.leading)
                                                }
                                                .padding(.leading, 28)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(12)
                            .background(Color(.systemGray6).opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                    // SECTION 3: HABILIDADES, CONOCIMIENTOS, ACTITUDES
                    VStack(alignment: .leading, spacing: 16) {
                        Text("APRENDIZAJES ASOCIADOS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.1)
                        
                        // Habilidades
                        curriculumCategorySection(
                            title: "Habilidades",
                            items: verUnidad.habilidades,
                            newItemText: $newHabilidad,
                            onAdd: {
                                guard !newHabilidad.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                let newItem = ElementoCurricular(id: "hab_custom_\(Date().timeIntervalSince1970)", texto: newHabilidad, seleccionado: true, esPropio: true)
                                viewModel.verUnidad?.habilidades.append(newItem)
                                newHabilidad = ""
                            },
                            onToggle: { idx in
                                viewModel.verUnidad?.habilidades[idx].seleccionado.toggle()
                            }
                        )
                        
                        // Conocimientos
                        curriculumCategorySection(
                            title: "Conocimientos",
                            items: verUnidad.conocimientos,
                            newItemText: $newConocimiento,
                            onAdd: {
                                guard !newConocimiento.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                let newItem = ElementoCurricular(id: "con_custom_\(Date().timeIntervalSince1970)", texto: newConocimiento, seleccionado: true, esPropio: true)
                                viewModel.verUnidad?.conocimientos.append(newItem)
                                newConocimiento = ""
                            },
                            onToggle: { idx in
                                viewModel.verUnidad?.conocimientos[idx].seleccionado.toggle()
                            }
                        )
                        
                        // Actitudes
                        curriculumCategorySection(
                            title: "Actitudes",
                            items: verUnidad.actitudes,
                            newItemText: $newActitud,
                            onAdd: {
                                guard !newActitud.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                let newItem = ElementoCurricular(id: "act_custom_\(Date().timeIntervalSince1970)", texto: newActitud, seleccionado: true, esPropio: true)
                                viewModel.verUnidad?.actitudes.append(newItem)
                                newActitud = ""
                            },
                            onToggle: { idx in
                                viewModel.verUnidad?.actitudes[idx].seleccionado.toggle()
                            }
                        )
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        } else {
            ProgressView()
        }
    }
    
    private func curriculumCategorySection(
        title: String,
        items: [ElementoCurricular],
        newItemText: Binding<String>,
        onAdd: @escaping () -> Void,
        onToggle: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
            
            // Flow/List of chips
            FlowLayout(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        onToggle(idx)
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.texto)
                                .font(.caption2)
                            if item.seleccionado {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(item.seleccionado ? .white : Color(.label))
                        .background(item.seleccionado ? Color(hex: "#F03E6E") : Color(.systemGray5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Inline add field
            HStack(spacing: 8) {
                TextField("Agregar propio...", text: newItemText)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color(hex: "#F03E6E"), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(newItemText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(Color(.systemGray6).opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - FlowLayout Helper for wrapping chips
struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            maxHeightInRow = max(maxHeightInRow, size.height)
            currentX += size.width + spacing
        }
        height = currentY + maxHeightInRow
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            maxHeightInRow = max(maxHeightInRow, size.height)
            currentX += size.width + spacing
        }
    }
}

// Color Hex Helper (if not globally declared)
private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else {
            self = .pink
            return
        }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else {
            self = .pink
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
