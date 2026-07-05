import SwiftUI

struct RubricaEvaluacionView: View {
    let rubricaId: String
    let dashboardRepository: DashboardRepository

    @State private var rubrica: RubricaTemplate?
    @State private var evaluacion: EvaluacionRubrica?
    @State private var grupoActivo = 0
    @State private var alumnoActivo: String?
    @State private var parteActiva = 0
    @State private var isLoading = true
    @State private var guardadoOk = false
    @State private var errorMessage: String?
    @State private var mostrarDistribucion = false
    @State private var tamanoGrupo = 2
    @State private var cantidadGrupos = 4
    @State private var distribucionPorCantidad = false
    @State private var confirmandoBloqueo = false
    @State private var autosaveTask: Task<Void, Never>?

    private let repository = EvaluacionesRepository()

    private var bloqueada: Bool {
        evaluacion?.bloqueada == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading {
                    EvaluacionesLoadingCard(texto: "Cargando evaluaci\u{00F3}n...")
                } else if let errorMessage, evaluacion == nil {
                    EvaluacionesErrorBanner(message: errorMessage)
                } else if rubrica != nil, evaluacion != nil {
                    contenido
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Evaluar r\u{00FA}brica")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if guardadoOk {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button {
                    confirmandoBloqueo = true
                } label: {
                    Image(systemName: bloqueada ? "lock.fill" : "lock.open")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(bloqueada ? .orange : EPTheme.primary)
                }
            }
        }
        .confirmationDialog(
            bloqueada ? "\u{00BF}Desbloquear evaluaci\u{00F3}n?" : "\u{00BF}Finalizar y bloquear evaluaci\u{00F3}n?",
            isPresented: $confirmandoBloqueo,
            titleVisibility: .visible
        ) {
            Button(bloqueada ? "Desbloquear" : "Bloquear") {
                evaluacion?.bloqueada = !bloqueada
                programarAutosave(inmediato: true)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(bloqueada
                 ? "Podr\u{00E1}s seguir editando los registros."
                 : "La evaluaci\u{00F3}n quedar\u{00E1} en modo solo lectura.")
        }
        .task { await cargar() }
        .onDisappear {
            autosaveTask?.cancel()
            if let evaluacion {
                let repo = repository
                Task { try? await repo.guardarEvaluacionRubrica(evaluacion) }
            }
        }
    }

    @ViewBuilder
    private var contenido: some View {
        if let errorMessage {
            EvaluacionesErrorBanner(message: errorMessage)
        }

        if bloqueada {
            EPStatusPill(text: "Evaluaci\u{00F3}n finalizada \u{00B7} solo lectura", icon: "lock.fill", tint: .orange)
        }

        encabezado
        selectorGrupos

        if mostrarDistribucion {
            distribucionCard
        }

        selectorAlumnos

        if let alumno = alumnoSeleccionado {
            scoreboardCard(alumno: alumno)
            criteriosCard(alumno: alumno)
            observacionesCard(alumno: alumno)
        } else {
            EPWebCard {
                EPEmptyState(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Sin alumno seleccionado",
                    message: "Elige un estudiante del grupo para asignar niveles de logro."
                )
            }
        }

        NavigationLink(value: AppRoute.rubricaResultados(rubricaId: rubricaId)) {
            Label("Ver resultados", systemImage: "chart.bar.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(EPTheme.heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var encabezado: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(rubrica?.nombre.isEmpty == false ? rubrica!.nombre : "R\u{00FA}brica")
                    .font(.system(size: 17, weight: .black))
                Text("\(rubrica?.curso ?? "") \u{00B7} \(rubrica?.criteriosTotales.count ?? 0) criterios \u{00B7} \(Int(rubrica?.puntajeMaximo ?? 0)) pts m\u{00E1}x.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectorGrupos: some View {
        SelectorGruposEvaluacion(
            grupos: gruposResumen,
            activo: grupoActivo,
            disabled: bloqueada,
            onSelect: { index in
                grupoActivo = index
                alumnoActivo = evaluacion?.grupos[index].estudiantes.first?.estudianteId
            },
            onAgregarGrupo: {
                guard var actual = evaluacion, !bloqueada else { return }
                let numero = actual.grupos.count + 1
                actual.grupos.append(GrupoRubrica(id: EvaluacionesIDs.uid(prefix: "grupo"), nombre: "Grupo \(numero)", estudiantes: []))
                evaluacion = actual
                programarAutosave()
            },
            onAusentes: asegurarGrupoAusentes,
            mostrarDistribucion: $mostrarDistribucion
        )
    }

    private var distribucionCard: some View {
        DistribucionGruposCard(
            distribucionPorCantidad: $distribucionPorCantidad,
            cantidadGrupos: $cantidadGrupos,
            tamanoGrupo: $tamanoGrupo,
            disabled: bloqueada,
            distribuir: distribuir
        )
    }

    private var selectorAlumnos: some View {
        SelectorAlumnosEvaluacion(
            estudiantes: grupoActual?.estudiantes ?? [],
            grupoVacio: grupoActual?.estudiantes.isEmpty == true,
            gruposDestino: gruposDestino,
            puedeMover: !bloqueada,
            alumnoActivo: $alumnoActivo,
            onMove: moverAlumno
        )
    }

    private func scoreboardCard(alumno: EstudianteRubrica) -> some View {
        EPWebCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(alumno.nombre)
                        .font(.system(size: 15, weight: .black))
                        .lineLimit(1)
                    Text(alumno.completado ? "Evaluaci\u{00F3}n completa" : "\(alumno.puntajes.count)/\(rubrica?.criteriosTotales.count ?? 0) criterios")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(alumno.completado ? .green : .secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(NotaChilena.formato(alumno.nota))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle((alumno.nota ?? 1) >= 4 ? .green : .red)
                    Text("\(Int(rubrica?.calcularPuntaje(puntajes: alumno.puntajes) ?? 0))/\(Int(rubrica?.puntajeMaximo ?? 0)) pts")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func criteriosCard(alumno: EstudianteRubrica) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                if (rubrica?.partes.count ?? 0) > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array((rubrica?.partes ?? []).enumerated()), id: \.element.id) { index, parte in
                                Button {
                                    withAnimation(EPTheme.spring) { parteActiva = index }
                                } label: {
                                    Text(parte.nombre)
                                        .font(.system(size: 11.5, weight: .black))
                                        .foregroundStyle(parteActiva == index ? .white : .secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            parteActiva == index
                                                ? AnyShapeStyle(EPTheme.fuchsia)
                                                : AnyShapeStyle(Color(.systemGray6)),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let parte = parteSeleccionada {
                    ForEach(parte.criterios) { criterio in
                        criterioFila(criterio: criterio, alumno: alumno)
                    }
                }
            }
        }
    }

    private func criterioFila(criterio: CriterioRubrica, alumno: EstudianteRubrica) -> some View {
        let seleccionado = alumno.puntajes[criterio.id]
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(criterio.nombre.isEmpty ? "Criterio \(criterio.orden)" : criterio.nombre)
                    .font(.system(size: 13, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let ponderacion = criterio.ponderacion, ponderacion > 1 {
                    EPStatusPill(text: "x\(Int(ponderacion))", tint: EPTheme.fuchsia)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(NivelRubrica.allCases) { nivel in
                    let activo = seleccionado == nivel.rawValue
                    Button {
                        registrarPuntaje(criterioId: criterio.id, valor: nivel.rawValue, actual: seleccionado)
                    } label: {
                        VStack(spacing: 2) {
                            Text(nivel.etiqueta)
                                .font(.system(size: 12, weight: .black))
                            Text("\(Int(nivel.rawValue)) pts")
                                .font(.system(size: 8.5, weight: .bold))
                                .opacity(0.8)
                        }
                        .foregroundStyle(activo ? .white : colorNivel(nivel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            activo ? AnyShapeStyle(colorNivel(nivel)) : AnyShapeStyle(colorNivel(nivel).opacity(0.12)),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let seleccionado,
               let nivel = NivelRubrica(rawValue: seleccionado) {
                let descripcion = nivel.descripcion(en: criterio)
                if !descripcion.isEmpty {
                    Text(descripcion)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(11)
        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .sensoryFeedback(.impact(weight: .light), trigger: seleccionado)
    }

    private func observacionesCard(alumno: EstudianteRubrica) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                EPSectionHeader(title: "Observaciones", icon: "text.bubble")
                TextField(
                    "Notas sobre el desempe\u{00F1}o de \(alumno.nombre)...",
                    text: Binding(
                        get: { alumnoSeleccionado?.observaciones ?? "" },
                        set: { nuevo in
                            actualizarAlumno(alumno.estudianteId) { $0.observaciones = nuevo }
                        }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .font(.system(size: 13))
                .padding(10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(bloqueada)
            }
        }
    }

    private func colorNivel(_ nivel: NivelRubrica) -> Color {
        switch nivel {
        case .logrado: return .green
        case .casiLogrado: return .blue
        case .parcialmenteLogrado: return .orange
        case .porLograr: return .red
        }
    }

    // MARK: - Estado derivado

    private var gruposResumen: [(id: String, nombre: String, esAusentes: Bool, count: Int)] {
        (evaluacion?.grupos ?? []).map {
            (id: $0.id, nombre: $0.nombre, esAusentes: $0.esAusentes, count: $0.estudiantes.count)
        }
    }

    private var gruposDestino: [(index: Int, nombre: String)] {
        Array((evaluacion?.grupos ?? []).enumerated()).compactMap { index, grupo in
            index == grupoActivo ? nil : (index: index, nombre: grupo.nombre)
        }
    }

    private var grupoActual: GrupoRubrica? {
        guard let evaluacion, evaluacion.grupos.indices.contains(grupoActivo) else { return nil }
        return evaluacion.grupos[grupoActivo]
    }

    private var alumnoSeleccionado: EstudianteRubrica? {
        grupoActual?.estudiantes.first { $0.estudianteId == alumnoActivo }
    }

    private var parteSeleccionada: RubricaParte? {
        guard let rubrica else { return nil }
        guard rubrica.partes.indices.contains(parteActiva) else { return rubrica.partes.first }
        return rubrica.partes[parteActiva]
    }

    // MARK: - Mutaciones

    private func registrarPuntaje(criterioId: String, valor: Double, actual: Double?) {
        guard let alumnoActivo else { return }
        actualizarAlumno(alumnoActivo) { est in
            if actual == valor {
                est.puntajes.removeValue(forKey: criterioId)
            } else {
                est.puntajes[criterioId] = valor
            }
        }
    }

    private func actualizarAlumno(_ estudianteId: String, _ transform: (inout EstudianteRubrica) -> Void) {
        guard var actual = evaluacion, !bloqueada, let rubrica,
              actual.grupos.indices.contains(grupoActivo),
              let estIndex = actual.grupos[grupoActivo].estudiantes.firstIndex(where: { $0.estudianteId == estudianteId })
        else { return }

        transform(&actual.grupos[grupoActivo].estudiantes[estIndex])
        actual.grupos[grupoActivo].estudiantes[estIndex].recalcular(con: rubrica)
        evaluacion = actual
        programarAutosave()
    }

    private func moverAlumno(estudianteId: String, hasta: Int) {
        guard var actual = evaluacion, !bloqueada,
              actual.grupos.indices.contains(grupoActivo),
              actual.grupos.indices.contains(hasta),
              let estIndex = actual.grupos[grupoActivo].estudiantes.firstIndex(where: { $0.estudianteId == estudianteId })
        else { return }

        let estudiante = actual.grupos[grupoActivo].estudiantes.remove(at: estIndex)
        actual.grupos[hasta].estudiantes.append(estudiante)
        evaluacion = actual
        if alumnoActivo == estudianteId {
            alumnoActivo = grupoActual?.estudiantes.first?.estudianteId
        }
        programarAutosave()
    }

    private func asegurarGrupoAusentes() {
        guard var actual = evaluacion else { return }
        if let index = actual.grupos.firstIndex(where: \.esAusentes) {
            grupoActivo = index
            alumnoActivo = actual.grupos[index].estudiantes.first?.estudianteId
            return
        }
        guard !bloqueada else { return }
        actual.grupos.append(GrupoRubrica(id: EvaluacionesIDs.uid(prefix: "grupo_ausentes"), nombre: "Ausentes", estudiantes: []))
        evaluacion = actual
        grupoActivo = actual.grupos.count - 1
        alumnoActivo = nil
        programarAutosave()
    }

    private func distribuir() {
        guard var actual = evaluacion, !bloqueada else { return }

        let grupoAusentes = actual.grupos.first(where: \.esAusentes)
        let aDistribuir = actual.grupos.filter { !$0.esAusentes }.flatMap(\.estudiantes)
        guard !aDistribuir.isEmpty else { return }

        let numGrupos = distribucionPorCantidad
            ? max(1, cantidadGrupos)
            : max(1, Int((Double(aDistribuir.count) / Double(tamanoGrupo)).rounded(.up)))
        var nuevos = (1...numGrupos).map {
            GrupoRubrica(id: EvaluacionesIDs.uid(prefix: "grupo"), nombre: "Grupo \($0)", estudiantes: [])
        }

        let pie = aDistribuir.filter(\.hasPie).shuffled()
        let regulares = aDistribuir.filter { !$0.hasPie }.shuffled()

        for (index, estudiante) in pie.enumerated() {
            nuevos[index % numGrupos].estudiantes.append(estudiante)
        }
        for estudiante in regulares {
            let menorIndex = nuevos.indices.min { nuevos[$0].estudiantes.count < nuevos[$1].estudiantes.count } ?? 0
            nuevos[menorIndex].estudiantes.append(estudiante)
        }

        if let grupoAusentes {
            nuevos.append(grupoAusentes)
        }

        actual.grupos = nuevos
        evaluacion = actual
        grupoActivo = 0
        alumnoActivo = nuevos.first?.estudiantes.first?.estudianteId
        withAnimation(EPTheme.spring) { mostrarDistribucion = false }
        programarAutosave()
    }

    // MARK: - Persistencia

    private func programarAutosave(inmediato: Bool = false) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            if !inmediato {
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled, let evaluacion else { return }
            do {
                try await repository.guardarEvaluacionRubrica(evaluacion)
                guardadoOk = true
                try? await Task.sleep(for: .seconds(1.6))
                guardadoOk = false
            } catch {
                errorMessage = "No se pudo guardar autom\u{00E1}ticamente."
            }
        }
    }

    private func cargar() async {
        defer { isLoading = false }
        do {
            guard let rubricaCargada = try await repository.cargarRubrica(id: rubricaId) else {
                errorMessage = "R\u{00FA}brica no encontrada."
                return
            }
            rubrica = rubricaCargada

            let snapshot = try await dashboardRepository.fetchDashboard()
            let alumnos = (snapshot.studentsByCourse[rubricaCargada.curso] ?? []).sorted { $0.orden < $1.orden }

            var evaluacionActual = try await repository.cargarEvaluacionRubrica(rubricaId: rubricaId)
                ?? .nueva(rubrica: rubricaCargada)
            evaluacionActual.sincronizarEstudiantes(alumnos, rubrica: rubricaCargada)
            evaluacion = evaluacionActual
            grupoActivo = 0
            parteActiva = 0
            alumnoActivo = evaluacionActual.grupos.first?.estudiantes.first?.estudianteId
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
