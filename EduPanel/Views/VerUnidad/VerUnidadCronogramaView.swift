import SwiftUI

struct VerUnidadCronogramaView: View {
    var viewModel: VerUnidadViewModel
    @Binding var selectedTab: String

    @State private var isMatrixMode = true
    @State private var classToEditOas: ClaseCronograma? = nil
    @State private var showingOaSheet = false

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        if let crono = viewModel.cronograma {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controlsCard(crono)
                    if !displayMode.isSimple {
                        coverageCard(crono)
                    }

                    if isMatrixMode {
                        matrixEditor(crono)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        sequenceList(crono)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .sheet(isPresented: $showingOaSheet) {
                if let cl = classToEditOas {
                    oaSelectorSheet(for: cl)
                        .presentationDetents([.medium, .large])
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func controlsCard(_ crono: CronogramaUnidadData) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Cronograma de unidad", subtitle: "\(safeClassNumbers(crono).count) clases y \(selectedOAs.count) OA activos.", icon: "calendar")

                HStack(spacing: 8) {
                    Button {
                        Task { await viewModel.calculateDatesFromSchedule() }
                    } label: {
                        Label("Calcular fechas", systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.black))
                            .foregroundStyle(EPTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(EPTheme.primary.opacity(0.1), in: Capsule())
                    }

                    Button {
                        withAnimation(EPTheme.spring) {
                            isMatrixMode.toggle()
                        }
                    } label: {
                        Label(isMatrixMode ? "Vista secuencia" : "Vista matriz", systemImage: isMatrixMode ? "list.bullet" : "grid")
                            .font(.caption.weight(.black))
                            .foregroundStyle(EPTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(EPTheme.primary.opacity(0.1), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func coverageCard(_ crono: CronogramaUnidadData) -> some View {
        let total = safeClassNumbers(crono).count
        let withOAs = crono.clases.filter { !$0.oaIds.isEmpty }.count
        let percent = total > 0 ? Int((Double(withOAs) / Double(total)) * 100) : 0
        let unassigned = max(0, total - withOAs)

        return EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Resumen de cobertura", subtitle: "Asignación de OA por clase.", icon: "checkmark.seal.fill")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    EPKPIBox(title: "Clases", value: "\(total)", subtitle: "en secuencia", icon: "number.square.fill", tint: .blue)
                    EPKPIBox(title: "Con OA", value: "\(withOAs)", subtitle: "clases cubiertas", icon: "checkmark.circle.fill", tint: .green)
                    EPKPIBox(title: "Sin OA", value: "\(unassigned)", subtitle: "por asignar", icon: "exclamationmark.triangle.fill", tint: .orange)
                    EPKPIBox(title: "Cobertura", value: "\(percent)%", subtitle: "avance matriz", icon: "chart.bar.fill", tint: percent >= 80 ? .green : EPTheme.primary)
                }

                if unassigned > 0 {
                    Label("\(unassigned) clases aún no tienen OA asignados.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func sequenceList(_ crono: CronogramaUnidadData) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(crono.clases.sorted { $0.numero < $1.numero }.enumerated()), id: \.element.numero) { _, clase in
                claseRow(clase)
            }
        }
    }

    private func claseRow(_ clase: ClaseCronograma) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clase \(clase.numero)")
                            .font(.headline.weight(.black))
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.secondary)
                            TextField("DD/MM/YYYY", text: Binding(
                                get: { viewModel.cronograma?.clases.first(where: { $0.numero == clase.numero })?.fecha ?? clase.fecha },
                                set: { value in
                                    if let idx = viewModel.cronograma?.clases.firstIndex(where: { $0.numero == clase.numero }) {
                                        viewModel.cronograma?.clases[idx].fecha = value
                                    }
                                }
                            ))
                            .font(.caption.weight(.semibold))
                            .textFieldStyle(.plain)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            classToEditOas = clase
                            showingOaSheet = true
                        } label: {
                            actionLabel("OAs", icon: "tag")
                        }

                        Button {
                            selectedTab = "clases"
                        } label: {
                            actionLabel("Planificar", icon: "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)
                }

                if clase.oaIds.isEmpty {
                    EPStatusPill(text: "Sin OA asignado", icon: "exclamationmark.triangle.fill", tint: .orange)
                } else {
                    ReplicaFlowLayout(spacing: 6) {
                        ForEach(clase.oaIds, id: \.self) { oaId in
                            EPStatusPill(text: oaId, icon: "checkmark", tint: EPTheme.primary)
                        }
                    }
                }
            }
        }
    }

    private func matrixEditor(_ crono: CronogramaUnidadData) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Matriz de distribución curricular", subtitle: "Toca una celda para asignar o quitar OA.", icon: "grid")

                if selectedOAs.isEmpty {
                    Text("Habilita objetivos de aprendizaje en la pestaña Unidad primero.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 0) {
                                Text("Objetivo")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 116, alignment: .leading)

                                ForEach(safeClassNumbers(crono), id: \.self) { cNum in
                                    Text("C\(cNum)")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 42)
                                }
                            }

                            ForEach(selectedOAs, id: \.id) { oa in
                                HStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                            .font(.caption.weight(.black))
                                        Text(oa.descripcion)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .frame(width: 116, alignment: .leading)

                                    ForEach(safeClassNumbers(crono), id: \.self) { cNum in
                                        let isAssigned = isOaAssigned(oaId: oa.id, classNum: cNum)
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                toggleOaAssignment(oaId: oa.id, classNum: cNum)
                                            }
                                        } label: {
                                            Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                                .font(.body.weight(.bold))
                                                .foregroundStyle(isAssigned ? EPTheme.primary : Color(.separator))
                                                .frame(width: 42, height: 34)
                                                .contentTransition(.symbolEffect(.replace))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6).opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
        }
    }

