import SwiftUI

struct VerUnidadClasesView: View {
    var viewModel: VerUnidadViewModel

    @State private var selectedClassNum = 1
    @State private var showingLiveMode = false
    @State private var newMaterial = ""
    @State private var newTic = ""

    var body: some View {
        VStack(spacing: 0) {
            classSelectorRail

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    classHeaderCard
                    objectivesCard
                    editorFields
                    resourcesSection
                    placeholdersCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            normalizeSelectedClass()
        }
        .sheet(isPresented: $showingLiveMode) {
            if let act = viewModel.clasesActividades[selectedClassNum] {
                LiveClassModeView(
                    actividad: act,
                    students: getStudents(),
                    dashboardRepository: viewModel.planificacionRepository
                )
            }
        }
    }

    private var classSelectorRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(classNumbers, id: \.self) { cNum in
                    let isSelected = selectedClassNum == cNum
                    let hasData = isClassPlanificable(classNum: cNum)
                    Button {
                        selectedClassNum = cNum
                    } label: {
                        HStack(spacing: 5) {
                            Text("Clase \(cNum)")
                                .font(.caption.weight(.black))
                            if hasData {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .foregroundStyle(isSelected ? .white : EPTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? EPTheme.primary : EPTheme.card, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color(.separator).opacity(isSelected ? 0 : 0.16), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(EPTheme.card)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.16))
                .frame(height: 1)
        }
    }

    private var classHeaderCard: some View {
        let act = activeActivity
        let dateLabel = act.fecha.isEmpty ? "Fecha no programada" : "Programada: \(act.fecha)"

        return EPWebCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DETALLE DE LA JORNADA")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(EPTheme.primary)
                    Text("Clase \(selectedClassNum): Plan de aula")
                        .font(.headline.weight(.black))
                    Text(dateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Estado", selection: activeActivityBinding.estado) {
                        Text("No planificada").tag("no_planificada")
                        Text("Planificada").tag("planificada")
                        Text("Realizada").tag("realizada")
                    }
                    .pickerStyle(.menu)
                    .font(.caption.weight(.black))
                }

                Spacer(minLength: 8)

                Button {
                    showingLiveMode = true
                } label: {
                    Label("Clase en vivo", systemImage: "play.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(EPTheme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var objectivesCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Objetivos vinculados", subtitle: "Vienen de la matriz del cronograma.", icon: "tag.fill")

                let linked = linkedOAs
                if linked.isEmpty {
                    Label("Esta clase todavía no tiene OA asignados.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ForEach(linked, id: \.id) { oa in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(oa.numero != nil ? "OA \(oa.numero!)" : oa.id)
                                .font(.subheadline.weight(.black))
                            Text(oa.descripcion)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            let selectedIndicators = oa.indicadores.filter(\.seleccionado)
                            if !selectedIndicators.isEmpty {
                                ReplicaFlowLayout(spacing: 6) {
                                    ForEach(selectedIndicators) { indicador in
                                        Text(indicador.texto)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(EPTheme.primary)
                                            .lineLimit(2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(EPTheme.primary.opacity(0.1), in: Capsule())
                                    }
                                }
                            }
                        }
                        .padding(11)
                        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
        }
    }

    private var editorFields: some View {
        let binding = activeActivityBinding

        return EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Planificación diaria", subtitle: "Campos rich text compatibles con Quill/HTML simple.", icon: "square.and.pencil")

                RichTextEditor(
                    title: "Objetivo de aprendizaje de la clase",
                    placeholder: "Crear un primer boceto de paisaje sonoro...",
                    html: binding.objetivo,
                    minHeight: 84
                )

                RichTextEditor(
                    title: "Contexto de la clase",
                    placeholder: "Notas pedagógicas, agrupamientos, apoyos o alertas...",
                    html: binding.contextoProfesor.toNonOptional(),
                    minHeight: 76
                )

                Divider()

                RichTextEditor(
                    title: "Momento 1: Inicio",
                    placeholder: "Activación de conocimientos, pregunta inicial, motivación...",
                    html: binding.inicio,
                    minHeight: 92
                )

                RichTextEditor(
                    title: "Momento 2: Desarrollo",
                    placeholder: "Actividad principal, pasos, agrupamientos y mediación docente...",
                    html: binding.desarrollo,
                    minHeight: 118
                )

                RichTextEditor(
                    title: "Momento 3: Cierre",
                    placeholder: "Metacognición, evidencia final o ticket de salida...",
                    html: binding.cierre,
                    minHeight: 92
                )

                Divider()

                RichTextEditor(
                    title: "Adecuación curricular",
                    placeholder: "Estrategias PIE / DUA, apoyos, multinivel o ajustes...",
                    html: binding.adecuacion,
                    minHeight: 92
                )
            }
        }
    }

