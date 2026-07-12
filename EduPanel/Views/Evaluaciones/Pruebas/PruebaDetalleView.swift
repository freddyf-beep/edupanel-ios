import SwiftUI

struct PruebaDetalleView: View {
    let pruebaId: String
    let scope: EvaluacionScope
    let repository: EvaluacionesRepository

    @State private var test: PruebaTemplate?
    @State private var application: PruebaAplicacion?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var applicationErrorMessage: String?

    private var navigationTitleText: String {
        guard let name = test?.nombre, !name.isEmpty else {
            return "Detalle de prueba"
        }
        return name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && test == nil {
                    EvaluacionesLoadingCard(texto: "Cargando detalle de la prueba...")
                } else if let errorMessage, test == nil {
                    EvaluacionesRetryCard(
                        title: "No se pudo abrir la prueba",
                        message: errorMessage,
                        isLoading: isLoading
                    ) {
                        Task { await load() }
                    }
                } else if let test {
                    detailContent(test)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(EPTheme.background)
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let test {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.pruebaResultados(pruebaId: test.id, scope: test.scope)) {
                        Label(application == nil ? "Aplicar" : "Corregir", systemImage: "checkmark.rectangle.stack")
                    }
                    if !test.isApplied {
                    NavigationLink(value: AppRoute.pruebaEditor(
                        pruebaId: test.id,
                        curso: test.curso,
                        asignatura: test.asignatura,
                        scope: test.scope
                    )) {
                        Label("Editar", systemImage: "pencil")
                    }
                    }
                }
            }
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func detailContent(_ test: PruebaTemplate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            hero(test)

            if test.isApplied {
                notice(
                    icon: "lock.fill",
                    title: "Prueba aplicada: solo lectura",
                    message: "Su estructura ya se us\u{00F3} con estudiantes y no puede modificarse desde el editor.",
                    tint: .blue
                )
            }

            if test.isFromCache || application?.isFromCache == true {
                notice(
                    icon: "icloud.slash.fill",
                    title: "Contenido disponible sin conexión",
                    message: "Puede no incluir los cambios más recientes de la versión web.",
                    tint: .orange
                )
            }

            if test.tieneContenidoDesconocido || !test.issues.isEmpty {
                compatibilityCard(test)
            }

            summaryGrid(test)
            configurationCard(test)
            instructionsCard(test)
            curriculumCard(test)

            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(
                    title: "Contenido de la prueba",
                    subtitle: "\(test.secciones.count) secciones · \(test.totalItems) ítems",
                    icon: "list.bullet.rectangle.fill"
                )

                ForEach(test.secciones.sorted(by: sectionOrder)) { section in
                    PruebaSectionDetailView(section: section)
                }
            }