    private func oaSelectorSheet(for clase: ClaseCronograma) -> some View {
        NavigationStack {
            List {
                if selectedOAs.isEmpty {
                    Text("No hay OAs seleccionados en esta unidad.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedOAs, id: \.id) { oa in
                        let isChecked = classToEditOas?.oaIds.contains(oa.id) ?? false
                        Button {
                            toggleSheetOa(oaId: oa.id)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                        .font(.subheadline.weight(.black))
                                    Text(oa.descripcion)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                Spacer()
                                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isChecked ? EPTheme.primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Asignar OAs a clase \(clase.numero)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        if let updated = classToEditOas,
                           let idx = viewModel.cronograma?.clases.firstIndex(where: { $0.numero == updated.numero }) {
                            viewModel.cronograma?.clases[idx].oaIds = updated.oaIds
                            Task { await viewModel.saveAll() }
                        }
                        showingOaSheet = false
                    }
                }
            }
        }
    }

    private var selectedOAs: [OAEditado] {
        viewModel.verUnidad?.oas.filter(\.seleccionado) ?? []
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(EPTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(EPTheme.primary.opacity(0.1), in: Capsule())
    }

    private func safeClassNumbers(_ crono: CronogramaUnidadData) -> [Int] {
        let maxNumber = max(crono.totalClases, crono.clases.map(\.numero).max() ?? 0)
        guard maxNumber > 0 else { return [] }
        return Array(1...maxNumber)
    }

    private func isOaAssigned(oaId: String, classNum: Int) -> Bool {
        viewModel.cronograma?.clases.first(where: { $0.numero == classNum })?.oaIds.contains(oaId) ?? false
    }

    private func toggleOaAssignment(oaId: String, classNum: Int) {
        guard var crono = viewModel.cronograma else { return }

        if let idx = crono.clases.firstIndex(where: { $0.numero == classNum }) {
            if crono.clases[idx].oaIds.contains(oaId) {
                crono.clases[idx].oaIds.removeAll { $0 == oaId }
            } else {
                crono.clases[idx].oaIds.append(oaId)
            }
        } else {
            crono.clases.append(ClaseCronograma(numero: classNum, fecha: "", oaIds: [oaId]))
            crono.totalClases = max(crono.totalClases, classNum)
        }

        viewModel.cronograma = crono
        Task { await viewModel.saveAll() }
    }

    private func toggleSheetOa(oaId: String) {
        guard var clase = classToEditOas else { return }
        if clase.oaIds.contains(oaId) {
            clase.oaIds.removeAll { $0 == oaId }
        } else {
            clase.oaIds.append(oaId)
        }
        classToEditOas = clase
    }
}
