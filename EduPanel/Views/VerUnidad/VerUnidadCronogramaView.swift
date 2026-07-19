import SwiftUI

struct VerUnidadCronogramaView: View {
    var viewModel: VerUnidadViewModel
    @Binding var selectedTab: String

    @State private var isMatrixMode = true
    @State private var classToEditOas: ClaseCronograma? = nil

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        if let crono = viewModel.cronograma {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
            .reportsTabBarScroll()
            .sheet(item: $classToEditOas) { selectedClass in
                oaSelectorSheet(for: selectedClass)
                    .presentationDetents([.medium, .large])
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

                Stepper(value: clasesBinding(crono), in: clasesMinimas(crono)...60) {
                    HStack(spacing: 7) {
                        Text("Clases en secuencia")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(safeClassNumbers(crono).count)")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func clasesMinimas(_ crono: CronogramaUnidadData) -> Int {
        let conDatos = crono.clases
            .filter { !$0.fecha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.oaIds.isEmpty }
            .map(\.numero)
            .max() ?? 1
        return max(1, conDatos)
    }

    private func clasesBinding(_ crono: CronogramaUnidadData) -> Binding<Int> {
        Binding(
            get: { max(crono.totalClases, crono.clases.map(\.numero).max() ?? 0) },
            set: { nuevo in
                guard var actual = viewModel.cronograma else { return }
                actual.totalClases = nuevo
                actual.clases.removeAll { clase in
                    clase.numero > nuevo &&
                    clase.fecha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    clase.oaIds.isEmpty
                }
                viewModel.cronograma = actual
                Task { await viewModel.saveAll() }
            }
        )
    }

    private func coverageCard(_ crono: CronogramaUnidadData) -> some View {
        let total = safeClassNumbers(crono).count
        let withOAs = crono.clases.filter { !$0.oaIds.isEmpty }.count
        let percent = total > 0 ? Int((Double(withOAs) / Double(total)) * 100) : 0
        let unassigned = max(0, total - withOAs)

        return EPCollapsibleSection(title: "Resumen de cobertura", subtitle: "\(withOAs)/\(total) clases con OA · \(percent)%.", icon: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 12) {
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
                EPSectionHeader(
                    title: "Matriz de distribución curricular",
                    subtitle: "Toca una clase para revisar o cambiar sus objetivos.",
                    icon: "square.grid.2x2"
                )

                if selectedOAs.isEmpty {
                    Text("Habilita objetivos de aprendizaje en la pestaña Unidad primero.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(safeClassNumbers(crono), id: \.self) { classNumber in
                            let scheduledClass = distributionClass(classNumber, in: crono)
                            ClassDistributionTile(
                                scheduledClass: scheduledClass,
                                objectiveLabels: scheduledClass.oaIds.map(objectiveLabel),
                                onOpen: { classToEditOas = scheduledClass }
                            )
                        }
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
                        classToEditOas = nil
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

    private func distributionClass(_ classNumber: Int, in crono: CronogramaUnidadData) -> ClaseCronograma {
        crono.clases.first(where: { $0.numero == classNumber })
            ?? ClaseCronograma(numero: classNumber, fecha: "", oaIds: [])
    }

    private func objectiveLabel(_ objectiveID: String) -> String {
        if let objective = selectedOAs.first(where: { $0.id == objectiveID }) {
            if let number = objective.numero { return "OA \(number)" }
            let digits = objective.id.filter(\.isNumber)
            return digits.isEmpty ? objective.id.uppercased() : "OA \(digits)"
        }
        let digits = objectiveID.filter(\.isNumber)
        return digits.isEmpty ? objectiveID.uppercased() : "OA \(digits)"
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

private struct ClassDistributionTile: View {
    let scheduledClass: ClaseCronograma
    let objectiveLabels: [String]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Clase \(scheduledClass.numero)")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Text(scheduledClass.fecha.isEmpty ? "Sin fecha" : scheduledClass.fecha)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if objectiveLabels.isEmpty {
                    Label("Sin OA", systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(objectiveLabels.joined(separator: " · "))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(EPTheme.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(objectiveLabels.count == 1 ? "1 objetivo" : "\(objectiveLabels.count) objetivos")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clase \(scheduledClass.numero)")
        .accessibilityValue(
            objectiveLabels.isEmpty
                ? "Sin objetivos asignados"
                : objectiveLabels.joined(separator: ", ")
        )
        .accessibilityHint("Abre la selección de objetivos de esta clase")
    }
}