            adaptationsCard(test)
            applicationCard(test)
        }
    }

    private func hero(_ test: PruebaTemplate) -> some View {
        EPModuleHeader(
            eyebrow: "Prueba · \(test.curso)",
            title: test.nombre.isEmpty ? "Sin nombre" : test.nombre,
            subtitle: [test.asignatura, test.unidadNombre ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            icon: "doc.text.fill",
            accent: .evaluaciones
        ) {
            ReplicaFlowLayout(spacing: 7) {
                EPStatusPill(text: typeLabel(test.tipoEvaluacion), tint: EPTheme.rose)
                EPStatusPill(text: stateLabel(test.estado), tint: stateTint(test.estado))
                if test.bloqueada {
                    EPStatusPill(text: "Bloqueada", icon: "lock.fill", tint: .gray)
                }
                if case .colegio(_) = test.scope {
                    EPStatusPill(text: "Colegio activo", icon: "building.2.fill", tint: .blue)
                }
            }
        }
    }

    private func summaryGrid(_ test: PruebaTemplate) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 9)], spacing: 9) {
            EPKPIBox(title: "Secciones", value: "\(test.secciones.count)", subtitle: "bloques", icon: "rectangle.stack.fill", tint: EPTheme.rose)
            EPKPIBox(title: "Ítems", value: "\(test.totalItems)", subtitle: "preguntas", icon: "number.square.fill", tint: .blue)
            EPKPIBox(
                title: "Puntaje",
                value: score(test.puntajeMaximo),
                subtitle: abs(test.puntajeMaximo - test.puntajeCalculado) > 0.001 ? "calculado \(score(test.puntajeCalculado))" : "máximo",
                icon: "star.circle.fill",
                tint: .orange
            )
            if let minutes = test.tiempoMinutos {
                EPKPIBox(title: "Tiempo", value: "\(minutes)", subtitle: "minutos", icon: "clock.fill", tint: .purple)
            }
        }
    }

    private func configurationCard(_ test: PruebaTemplate) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Configuración", icon: "slider.horizontal.3")
                keyValue("Asignatura", test.asignatura.isEmpty ? "Sin asignatura" : test.asignatura)
                keyValue("Curso", test.curso.isEmpty ? "Sin curso" : test.curso)
                if let unit = test.unidadNombre ?? test.unidadId {
                    keyValue("Unidad", unit)
                }
                keyValue("Tipo", typeLabel(test.tipoEvaluacion))
                if let weight = test.ponderacion {
                    keyValue("Ponderación", "\(score(weight))%")
                }
                keyValue("Exigencia", "\(Int((test.exigencia * 100).rounded()))%")
                if let teacher = test.docenteNombre, !teacher.isEmpty {
                    keyValue("Docente", teacher)
                }
                if let date = test.fechaActualizacion ?? test.fechaCreacion {
                    keyValue("Última actualización", date.formatted(date: .long, time: .shortened))
                }
            }
        }
    }

    @ViewBuilder
    private func instructionsCard(_ test: PruebaTemplate) -> some View {
        if !test.instruccionesGenerales.isEmpty {
            EPWebCard {
                VStack(alignment: .leading, spacing: 10) {
                    EPSectionHeader(title: "Instrucciones generales", icon: "text.badge.checkmark")
                    ForEach(Array(test.instruccionesGenerales.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(EPTheme.rose, in: Circle())
                            Text(instruction)
                                .font(.system(size: 12.5, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func curriculumCard(_ test: PruebaTemplate) -> some View {
        let metadata = test.metadatosCurriculares
        if !metadata.objetivos.isEmpty || !metadata.indicadores.isEmpty || !metadata.objetivosTransversales.isEmpty {
            EPCollapsibleSection(
                title: "Vinculación curricular",
                subtitle: "OA, indicadores y objetivos transversales.",
                icon: "link.circle.fill"
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    curriculumRows("Objetivos", values: metadata.objetivos, tint: .blue)
                    curriculumRows("Indicadores", values: metadata.indicadores, tint: .green)
                    curriculumRows("Objetivos transversales", values: metadata.objetivosTransversales, tint: .purple)
                }
            }
        }
    }

    @ViewBuilder
    private func curriculumRows(_ title: String, values: [String], tint: Color) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.7)
                    .foregroundStyle(tint)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func adaptationsCard(_ test: PruebaTemplate) -> some View {
        if !test.adaptacionesPie.isEmpty {
            EPCollapsibleSection(
                title: "Adecuaciones PIE",
                subtitle: "\(test.adaptacionesPie.count) adaptación(es) guardadas en la prueba.",
                icon: "person.crop.circle.badge.checkmark"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(test.adaptacionesPie) { adaptation in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(adaptation.nombre)
                                .font(.subheadline.weight(.black))
                            if let student = adaptation.estudianteNombre, !student.isEmpty {
                                Label(student, systemImage: "person.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            if !adaptation.diagnostico.isEmpty {
                                Text(adaptation.diagnostico)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(adaptation.secciones.count) secciones adaptadas")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(EPTheme.rose)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(EPTheme.rose.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
            }
        }
    }

    private func compatibilityCard(_ test: PruebaTemplate) -> some View {
        notice(
            icon: "exclamationmark.shield.fill",
            title: "Compatibilidad protegida",
            message: compatibilityMessage(test),
            tint: .orange
        )
    }

    private func applicationCard(_ test: PruebaTemplate) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 13) {
                EPSectionHeader(
                    title: "Aplicación y resultados",
                    subtitle: "Registro compatible con apl_\(test.id)",
                    icon: "person.3.fill"
                )

                NavigationLink(value: AppRoute.pruebaResultados(pruebaId: test.id, scope: test.scope)) {
                    Label(
                        application == nil ? "Aplicar prueba al curso" : "Abrir corrección y resultados",
                        systemImage: application == nil ? "play.circle.fill" : "checkmark.rectangle.stack.fill"
                    )
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                if let applicationErrorMessage {
                    notice(
                        icon: "exclamationmark.triangle.fill",
                        title: "No se pudo leer la aplicación",
                        message: applicationErrorMessage,
                        tint: .orange
                    )
                } else if let application {
                    applicationSummary(application)
                } else {
                    Label("Esta prueba todavía no tiene una aplicación guardada.", systemImage: "tray")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private func applicationSummary(_ application: PruebaAplicacion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                compactMetric("Alumnos", "\(application.resultados.count)", .blue)
                compactMetric("Corregidos", "\(application.completados.count)", .green)
                compactMetric("Ausentes", "\(application.resultados.filter { $0.ausente }.count)", .orange)
                compactMetric("Promedio", application.promedio.map { String(format: "%.1f", $0) } ?? "—", EPTheme.rose)
            }

            if let date = application.fechaAplicacion, !date.isEmpty {
                Label("Fecha de aplicación: \(date)", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if application.bloqueada {
                EPStatusPill(text: "Aplicación bloqueada", icon: "lock.fill", tint: .gray)
            }

            Divider()

            ForEach(application.resultados.sorted { $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending }) { result in
                HStack(spacing: 10) {
                    Image(systemName: result.ausente ? "person.crop.circle.badge.xmark" : "person.crop.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(result.ausente ? .orange : EPTheme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(result.nombre)
                                .font(.caption.weight(.black))
                            if result.hasPie {
                                Text("PIE")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.1), in: Capsule())
                            }
                        }
                        Text(result.ausente ? "Ausente" : "\(score(result.puntajeTotal)) pts")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(result.nota.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(noteTint(result.nota))
                        .frame(minWidth: 34)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func compactMetric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func notice(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.black))
                Text(message)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func compatibilityMessage(_ test: PruebaTemplate) -> String {
        var parts = Array(test.issues.prefix(3))
        if test.tieneContenidoDesconocido {
            parts.append("Hay tipos futuros o desconocidos; se conservan sin alterarlos.")
        }
        return parts.isEmpty ? "El contenido se conserva sin modificaciones." : parts.joined(separator: " ")
    }

    private func sectionOrder(_ lhs: PruebaSeccion, _ rhs: PruebaSeccion) -> Bool {
        if lhs.orden == rhs.orden { return lhs.id < rhs.id }
        return lhs.orden < rhs.orden
    }

    private func typeLabel(_ value: String) -> String {
        switch value {
        case "formativa": return "Formativa"
        case "diagnostica": return "Diagnóstica"
        case "sumativa", "": return "Sumativa"
        default: return value.capitalized
        }
    }

    private func stateLabel(_ value: String) -> String {
        switch value {
        case "lista": return "Lista"
        case "aplicada": return "Aplicada"
        case "archivada": return "Archivada"
        case "borrador", "": return "Borrador"
        default: return value.capitalized
        }
    }

    private func stateTint(_ value: String) -> Color {
        switch value {
        case "lista": return .green
        case "aplicada": return .blue
        case "archivada": return .gray
        default: return .orange
        }
    }

    private func score(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func noteTint(_ note: Double?) -> Color {
        guard let note else { return .secondary }
        return note >= 4 ? .green : .red
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        applicationErrorMessage = nil
        defer { isLoading = false }

        do {
            guard let loadedTest = try await repository.cargarPrueba(id: pruebaId, scope: scope) else {
                test = nil
                application = nil
                errorMessage = "La prueba no existe en el colegio seleccionado."
                return
            }
            guard !Task.isCancelled else { return }
            test = loadedTest

            do {
                application = try await repository.cargarAplicacionPrueba(pruebaId: pruebaId, scope: scope)
            } catch is CancellationError {
                return
            } catch {
                application = nil
                applicationErrorMessage = error.localizedDescription
            }
        } catch is CancellationError {
            return
        } catch {
            test = nil
            application = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct PruebaSectionDetailView: View {
    let section: PruebaSeccion

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Text(roman(section.orden))
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(EPTheme.rose, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.titulo.isEmpty ? "Sección \(section.orden)" : section.titulo)
                            .font(.system(size: 15, weight: .black))
                        if !section.instrucciones.isEmpty {
                            Text(section.instrucciones)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    EPStatusPill(text: "\(section.items.count) ítems", tint: EPTheme.rose)
                }

                if !section.estimulo.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("ESTÍMULO")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        ForEach(section.estimulo) { block in
                            PruebaContentBlockView(block: block)
                        }
                    }
                    .padding(11)
                    .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    PruebaItemDetailView(item: item, number: index + 1)
                    if index < section.items.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func roman(_ value: Int) -> String {
        let map: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        guard value > 0, value < 40 else { return String(value) }
        var number = value
        var result = ""
        for (amount, symbol) in map {
            while number >= amount { result += symbol; number -= amount }
        }
        return result
    }
}

private struct PruebaItemDetailView: View {
    let item: PruebaItem
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 9) {
                Text("\(number)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(EPTheme.rose)
                    .frame(width: 25, height: 25)
                    .background(EPTheme.rose.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Label(item.kind.label, systemImage: item.kind.icon)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(item.kind.isUnknown ? .orange : EPTheme.rose)
                        Spacer()
                        Text("\(score(item.puntaje)) pts")
                            .font(.caption.weight(.black))
                    }
                    if !item.enunciado.isEmpty {
                        Text(item.enunciado)
                            .font(.system(size: 13, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        if let oa = item.oaVinculado, !oa.isEmpty {
                            EPStatusPill(text: oa, icon: "link", tint: .blue)
                        }
                        if let skill = item.habilidad, !skill.isEmpty {
                            EPStatusPill(text: skill.capitalized, icon: "brain.head.profile", tint: .purple)
                        }
                    }
                }
            }

            itemSpecificContent

            if !item.recursos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECURSOS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    ForEach(item.recursos) { block in
                        PruebaContentBlockView(block: block)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var itemSpecificContent: some View {
        switch item.kind {
        case .seleccionMultiple:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(item.alternativas) { alternative in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: alternative.esCorrecta ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(alternative.esCorrecta ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(alternative.texto.isEmpty ? "Alternativa sin texto" : alternative.texto)
                                .font(.caption.weight(alternative.esCorrecta ? .bold : .medium))
                            if let imageURL = alternative.imagenUrl {
                                PruebaRemoteImage(urlString: imageURL, alt: alternative.texto)
                            }
                        }
                    }
                }
            }
        case .verdaderoFalso:
            Label(
                item.respuestaCorrecta == true ? "Respuesta: Verdadero" : item.respuestaCorrecta == false ? "Respuesta: Falso" : "Sin respuesta definida",
                systemImage: item.respuestaCorrecta == nil ? "questionmark.circle" : "checkmark.seal.fill"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(item.respuestaCorrecta == nil ? .orange : .green)
            if item.pideJustificacion {
                Text("El estudiante debe justificar las afirmaciones falsas.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .pareados:
            HStack(alignment: .top, spacing: 10) {
                pairingColumn("Columna A", rows: item.columnaA.map { $0.texto })
                pairingColumn("Columna B", rows: item.columnaB.map { $0.texto })
            }
        case .ordenar:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(item.pasos.enumerated()), id: \.element.id) { index, step in
                    Label(step.texto, systemImage: "\(index + 1).circle.fill")
                        .font(.caption.weight(.semibold))
                }
            }
        case .completar:
            VStack(alignment: .leading, spacing: 7) {
                if let text = item.textoConBlancos, !text.isEmpty {
                    Text(text)
                        .font(.caption.weight(.semibold))
                }
                if !item.respuestasCorrectas.isEmpty {
                    Text("Respuestas: \(item.respuestasCorrectas.joined(separator: " · "))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
                if !item.bancoPalabras.isEmpty {
                    Text("Banco: \(item.bancoPalabras.joined(separator: " · "))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        case .respuestaCorta:
            if let expected = item.respuestaEsperada, !expected.isEmpty {
                answerBox(title: "Respuesta esperada", text: expected)
            } else {
                Text("Corrección manual")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .desarrollo:
            VStack(alignment: .leading, spacing: 8) {
                if let guideline = item.pautaCorreccion, !guideline.isEmpty {
                    answerBox(title: "Pauta de corrección", text: guideline)
                }
                ForEach(item.criterios) { criterion in
                    HStack(alignment: .top) {
                        Text(criterion.texto)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(score(criterion.puntaje)) pts")
                            .font(.caption2.weight(.black))
                    }
                }
            }
        case .unknown(let rawType):
            Label(
                "Tipo web no reconocido: \(rawType.isEmpty ? "sin discriminador" : rawType). El payload original se conserva.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
    }

    private func pairingColumn(_ title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Text("\(index + 1). \(row)")
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(9)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func answerBox(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.green)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func score(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct PruebaContentBlockView: View {
    let block: PruebaContentBlock

    var body: some View {
        Group {
            switch block.kind {
            case .texto:
                if let html = block.html, !RichTextHTML.plainText(from: html).isEmpty {
                    RichTextRenderer(html: html)
                }
            case .imagen:
                if let url = block.url {
                    VStack(alignment: .leading, spacing: 5) {
                        PruebaRemoteImage(urlString: url, alt: block.alt ?? block.caption ?? "Imagen de la prueba")
                        if let caption = block.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .tabla:
                PruebaTableBlock(headers: block.cabeceras, rows: block.filas)
            case .separador:
                Divider()
                    .padding(.vertical, block.estilo == "espacio" ? 14 : 4)
            case .unknown(let type):
                Label(
                    "Bloque web no reconocido: \(type.isEmpty ? "sin tipo" : type)",
                    systemImage: "questionmark.diamond.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PruebaRemoteImage: View {
    let urlString: String
    let alt: String

    private var secureURL: URL? {
        guard let components = URLComponents(string: urlString),
              components.scheme?.lowercased() == "https" else { return nil }
        return components.url
    }

    var body: some View {
        Group {
            if let secureURL {
                AsyncImage(url: secureURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 100)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                    case .failure:
                        placeholder("No se pudo cargar la imagen")
                    @unknown default:
                        placeholder("Vista previa no disponible")
                    }
                }
            } else {
                placeholder("Imagen bloqueada: la URL no usa HTTPS")
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(alt.isEmpty ? "Imagen de la prueba" : alt)
    }

    private func placeholder(_ text: String) -> some View {
        Label(text, systemImage: "photo")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(10)
    }
}

struct PruebaTableBlock: View {
    let headers: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        if columnCount > 0 {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 1) {
                    if !headers.isEmpty {
                        row(headers, isHeader: true)
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, values in
                        row(values, isHeader: false)
                    }
                }
                .padding(1)
                .background(Color(.separator).opacity(0.35))
            }
        }
    }

    private func row(_ values: [String], isHeader: Bool) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<columnCount, id: \.self) { index in
                Text(index < values.count ? values[index] : "")
                    .font(.caption2.weight(isHeader ? .black : .medium))
                    .frame(width: 130, alignment: .leading)
                    .padding(8)
                    .background(isHeader ? EPTheme.rose.opacity(0.12) : Color(.systemBackground))
            }
        }
    }
}
