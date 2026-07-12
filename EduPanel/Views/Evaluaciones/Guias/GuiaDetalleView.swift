import SwiftUI

struct GuiaDetalleView: View {
    let guiaId: String
    let scope: EvaluacionScope
    let repository: EvaluacionesRepository
    let dashboardRepository: DashboardRepository

    @State private var guide: GuiaTemplate?
    @State private var school: InfoColegio = .empty
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var exportArtifact: GuiaPDFArtifact?
    @State private var exportingMode: GuiaPDFMode?
    @State private var exportErrorMessage: String?

    private let pdfExporter = GuiaPDFExporter()

    private var title: String {
        guard let name = guide?.nombre, !name.isEmpty else { return "Detalle de guía" }
        return name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && guide == nil {
                    EvaluacionesLoadingCard(texto: "Cargando guía...")
                } else if let errorMessage, guide == nil {
                    EvaluacionesRetryCard(title: "No se pudo abrir la guía", message: errorMessage, isLoading: isLoading) {
                        Task { await load() }
                    }
                } else if let guide {
                    content(guide)
                }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 28)
        }
        .background(EPTheme.background)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let guide {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        GuiaPDFExportActions(templates: school.guideExportTemplates) { mode, format in
                            beginExport(mode, formatOverride: format)
                        }
                    } label: {
                        if exportingMode != nil { ProgressView() }
                        else { Label("Exportar", systemImage: "square.and.arrow.up") }
                    }
                    .disabled(exportingMode != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.guiaEditor(
                        guiaId: guide.id,
                        curso: guide.curso,
                        asignatura: guide.asignatura,
                        scope: guide.scope
                    )) {
                        Label("Editar", systemImage: "pencil")
                    }
                }
            }
        }
        .sheet(item: $exportArtifact) { artifact in
            GuiaPDFShareSheet(artifact: artifact)
        }
        .alert("No se pudo exportar", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "Error desconocido")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func content(_ guide: GuiaTemplate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            EPModuleHeader(
                eyebrow: [guide.numeroGuia ?? "Guía", guide.curso].filter { !$0.isEmpty }.joined(separator: " · "),
                title: guide.nombre.isEmpty ? "Guía sin nombre" : guide.nombre,
                subtitle: [guide.asignatura, guide.unidadNombre ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                icon: "book.pages.fill", accent: .evaluaciones
            )

            HStack(spacing: 7) {
                EPStatusPill(text: typeName(guide.tipoGuia), icon: "book.closed.fill")
                EPStatusPill(text: statusName(guide.estado), icon: guide.estado == "lista" ? "checkmark.circle.fill" : "pencil.circle")
                if case .colegio(_) = guide.scope { EPStatusPill(text: "Colegio activo", icon: "building.2.fill") }
            }

            if guide.isFromCache {
                notice(icon: "icloud.slash.fill", title: "Contenido disponible sin conexión",
                       message: "Puede no incluir los cambios más recientes de la web.", tint: .orange)
            }
            if guide.tieneContenidoDesconocido || !guide.issues.isEmpty {
                notice(icon: "exclamationmark.triangle.fill", title: "Compatibilidad conservada",
                       message: "Hay contenido heredado o futuro. iOS lo mantiene intacto y muestra lo que reconoce.", tint: .orange)
            }

            summary(guide)

            if !guide.objetivo.isEmpty {
                sectionCard(title: "Objetivo", icon: "scope") {
                    Text(guide.objetivo).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !guide.instrucciones.isEmpty {
                sectionCard(title: "Instrucciones", icon: "list.number") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(guide.instrucciones.enumerated()), id: \.offset) { index, instruction in
                            Label(instruction, systemImage: "\(index + 1).circle.fill")
                                .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            curriculum(guide)

            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Contenido de la guía",
                                subtitle: "\(guide.secciones.count) secciones · \(guide.totalActividades) actividades",
                                icon: "rectangle.3.group.fill")
                ForEach(guide.secciones) { section in GuiaSectionView(section: section) }
            }

            if !guide.cierre.isEmpty {
                sectionCard(title: "Cierre y reflexión", icon: "checkmark.seal.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(guide.cierre) { PruebaContentBlockView(block: $0) }
                    }
                }
            }
        }
    }

    private func summary(_ guide: GuiaTemplate) -> some View {
        EPWebCard {
            HStack(spacing: 8) {
                metric("Secciones", "\(guide.secciones.count)", .purple)
                metric("Actividades", "\(guide.totalActividades)", .orange)
                metric("Bloques", "\(guide.totalBloques)", .blue)
                metric("Puntaje", guide.puntajeMaximo > 0 ? score(guide.puntajeMaximo) : "—", .green)
                if let minutes = guide.tiempoMinutos { metric("Minutos", "\(minutes)", EPTheme.rose) }
            }
        }
    }

    @ViewBuilder
    private func curriculum(_ guide: GuiaTemplate) -> some View {
        let hasContent = !guide.objetivos.isEmpty || !guide.indicadores.isEmpty || !guide.objetivosTransversales.isEmpty
        if hasContent {
            sectionCard(title: "Vinculación curricular", icon: "graduationcap.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    curriculumRows("Objetivos", guide.objetivos, .blue)
                    curriculumRows("Indicadores", guide.indicadores, .purple)
                    curriculumRows("Transversales", guide.objetivosTransversales, .green)
                }
            }
        }
    }

    @ViewBuilder
    private func curriculumRows(_ title: String, _ values: [String], _ tint: Color) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.weight(.black)).foregroundStyle(tint)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text("• \(value)").font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon).font(.subheadline.weight(.black)).foregroundStyle(EPTheme.primary)
                content()
            }
        }
    }

    private func metric(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.black)).foregroundStyle(tint)
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notice(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.black))
                Text(message).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            async let guideTask = repository.cargarGuia(id: guiaId, scope: scope)
            async let schoolTask: InfoColegio? = try? await dashboardRepository.fetchExportSchool(scope: scope)
            guard let loaded = try await guideTask else {
                errorMessage = "La guía ya no existe o no pertenece al colegio activo."
                return
            }
            guide = loaded
            if let exportSchool = await schoolTask { school = exportSchool }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginExport(_ mode: GuiaPDFMode, formatOverride: ExportFormat? = nil) {
        Task { await export(mode, formatOverride: formatOverride) }
    }

    private func export(_ mode: GuiaPDFMode, formatOverride: ExportFormat?) async {
        guard let guide, exportingMode == nil else { return }
        exportingMode = mode
        exportErrorMessage = nil
        defer { exportingMode = nil }
        do {
            exportArtifact = try await pdfExporter.export(
                guide: guide,
                school: school,
                teacherName: guide.docenteNombre,
                mode: mode,
                formatOverride: formatOverride
            )
        } catch is CancellationError {
            return
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func score(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func typeName(_ value: String) -> String {
        switch value { case "refuerzo": return "Refuerzo"; case "ejercitacion": return "Ejercitación";
        case "evaluacion_formativa": return "Evaluación formativa"; default: return "Aprendizaje" }
    }
    private func statusName(_ value: String) -> String {
        switch value { case "lista": return "Lista"; case "archivada": return "Archivada"; default: return "Borrador" }
    }
}

private struct GuiaSectionView: View {
    let section: GuiaSeccion

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.titulo).font(.headline.weight(.black))
                    if let description = section.descripcion, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(section.contenido) { PruebaContentBlockView(block: $0) }
                if !section.contenido.isEmpty && !section.actividades.isEmpty { Divider() }
                ForEach(section.actividades) { GuiaActividadView(activity: $0) }
            }
        }
    }
}

