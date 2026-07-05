import SwiftUI

struct ListaEvaluacionView: View {
    let listaId: String
    let dashboardRepository: DashboardRepository

    @State private var lista: ListaCotejoTemplate?
    @State private var evaluacion: ListaCotejoEvaluacion?
    @State private var grupoActivo = 0
    @State private var alumnoActivo: String?
    @State private var isLoading = true
    @State private var guardadoOk = false
    @State private var errorMessage: String?
    @State private var mostrarDistribucion = false
    @State private var tamanoGrupo = 2
    @State private var cantidadGrupos = 4
    @State private var distribucionPorCantidad = false
    @State private var confirmandoBloqueo = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var busqueda = ""
    @State private var filtro: FiltroAlumno = .todos
    @State private var vistaPorIndicador = false
    @State private var indicadorActivoId: String?

    private let repository = EvaluacionesRepository()

    enum FiltroAlumno: String, CaseIterable {
        case todos = "Todos"
        case pendientes = "Pendientes"
        case completados = "Completados"
    }

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
                } else if lista != nil, evaluacion != nil {
                    contenido
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Evaluar lista")
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
                Task { try? await repo.guardarEvaluacionLista(evaluacion) }
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

        controlesEvaluacion

        if vistaPorIndicador {
            vistaPorIndicadorCard
        } else {
            selectorAlumnos

            if let alumno = alumnoSeleccionado {
                indicadoresCard(alumno: alumno)
                observacionesCard(alumno: alumno)
            } else {
                EPWebCard {
                    EPEmptyState(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "Sin alumno seleccionado",
                        message: "Elige un estudiante del grupo para registrar S\u{00ED}/No."
                    )
                }
            }
        }

        NavigationLink(value: AppRoute.listaResultados(listaId: listaId)) {
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
                Text(lista?.nombre.isEmpty == false ? lista!.nombre : "Lista de cotejo")
                    .font(.system(size: 17, weight: .black))
                Text("\(lista?.curso ?? "") \u{00B7} \(lista?.indicadoresTotales.count ?? 0) indicadores \u{00B7} \(Int(lista?.puntajeMaximo ?? 0)) pts m\u{00E1}x.")
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
                actual.grupos.append(GrupoListaCotejo(id: EvaluacionesIDs.uid(prefix: "grupo"), nombre: "Grupo \(numero)", estudiantes: []))
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

    private var controlesEvaluacion: some View {
        VStack(spacing: 8) {
            Picker("Vista", selection: $vistaPorIndicador) {
                Text("Por alumno").tag(false)
                Text("Por indicador").tag(true)
            }
            .pickerStyle(.segmented)

            if !vistaPorIndicador {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("Buscar alumno...", text: $busqueda)
                            .font(.system(size: 12.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6), in: Capsule())

                    Menu {
                        ForEach(FiltroAlumno.allCases, id: \.self) { opcion in
                            Button {
                                filtro = opcion
                            } label: {
                                if filtro == opcion {
                                    Label(opcion.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(opcion.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 11, weight: .black))
                            Text(filtro.rawValue)
                                .font(.system(size: 11.5, weight: .black))
                        }
                        .foregroundStyle(EPTheme.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(EPTheme.primary.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }

    private var estudiantesFiltrados: [EstudianteListaCotejo] {
        (grupoActual?.estudiantes ?? []).filter { est in
            let coincideBusqueda = busqueda.isEmpty || est.nombre.localizedCaseInsensitiveContains(busqueda)
            let coincideFiltro: Bool
            switch filtro {
            case .todos: coincideFiltro = true
            case .pendientes: coincideFiltro = !est.completado
            case .completados: coincideFiltro = est.completado
            }
            return coincideBusqueda && coincideFiltro
        }
    }

    private var selectorAlumnos: some View {
        SelectorAlumnosEvaluacion(
            estudiantes: estudiantesFiltrados,
            grupoVacio: grupoActual?.estudiantes.isEmpty == true,
            gruposDestino: gruposDestino,
            puedeMover: !bloqueada,
            alumnoActivo: $alumnoActivo,
            onMove: moverAlumno
        )
    }

    private var indicadoresPlanos: [(seccion: String, indicador: IndicadorListaCotejo)] {
        (lista?.secciones ?? []).flatMap { seccion in
            seccion.indicadores.map { (seccion.nombre, $0) }
        }
    }

    private var indicadorActivo: IndicadorListaCotejo? {
        let planos = indicadoresPlanos
        if let id = indicadorActivoId, let encontrado = planos.first(where: { $0.indicador.id == id }) {
            return encontrado.indicador
        }
        return planos.first?.indicador
    }

    private var vistaPorIndicadorCard: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 12) {
                EPSectionHeader(title: "Marcar por indicador", icon: "checklist")

                Menu {
                    ForEach(indicadoresPlanos, id: \.indicador.id) { item in
                        Button {
                            indicadorActivoId = item.indicador.id
                        } label: {
                            if item.indicador.id == indicadorActivo?.id {
                                Label(item.indicador.texto.isEmpty ? "Indicador" : item.indicador.texto, systemImage: "checkmark")
                            } else {
                                Text(item.indicador.texto.isEmpty ? "Indicador" : item.indicador.texto)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.number")
                            .font(.system(size: 11, weight: .black))
                        Text(indicadorActivo?.texto.isEmpty == false ? indicadorActivo!.texto : "Selecciona un indicador")
                            .font(.system(size: 12.5, weight: .bold))
                            .lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .black))
                    }
                    .foregroundStyle(EPTheme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(EPTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let indicador = indicadorActivo {
                    ForEach(estudiantesFiltrados) { estudiante in
                        let respuesta = estudiante.respuestas[indicador.id]
                        HStack(spacing: 8) {
                            Text(estudiante.nombre)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                            if estudiante.hasPie {
                                Text("PIE")
                                    .font(.system(size: 8, weight: .black))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                            Spacer(minLength: 8)
                            BotonSiNo(titulo: lista?.etiquetaSi ?? "S\u{00ED}", activo: respuesta == true, tint: .green) {
                                toggleRespuesta(estudianteId: estudiante.estudianteId, indicadorId: indicador.id, valor: true)
                            }
                            BotonSiNo(titulo: lista?.etiquetaNo ?? "No", activo: respuesta == false, tint: .red) {
                                toggleRespuesta(estudianteId: estudiante.estudianteId, indicadorId: indicador.id, valor: false)
                            }
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                } else {
                    Text("Esta lista no tiene indicadores.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggleRespuesta(estudianteId: String, indicadorId: String, valor: Bool) {
        let actual = grupoActual?.estudiantes.first { $0.estudianteId == estudianteId }?.respuestas[indicadorId]
        actualizarAlumno(estudianteId) { est in
            if actual == valor {
                est.respuestas.removeValue(forKey: indicadorId)
            } else {
                est.respuestas[indicadorId] = valor
            }
        }
    }

    private func indicadoresCard(alumno: EstudianteListaCotejo) -> some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    EPSectionHeader(title: "Indicadores", icon: "checklist")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(NotaChilena.formato(alumno.nota))
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle((alumno.nota ?? 1) >= 4 ? .green : .red)
                        Text("\(Int(alumno.puntaje ?? 0))/\(Int(lista?.puntajeMaximo ?? 0)) pts \u{00B7} \(Int(alumno.porcentaje ?? 0))%")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(lista?.secciones ?? []) { seccion in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(seccion.nombre.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(EPTheme.primary)

                        ForEach(seccion.indicadores) { indicador in
                            filaIndicador(indicador: indicador, alumno: alumno)
                        }
                    }
                }
            }
        }
    }

    private func filaIndicador(indicador: IndicadorListaCotejo, alumno: EstudianteListaCotejo) -> some View {
        let respuesta = alumno.respuestas[indicador.id]
        return HStack(alignment: .top, spacing: 10) {
            Text(indicador.texto)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                BotonSiNo(titulo: lista?.etiquetaSi ?? "S\u{00ED}", activo: respuesta == true, tint: .green) {
                    registrarRespuesta(indicadorId: indicador.id, valor: true, actual: respuesta)
                }
                BotonSiNo(titulo: lista?.etiquetaNo ?? "No", activo: respuesta == false, tint: .red) {
                    registrarRespuesta(indicadorId: indicador.id, valor: false, actual: respuesta)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func observacionesCard(alumno: EstudianteListaCotejo) -> some View {
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

    private var grupoActual: GrupoListaCotejo? {
        guard let evaluacion, evaluacion.grupos.indices.contains(grupoActivo) else { return nil }
        return evaluacion.grupos[grupoActivo]
    }

    private var alumnoSeleccionado: EstudianteListaCotejo? {
        grupoActual?.estudiantes.first { $0.estudianteId == alumnoActivo }
    }

    // MARK: - Mutaciones

    private func registrarRespuesta(indicadorId: String, valor: Bool, actual: Bool?) {
        guard let alumnoActivo else { return }
        actualizarAlumno(alumnoActivo) { est in
            if actual == valor {
                est.respuestas.removeValue(forKey: indicadorId)
            } else {
                est.respuestas[indicadorId] = valor
            }
        }
    }

    private func actualizarAlumno(_ estudianteId: String, _ transform: (inout EstudianteListaCotejo) -> Void) {
        guard var actual = evaluacion, !bloqueada, let lista,
              actual.grupos.indices.contains(grupoActivo),
              let estIndex = actual.grupos[grupoActivo].estudiantes.firstIndex(where: { $0.estudianteId == estudianteId })
        else { return }

        transform(&actual.grupos[grupoActivo].estudiantes[estIndex])
        actual.grupos[grupoActivo].estudiantes[estIndex].recalcular(con: lista)
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
        actual.grupos.append(GrupoListaCotejo(id: EvaluacionesIDs.uid(prefix: "grupo_ausentes"), nombre: "Ausentes", estudiantes: []))
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
            GrupoListaCotejo(id: EvaluacionesIDs.uid(prefix: "grupo"), nombre: "Grupo \($0)", estudiantes: [])
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
                try await repository.guardarEvaluacionLista(evaluacion)
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
            guard let listaCargada = try await repository.cargarListaCotejo(id: listaId) else {
                errorMessage = "Lista de cotejo no encontrada."
                return
            }
            lista = listaCargada

            let snapshot = try await dashboardRepository.fetchDashboard()
            let alumnos = (snapshot.studentsByCourse[listaCargada.curso] ?? []).sorted { $0.orden < $1.orden }

            var evaluacionActual = try await repository.cargarEvaluacionLista(listaId: listaId)
                ?? .nueva(lista: listaCargada, estudiantes: [])
            evaluacionActual.sincronizarEstudiantes(alumnos, lista: listaCargada)
            evaluacion = evaluacionActual
            grupoActivo = 0
            alumnoActivo = evaluacionActual.grupos.first?.estudiantes.first?.estudianteId
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