    private var resourcesSection: some View {
        let binding = activeActivityBinding

        return EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                EPSectionHeader(title: "Recursos y materiales de clase", subtitle: "Mantiene chips editables como la web.", icon: "tray.full.fill")

                chipEditor(
                    title: "Materiales físicos",
                    placeholder: "Añadir material...",
                    text: $newMaterial,
                    items: binding.wrappedValue.materiales,
                    tint: .blue,
                    onAdd: { value in
                        viewModel.clasesActividades[selectedClassNum]?.materiales.append(value)
                    },
                    onRemove: { value in
                        viewModel.clasesActividades[selectedClassNum]?.materiales.removeAll { $0 == value }
                    }
                )

                Divider()

                chipEditor(
                    title: "Herramientas TIC",
                    placeholder: "Añadir TIC...",
                    text: $newTic,
                    items: binding.wrappedValue.tics,
                    tint: .purple,
                    onAdd: { value in
                        viewModel.clasesActividades[selectedClassNum]?.tics.append(value)
                    },
                    onRemove: { value in
                        viewModel.clasesActividades[selectedClassNum]?.tics.removeAll { $0 == value }
                    }
                )

                if let archivos = binding.wrappedValue.archivos, !archivos.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Archivos")
                            .font(.caption.weight(.black))
                        ForEach(archivos) { archivo in
                            Label(archivo.nombre, systemImage: "paperclip")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var placeholdersCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Apoyos IA y Drive", subtitle: "Visible como estructura nativa, sin WebView.", icon: "sparkles")
                HStack(spacing: 8) {
                    EPPlaceholderActionButton(title: "Sugerir mejoras", icon: "wand.and.stars", message: "La asistencia IA se conectará después de cerrar la réplica base.")
                    EPPlaceholderActionButton(title: "Adjuntar Drive", icon: "externaldrive.fill", message: "El selector Drive queda pendiente de conexión nativa.")
                }
            }
        }
    }

    private func chipEditor(
        title: String,
        placeholder: String,
        text: Binding<String>,
        items: [String],
        tint: Color,
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.black))

            if items.isEmpty {
                Text("Sin elementos agregados.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ReplicaFlowLayout(spacing: 7) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.black))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.11), in: Capsule())
                            .onLongPressGesture {
                                onRemove(item)
                            }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .font(.caption.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
                Button {
                    let value = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    onAdd(value)
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var classNumbers: [Int] {
        guard let crono = viewModel.cronograma else { return [1] }
        let maxNumber = max(crono.totalClases, crono.clases.map(\.numero).max() ?? 0)
        return maxNumber > 0 ? Array(1...maxNumber) : [1]
    }

    private var linkedOAs: [OAEditado] {
        guard let verUnidad = viewModel.verUnidad else { return [] }
        let ids = Set(activeActivity.oaIds)
        return verUnidad.oas.filter { ids.contains($0.id) }
    }

    private var activeActivity: ActividadClase {
        viewModel.clasesActividades[selectedClassNum] ?? ActividadClase(
            id: PlanificacionRepository.buildActividadClaseId(
                curso: viewModel.curso,
                unidadId: viewModel.unidadId,
                numeroClase: selectedClassNum,
                asignatura: viewModel.activeSubject
            ),
            asignatura: viewModel.activeSubject,
            curso: viewModel.curso,
            unidadId: viewModel.unidadId,
            numeroClase: selectedClassNum,
            fecha: viewModel.cronograma?.clases.first(where: { $0.numero == selectedClassNum })?.fecha ?? "",
            oaIds: viewModel.cronograma?.clases.first(where: { $0.numero == selectedClassNum })?.oaIds ?? [],
            objetivo: "",
            inicio: "",
            desarrollo: "",
            cierre: "",
            adecuacion: "",
            habilidades: [],
            actitudes: [],
            materiales: [],
            tics: [],
            estado: "no_planificada",
            sincronizada: false
        )
    }

    private var activeActivityBinding: Binding<ActividadClase> {
        Binding(
            get: {
                activeActivity
            },
            set: { newValue in
                viewModel.clasesActividades[selectedClassNum] = newValue
            }
        )
    }

    private func normalizeSelectedClass() {
        if !classNumbers.contains(selectedClassNum) {
            selectedClassNum = classNumbers.first ?? 1
        }
        if viewModel.clasesActividades[selectedClassNum] == nil {
            viewModel.clasesActividades[selectedClassNum] = activeActivity
        }
    }

    private func isClassPlanificable(classNum: Int) -> Bool {
        guard let act = viewModel.clasesActividades[classNum] else { return false }
        return !RichTextHTML.plainText(from: act.objetivo).isEmpty ||
        !RichTextHTML.plainText(from: act.inicio).isEmpty ||
        !RichTextHTML.plainText(from: act.desarrollo).isEmpty
    }

    private func getStudents() -> [EstudiantePerfil] {
        viewModel.snapshot?.studentsByCourse[viewModel.curso] ?? []
    }
}

private extension Binding where Value == Optional<String> {
    func toNonOptional() -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0 }
        )
    }
}