private struct GuiaActividadView: View {
    let activity: GuiaActividad

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(activity.numero)").font(.caption.weight(.black)).foregroundStyle(EPTheme.rose)
                    .frame(width: 24, height: 24).background(EPTheme.rose.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(activity.kind.label).font(.caption2.weight(.black)).foregroundStyle(EPTheme.primary)
                        Spacer()
                        if let points = activity.puntaje { Text("\(score(points)) pts").font(.caption.weight(.black)) }
                    }
                    if !activity.enunciado.isEmpty {
                        Text(activity.enunciado).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let oa = activity.oaVinculado, !oa.isEmpty {
                        Label(oa, systemImage: "graduationcap.fill").font(.caption2.weight(.bold)).foregroundStyle(.blue)
                    }
                }
            }
            ForEach(activity.recursos) { PruebaContentBlockView(block: $0) }
            activityBody
        }
        .padding(11).background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(EPTheme.border))
    }

    @ViewBuilder
    private var activityBody: some View {
        switch activity.kind {
        case .seleccionMultiple, .encerrar, .marcar:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(activity.opciones) { option in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: symbol(option.correcta)).foregroundStyle(option.correcta == true ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(option.texto.isEmpty ? "Opción sin texto" : option.texto).font(.caption.weight(.semibold))
                            if let image = option.imagenUrl { PruebaRemoteImage(urlString: image, alt: option.texto) }
                        }
                    }
                }
            }
        case .verdaderoFalso:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(activity.afirmaciones) { item in
                    Label(item.texto, systemImage: item.correcta == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(item.correcta == true ? .green : .red)
                }
            }
        case .completar:
            VStack(alignment: .leading, spacing: 6) {
                if let text = activity.textoCompletar { Text(text).font(.caption.weight(.semibold)) }
                chips(title: "Respuestas", values: activity.respuestas)
                chips(title: "Banco", values: activity.banco)
            }
        case .respuestaCorta, .abierta:
            answerSpace(lines: activity.lineas ?? 3, hint: activity.respuestaSugerida)
        case .ordenar:
            VStack(alignment: .leading, spacing: 5) {
                ForEach(activity.pasos) { step in Label(step.texto, systemImage: "\(step.numeroCorrecto ?? 0).circle.fill").font(.caption) }
            }
        case .pareados:
            HStack(alignment: .top, spacing: 12) { pairColumn("A", activity.columnaA); pairColumn("B", activity.columnaB) }
        case .colorear:
            instruction(activity.instruccion)
            if let image = activity.imagenUrl {
                PruebaRemoteImage(urlString: image, alt: activity.instruccion ?? "Imagen para colorear")
            }
        case .dibujar:
            instruction(activity.instruccion)
            drawingBox(height: CGFloat(max(100, (activity.alturaCm ?? 5) * 18)))
        case .investigar:
            instruction(activity.instruccion)
            answerSpace(lines: activity.lineas ?? 6, hint: nil)
        case .sopaLetras:
            chips(title: "Palabras", values: activity.palabras)
            if let size = activity.tamanoCuadro { Text("Cuadrícula sugerida: \(size) × \(size)").font(.caption2).foregroundStyle(.secondary) }
        case .desconocida:
            Label("Este tipo se conserva intacto para no perder información.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private func instruction(_ value: String?) -> some View {
        if let value, !value.isEmpty { Text(value).font(.caption.weight(.semibold)) }
    }
    private func drawingBox(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.secondary.opacity(0.5))
            .frame(height: height).overlay(Text("Espacio de trabajo").font(.caption2).foregroundStyle(.tertiary))
    }
    private func answerSpace(lines: Int, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<max(1, min(lines, 12)), id: \.self) { _ in Divider() }
            if let hint, !hint.isEmpty { Text("Respuesta sugerida: \(hint)").font(.caption2).foregroundStyle(.green) }
        }
    }
    @ViewBuilder private func chips(title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption2.weight(.black)).foregroundStyle(.secondary)
                Text(values.joined(separator: " · ")).font(.caption.weight(.semibold))
            }
        }
    }
    private func pairColumn(_ title: String, _ values: [GuiaPareado]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Columna \(title)").font(.caption2.weight(.black)).foregroundStyle(EPTheme.primary)
            ForEach(values) { Text($0.texto).font(.caption).padding(5).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6)) }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private func symbol(_ correct: Bool?) -> String {
        if correct == true { return "checkmark.circle.fill" }
        return activity.kind == .marcar ? "xmark.square" : (activity.kind == .encerrar ? "circle" : "circle")
    }
    private func score(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}
