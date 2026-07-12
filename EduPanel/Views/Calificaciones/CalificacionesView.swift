import SwiftUI

private struct OaOpcionCalificaciones: Identifiable, Hashable {
    let id: String
    let label: String
    let descripcion: String
    let unidadId: String
}

struct CalificacionesView: View {
    let dashboardRepository: DashboardRepository

    @State private var snapshot: DashboardSnapshot?
    @State private var selectedCurso = ""
    @State private var selectedSubject = ""
    @State private var doc: CalificacionesDoc?
    @State private var oaOpciones: [OaOpcionCalificaciones] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tab = "tabla"
    @State private var filtroPeriodo = "todos"

    private let repository = CalificacionesRepository()
    private let planificacionRepository = PlanificacionRepository()
    private let curriculoRepository = CurriculoRepository()

    private let tabs = [
        EPWebTab(id: "tabla", title: "Tabla densa", icon: "tablecells"),
        EPWebTab(id: "alumnos", title: "Diario digital", icon: "person.text.rectangle"),
        EPWebTab(id: "cobertura", title: "Cobertura OA", icon: "target")
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                selectors

                if let errorMessage {
                    EvaluacionesErrorBanner(message: errorMessage)
                }

                if isLoading {
                    EvaluacionesLoadingCard(texto: "Cargando calificaciones...")
                } else if cursos.isEmpty {
                    EPWebCard {
                        EPEmptyState(
                            icon: "graduationcap",
                            title: "Configura tus cursos en Mi Perfil",
                            message: "Para revisar calificaciones necesitas al menos un curso en tu horario semanal."
                        )
                    }
                } else {
                    contenido
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(EPTheme.background)
        .navigationTitle("Calificaciones")
        .task { await cargar() }
        .refreshable { await cargar() }
    }

    private var header: some View {
        EPModuleHeader(
            eyebrow: "Calificaciones",
            title: "Notas sincronizadas",
            subtitle: "Visor nativo para revisar la tabla, el diario digital y la cobertura OA.",
            icon: "checkmark.clipboard.fill",
            accent: .calificaciones
        )
    }

    @ViewBuilder
    private var selectors: some View {
        if !cursos.isEmpty {
            HStack(spacing: 10) {
                EvaluacionesCursoPicker(
                    cursos: cursos,
                    seleccionado: Binding(
                        get: { selectedCurso },
                        set: { nuevo in
                            Task { await seleccionarCurso(nuevo) }
                        }
                    )
                )

                Menu {
                    ForEach(availableSubjects, id: \.self) { subject in
                        Button {
                            Task { await seleccionarAsignatura(subject) }
                        } label: {
                            if subject == activeSubject {
                                Label(subject, systemImage: "checkmark")
                            } else {
                                Text(subject)
                            }
                        }
                    }
                } label: {
                    EPStatusPill(text: activeSubject, icon: "book.closed.fill")
                }

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var contenido: some View {
        if let doc {
            kpis(doc)
            filtroPeriodoPicker
            EPWebTabBar(tabs: tabs, selected: $tab)

            if evaluacionesFiltradas.isEmpty {
                emptyState
            } else {
                switch tab {
                case "tabla":
                    tablaView(doc)
                case "cobertura":
                    coberturaView(doc)
                default:
                    porAlumnoView(doc)
                }
            }
        } else {
            emptyState
        }
    }

    private func kpis(_ doc: CalificacionesDoc) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            EPKPIBox(title: "Estudiantes", value: "\(doc.estudiantes.count)", subtitle: "En el documento", icon: "person.2.fill")
            EPKPIBox(title: "Evaluaciones", value: "\(evaluacionesFiltradas.count)", subtitle: periodoDescripcion, icon: "checklist.checked")
            EPKPIBox(
                title: "Promedio curso",
                value: formatNota(promedioCurso),
                subtitle: "Promedio de estudiantes con nota",
                icon: "chart.line.uptrend.xyaxis",
                tint: (promedioCurso ?? 1) >= 4 ? .green : .red
            )
            EPKPIBox(
                title: "Aprobacion",
                value: aprobacionCurso.map { "\($0)%" } ?? "-",
                subtitle: "Promedio 4.0 o superior",
                icon: "checkmark.seal.fill",
                tint: .green
            )
        }
    }

    private var filtroPeriodoPicker: some View {
        Picker("Periodo", selection: $filtroPeriodo) {
            Text("Todos").tag("todos")
            Text("S1").tag("s1")
            Text("S2").tag("s2")
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        EPWebCard {
            EPEmptyState(
                icon: "tray",
                title: "Aun no hay calificaciones sincronizadas",
                message: "Sincroniza desde los resultados de una prueba, rúbrica o lista para revisar las notas de este curso."
            )
        }
    }

    private func tablaView(_ doc: CalificacionesDoc) -> some View {
        EPWebCard(padding: 12) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text("Estudiante")
                            .font(.system(size: 10.5, weight: .black))
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                        ForEach(evaluacionesFiltradas) { evaluacion in
                            Text(evaluacion.label)
                                .font(.system(size: 9.5, weight: .black))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 64)
                                .frame(minHeight: 34)
                        }
                        Text("Prom.")
                            .font(.system(size: 10.5, weight: .black))
                            .foregroundStyle(.secondary)
                            .frame(width: 56)
                    }
                    .padding(.bottom, 8)

                    Divider()

                    ForEach(Array(estudiantesOrdenados.enumerated()), id: \.element.id) { index, estudiante in
                        HStack(spacing: 6) {
                            estudianteCell(estudiante)
                            ForEach(evaluacionesFiltradas) { evaluacion in
                                notaCell(doc.notaEfectiva(estudiante: estudiante, evalId: evaluacion.id))
                                    .frame(width: 64)
                            }
                            promedioCell(doc.promedio(estudiante: estudiante, evaluaciones: evaluacionesFiltradas))
                                .frame(width: 56)
                        }
                        .padding(.vertical, 8)

                        if index < estudiantesOrdenados.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func porAlumnoView(_ doc: CalificacionesDoc) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(estudiantesOrdenados) { estudiante in
                EPWebCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(estudiante.name)
                                        .font(.system(size: 14, weight: .black))
                                    if estudiante.hasPie {
                                        pieBadge
                                    }
                                }
                                if let diagnostico = estudiante.pieDiagnostico, !diagnostico.isEmpty {
                                    Text(diagnostico)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            let promedio = doc.promedio(estudiante: estudiante, evaluaciones: evaluacionesFiltradas)
                            Text(formatNota(promedio))
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(colorNota(promedio))
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(evaluacionesFiltradas.enumerated()), id: \.element.id) { index, evaluacion in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(evaluacion.label)
                                            .font(.system(size: 12.5, weight: .bold))
                                            .lineLimit(2)
                                        EPStatusPill(text: tipoLabel(evaluacion.tipo), tint: evaluacion.tipo == "formativa" ? .gray : .blue)
                                    }
                                    Spacer()
                                    notaCell(doc.notaEfectiva(estudiante: estudiante, evalId: evaluacion.id))
                                }
                                .padding(.vertical, 8)

                                if index < evaluacionesFiltradas.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func coberturaView(_ doc: CalificacionesDoc) -> some View {
        let oas = oaInfoCobertura
        let evaluacionesPorOa = evaluacionesPorOA(oas)

        return Group {
            if oas.isEmpty {
                coberturaEmptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    coberturaInfoBanner

                    EPWebCard(padding: 12) {
                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Text("Estudiante")
                                        .font(.system(size: 10.5, weight: .black))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 140, alignment: .leading)

                                    ForEach(oas) { oa in
                                        VStack(spacing: 2) {
                                            Text(oa.label)
                                                .font(.system(size: 10, weight: .black))
                                                .lineLimit(1)
                                            if !oa.descripcion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(oa.descripcion)
                                                    .font(.system(size: 8.5, weight: .semibold))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .multilineTextAlignment(.center)
                                        .frame(width: 70)
                                        .frame(minHeight: 38)
                                    }
                                }
                                .padding(.bottom, 8)

                                Divider()

                                ForEach(Array(estudiantesOrdenados.enumerated()), id: \.element.id) { index, estudiante in
                                    HStack(spacing: 6) {
                                        estudianteCell(estudiante)

                                        ForEach(oas) { oa in
                                            coberturaCell(
                                                resultado: resultadoCobertura(
                                                    estudiante: estudiante,
                                                    evaluaciones: evaluacionesPorOa[oa.id] ?? [],
                                                    doc: doc
                                                )
                                            )
                                            .frame(width: 70)
                                        }
                                    }
                                    .padding(.vertical, 8)

                                    if index < estudiantesOrdenados.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private var coberturaInfoBanner: some View {
        EPWebCard(padding: 12) {
            Label(
                "Heatmap de cobertura: cada celda muestra el promedio del estudiante en las evaluaciones que tocan ese OA.",
                systemImage: "target"
            )
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var coberturaEmptyState: some View {
        EPWebCard {
            EPEmptyState(
                icon: "target",
                title: "Sin cobertura OA",
                message: "Aun no has vinculado evaluaciones a OAs. Vincula al menos una en la web o desde evaluaciones sincronizadas."
            )
        }
    }

    private func coberturaCell(resultado: (nota: Double?, count: Int)) -> some View {
        VStack(spacing: 2) {
            Text(formatNota(resultado.nota))
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(colorCobertura(resultado.nota))

            if resultado.count > 0 {
                Text("\(resultado.count)x ev")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 48)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(colorCobertura(resultado.nota).opacity(resultado.nota == nil ? 0.08 : 0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func estudianteCell(_ estudiante: EstudianteCalif) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(estudiante.name)
                .font(.system(size: 11.5, weight: .bold))
                .lineLimit(2)
            if estudiante.hasPie {
                pieBadge
            }
        }
        .frame(width: 140, alignment: .leading)
    }

    private var pieBadge: some View {
        Text("PIE")
            .font(.system(size: 8.5, weight: .black))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15), in: Capsule())
            .foregroundStyle(.purple)
    }

    private func notaCell(_ nota: Double?) -> some View {
        Text(formatNota(nota))
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(colorNota(nota))
            .frame(minWidth: 42)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(colorNota(nota).opacity(nota == nil ? 0.08 : 0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func promedioCell(_ promedio: Double?) -> some View {
        Text(formatNota(promedio))
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(colorNota(promedio))
    }

    private var cursos: [String] {
        snapshot?.courses ?? []
    }

    private var activeSubject: String {
        if !selectedSubject.isEmpty { return selectedSubject }
        if let delCurso = asignaturasDelCurso(selectedCurso).first { return delCurso }
        if let habilitada = snapshot?.preferences.asignaturasHabilitadas.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return habilitada
        }
        let especialidad = snapshot?.profile.especialidad.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return especialidad.isEmpty ? "M\u{00FA}sica" : especialidad
    }

    private var availableSubjects: [String] {
        var resultado: [String] = []
        var vistos = Set<String>()
        func agregar(_ valor: String) {
            let limpio = valor.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty, !vistos.contains(limpio) else { return }
            vistos.insert(limpio)
            resultado.append(limpio)
        }
        asignaturasDelCurso(selectedCurso).forEach(agregar)
        (snapshot?.preferences.asignaturasHabilitadas ?? []).forEach(agregar)
        agregar(snapshot?.profile.especialidad ?? "")
        if resultado.isEmpty { agregar("M\u{00FA}sica") }
        return resultado
    }

    private func asignaturasDelCurso(_ curso: String) -> [String] {
        guard !curso.isEmpty, let horario = snapshot?.horario else { return [] }
        var resultado: [String] = []
        var vistos = Set<String>()
        for clase in horario where clase.resumen == curso {
            guard let asignatura = clase.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !asignatura.isEmpty, !vistos.contains(asignatura) else { continue }
            vistos.insert(asignatura)
            resultado.append(asignatura)
        }
        return resultado
    }

    private var evaluacionesFiltradas: [EvaluacionCalif] {
        guard let doc else { return [] }
        return doc.evaluaciones.filter { evaluacion in
            filtroPeriodo == "todos" || evaluacion.periodo.lowercased() == filtroPeriodo
        }
    }

    private var oaInfoCobertura: [OaOpcionCalificaciones] {
        let index = Dictionary(oaOpciones.map { ($0.id, $0) }) { first, _ in first }
        var vistos = Set<String>()
        var result: [OaOpcionCalificaciones] = []

        for evaluacion in evaluacionesFiltradas {
            for rawId in evaluacion.oaIds ?? [] {
                let oaId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !oaId.isEmpty, !vistos.contains(oaId) else { continue }
                vistos.insert(oaId)
                result.append(index[oaId] ?? OaOpcionCalificaciones(id: oaId, label: oaId, descripcion: "", unidadId: ""))
            }
        }
        return result
    }

    private var estudiantesOrdenados: [EstudianteCalif] {
        (doc?.estudiantes ?? []).sorted {
            let left = $0.orden ?? 999
            let right = $1.orden ?? 999
            return left == right ? $0.name < $1.name : left < right
        }
    }

    private var promediosCurso: [Double] {
        guard let doc else { return [] }
        return doc.estudiantes.compactMap { doc.promedio(estudiante: $0, evaluaciones: evaluacionesFiltradas) }
    }

    private var promedioCurso: Double? {
        guard !promediosCurso.isEmpty else { return nil }
        let promedio = promediosCurso.reduce(0, +) / Double(promediosCurso.count)
        return (promedio * 10).rounded() / 10
    }

    private var aprobacionCurso: Int? {
        guard !promediosCurso.isEmpty else { return nil }
        let aprobados = promediosCurso.filter { $0 >= 4.0 }.count
        return Int((Double(aprobados) / Double(promediosCurso.count) * 100).rounded())
    }

    private func evaluacionesPorOA(_ oas: [OaOpcionCalificaciones]) -> [String: [EvaluacionCalif]] {
        Dictionary(uniqueKeysWithValues: oas.map { oa in
            (oa.id, evaluacionesFiltradas.filter { tocaOA($0, oaId: oa.id) })
        })
    }

    private func tocaOA(_ evaluacion: EvaluacionCalif, oaId: String) -> Bool {
        (evaluacion.oaIds ?? []).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == oaId
        }
    }

    private func resultadoCobertura(estudiante: EstudianteCalif, evaluaciones: [EvaluacionCalif], doc: CalificacionesDoc) -> (nota: Double?, count: Int) {
        let notas = evaluaciones.compactMap { doc.notaEfectiva(estudiante: estudiante, evalId: $0.id) }
        guard !notas.isEmpty else { return (nil, 0) }
        let promedio = notas.reduce(0, +) / Double(notas.count)
        return ((promedio * 10).rounded() / 10, notas.count)
    }

    private var periodoDescripcion: String {
        switch filtroPeriodo {
        case "s1": return "Primer semestre"
        case "s2": return "Segundo semestre"
        default: return "Todos los periodos"
        }
    }

    private func tipoLabel(_ value: String) -> String {
        value.lowercased() == "formativa" ? "Formativa" : "Sumativa"
    }

    private func colorNota(_ nota: Double?) -> Color {
        guard let nota else { return .secondary }
        return nota >= 4.0 ? .green : .red
    }

    private func colorCobertura(_ nota: Double?) -> Color {
        guard let nota else { return .secondary }
        if nota < 4.0 { return .red }
        if nota < 5.5 { return .orange }
        return .green
    }

    private func formatNota(_ nota: Double?) -> String {
        guard let nota else { return "\u{2014}" }
        return String(format: "%.1f", nota)
    }

    private func cargarOpcionesOA(asignatura: String, curso: String, snapshot: DashboardSnapshot) async -> [OaOpcionCalificaciones] {
        if let unidadesGuardadas = try? await planificacionRepository.cargarVerUnidadesCurso(asignatura: asignatura, curso: curso) {
            let opciones = opcionesDesdeVerUnidades(unidadesGuardadas)
            if !opciones.isEmpty { return opciones }
        }

        guard let nivel = CurriculoNivel.resolver(curso: curso, mapping: snapshot.nivelMapping),
              let unidades = try? await curriculoRepository.getUnidades(asignatura: asignatura, nivel: nivel) else {
            return []
        }

        var completas: [UnidadCurricular] = []
        for unidad in unidades {
            if let completa = try? await curriculoRepository.getUnidadCompleta(asignatura: asignatura, nivel: nivel, unidadId: unidad.id) {
                completas.append(completa)
            } else {
                completas.append(unidad)
            }
        }
        return opcionesDesdeCurriculo(completas, asignatura: asignatura)
    }

    private func opcionesDesdeVerUnidades(_ unidades: [String: VerUnidadGuardada]) -> [OaOpcionCalificaciones] {
        var vistos = Set<String>()
        var result: [OaOpcionCalificaciones] = []

        for (fallbackUnidadId, unidad) in unidades.sorted(by: { $0.key < $1.key }) {
            let unidadId = firstNonEmpty(unidad.unidadId, fallbackUnidadId)
            for oa in unidad.oas where oa.seleccionado {
                let oaId = oa.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !oaId.isEmpty, !vistos.contains(oaId) else { continue }
                vistos.insert(oaId)
                result.append(
                    OaOpcionCalificaciones(
                        id: oaId,
                        label: etiquetaOA(oa, fallback: oaId),
                        descripcion: oa.descripcion,
                        unidadId: unidadId
                    )
                )
            }
        }
        return result
    }

    private func opcionesDesdeCurriculo(_ unidades: [UnidadCurricular], asignatura: String) -> [OaOpcionCalificaciones] {
        var vistos = Set<String>()
        var result: [OaOpcionCalificaciones] = []

        for unidad in unidades.sorted(by: { $0.numeroUnidad < $1.numeroUnidad }) {
            for oa in CurriculoOA.initOAs(unidad: unidad, asignatura: asignatura) where oa.seleccionado {
                let oaId = oa.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !oaId.isEmpty, !vistos.contains(oaId) else { continue }
                vistos.insert(oaId)
                result.append(
                    OaOpcionCalificaciones(
                        id: oaId,
                        label: etiquetaOA(oa, fallback: oaId),
                        descripcion: oa.descripcion,
                        unidadId: unidad.id
                    )
                )
            }
        }
        return result
    }

    private func etiquetaOA(_ oa: OAEditado, fallback: String) -> String {
        if let numero = oa.numero {
            return "OA \(numero)"
        }
        return fallback
    }

    private func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    private func seleccionarCurso(_ curso: String) async {
        selectedCurso = curso
        selectedSubject = ""
        await cargar()
    }

    private func seleccionarAsignatura(_ asignatura: String) async {
        selectedSubject = asignatura
        await cargar()
    }

    private func cargar() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let snap = try await dashboardRepository.fetchDashboard()
            snapshot = snap
            if selectedCurso.isEmpty || !snap.courses.contains(selectedCurso) {
                selectedCurso = snap.courses.first ?? ""
                selectedSubject = ""
            }
            guard !selectedCurso.isEmpty else {
                doc = nil
                oaOpciones = []
                return
            }
            if selectedSubject.isEmpty {
                selectedSubject = availableSubjects.first ?? activeSubject
            }
            let subject = activeSubject
            let scope = EvaluacionScope.resolve(snap.preferences.colegioActivoId)
            doc = try await repository.cargar(
                asignatura: subject,
                curso: selectedCurso,
                scope: scope
            )
            oaOpciones = await cargarOpcionesOA(asignatura: subject, curso: selectedCurso, snapshot: snap)
        } catch {
            doc = nil
            oaOpciones = []
            errorMessage = "No se pudieron cargar las calificaciones de este curso."
        }
    }
}
