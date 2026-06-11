import SwiftUI
import Observation

struct CronogramaView: View {
    @State private var viewModel: CronogramaViewModel
    @State private var selectedVista = "semana"
    @State private var editingActividad: ActividadCronograma?
    @State private var filtrosVisibles = false

    @Environment(\.displayMode) private var displayMode

    private let tabs = [
        EPWebTab(id: "semana", title: "Semana", icon: "square.grid.2x2"),
        EPWebTab(id: "mes", title: "Mes", icon: "square.grid.3x3"),
        EPWebTab(id: "dia", title: "Día", icon: "calendar.day.timeline.left"),
        EPWebTab(id: "lista", title: "Lista", icon: "list.bullet"),
        EPWebTab(id: "gantt", title: "Gantt", icon: "chart.bar.doc.horizontal"),
        EPWebTab(id: "heatmap", title: "Heatmap", icon: "chart.bar.xaxis")
    ]

    init(dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self._viewModel = State(initialValue: CronogramaViewModel(
            dashboardRepository: dashboardRepository,
            planificacionRepository: planificacionRepository
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading && viewModel.actividades.isEmpty && viewModel.horario.isEmpty {
                    loadingState
                } else {
                    contenido
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cronograma")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(item: $editingActividad) { actividad in
            ActividadEditorSheet(viewModel: viewModel, actividad: actividad)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando cronograma…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var contenido: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            heroCard
            kpiGrid
            filtrosSection

            EPWebTabBar(tabs: tabs, selected: $selectedVista)

            if viewModel.cursosDisponibles.isEmpty {
                EPWebCard {
                    EPEmptyState(
                        icon: "calendar.badge.exclamationmark",
                        title: "Sin cursos en tu horario",
                        message: "Configura bloques de clase en Mi Perfil para usar el cronograma."
                    )
                }
            } else {
                switch selectedVista {
                case "semana":
                    CronogramaSemanaView(viewModel: viewModel) { actividad in
                        editingActividad = actividad
                    } onCreate: { dia, hora in
                        editingActividad = viewModel.nuevaActividad(dia: dia, hora: hora)
                    }
                case "mes":
                    CronogramaMesView(viewModel: viewModel) { fecha in
                        viewModel.currentDate = fecha
                        withAnimation(EPTheme.spring) {
                            selectedVista = "dia"
                        }
                    }
                case "dia":
                    CronogramaDiaView(viewModel: viewModel) { actividad in
                        editingActividad = actividad
                    }
                case "lista":
                    CronogramaListaView(viewModel: viewModel) { actividad in
                        editingActividad = actividad
                    }
                case "gantt":
                    CronogramaGanttView(viewModel: viewModel)
                case "heatmap":
                    CronogramaHeatmapView(viewModel: viewModel)
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("CRONOGRAMA", systemImage: "calendar.badge.clock")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))

                Text("Tu mapa pedagógico del año")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.white)

                Text("\(viewModel.asignatura) · \(viewModel.cursoSeleccionado == "__todos__" ? "Todos los cursos" : viewModel.cursoSeleccionado) · Semana \(viewModel.semanaActual) · \(String(viewModel.anioActual))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        Task { await viewModel.seleccionarCurso("__todos__") }
                    } label: {
                        Label("Todos los cursos", systemImage: viewModel.cursoSeleccionado == "__todos__" ? "checkmark" : "books.vertical")
                    }
                    ForEach(viewModel.cursosDisponibles, id: \.self) { curso in
                        Button {
                            Task { await viewModel.seleccionarCurso(curso) }
                        } label: {
                            Label(curso, systemImage: viewModel.cursoSeleccionado == curso ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                        Text(viewModel.cursoSeleccionado == "__todos__" ? "Todos" : viewModel.cursoSeleccionado)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .black))
                    }
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.18), in: Capsule())
                }

                Spacer(minLength: 0)

                ProfileSaveBadge(status: viewModel.saveStatus)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(viewModel.saveStatus == .idle ? 0 : 0.85), in: Capsule())
            }

            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Button {
                        viewModel.cambiarSemana(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    Text(CronoDateHelpers.etiquetaSemana(viewModel.lunesActual))
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                    Button {
                        viewModel.cambiarSemana(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                }
                .background(.white.opacity(0.18), in: Capsule())

                Button {
                    withAnimation(EPTheme.spring) {
                        viewModel.irAHoy()
                    }
                } label: {
                    Text("Hoy")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.18), in: Capsule())
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.cyan, .blue, Color(red: 0.55, green: 0.36, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
        )
        .shadow(color: .blue.opacity(0.25), radius: 14, y: 7)
    }

    // MARK: - KPIs

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            EPKPIBox(title: "Actividades", value: "\(viewModel.actividadesFiltradas.count)", subtitle: "totales", icon: "sparkles", tint: .blue)
            EPKPIBox(title: "Unidades", value: "\(viewModel.unidadesConActividades)", subtitle: "con actividades", icon: "square.stack.3d.up.fill", tint: .purple)
            if !displayMode.isSimple {
                EPKPIBox(title: "Cursos", value: "\(viewModel.cursosDisponibles.count)", subtitle: "en horario", icon: "folder.fill", tint: EPTheme.primary)
                EPKPIBox(title: "Semana", value: "\(viewModel.semanaActual)", subtitle: CronoDateHelpers.tituloMes(viewModel.currentDate), icon: "calendar", tint: .cyan)
            }
        }
    }

    // MARK: - Filtros

    private var filtrosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayMode.isSimple {
                Button {
                    withAnimation(EPTheme.spring) {
                        filtrosVisibles.toggle()
                    }
                } label: {
                    HStack {
                        Label("Filtros", systemImage: "slider.horizontal.3")
                            .font(.footnote.weight(.black))
                            .foregroundStyle(EPTheme.primary)
                        Spacer()
                        if viewModel.hayFiltrosActivos {
                            Text("\(viewModel.filtroCursos.count + viewModel.filtroUnidades.count) activos")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(EPTheme.primary, in: Capsule())
                        } else {
                            Image(systemName: filtrosVisibles ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                if filtrosVisibles {
                    filtrosCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                filtrosCard
            }
        }
    }

    private var filtrosCard: some View {
        EPWebCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.cursoSeleccionado == "__todos__" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CURSO")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                        ReplicaFlowLayout(spacing: 8) {
                            ForEach(viewModel.cursosDisponibles, id: \.self) { curso in
                                filtroChip(
                                    titulo: curso,
                                    colorHex: nil,
                                    seleccionado: viewModel.filtroCursos.contains(curso)
                                ) {
                                    if viewModel.filtroCursos.contains(curso) {
                                        viewModel.filtroCursos.remove(curso)
                                    } else {
                                        viewModel.filtroCursos.insert(curso)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("UNIDAD")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                    if viewModel.unidades.isEmpty {
                        Text("No hay unidades planificadas en este curso.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ReplicaFlowLayout(spacing: 8) {
                            ForEach(viewModel.unidades) { unidad in
                                filtroChip(
                                    titulo: unidad.nombre,
                                    colorHex: unidad.colorHex,
                                    seleccionado: viewModel.filtroUnidades.contains(unidad.unidadId)
                                ) {
                                    if viewModel.filtroUnidades.contains(unidad.unidadId) {
                                        viewModel.filtroUnidades.remove(unidad.unidadId)
                                    } else {
                                        viewModel.filtroUnidades.insert(unidad.unidadId)
                                    }
                                }
                            }
                        }
                    }
                }

                if viewModel.hayFiltrosActivos {
                    Button {
                        withAnimation(EPTheme.spring) {
                            viewModel.filtroCursos.removeAll()
                            viewModel.filtroUnidades.removeAll()
                        }
                    } label: {
                        Label("Limpiar todo", systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(EPTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filtroChip(titulo: String, colorHex: String?, seleccionado: Bool, accion: @escaping () -> Void) -> some View {
        Button {
            withAnimation(EPTheme.spring) {
                accion()
            }
        } label: {
            HStack(spacing: 5) {
                if seleccionado {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.black))
                }
                if let colorHex {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(seleccionado ? Color.white : EPTheme.color(hex: colorHex))
                        .frame(width: 8, height: 8)
                }
                Text(titulo)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
            }
            .foregroundStyle(seleccionado ? .white : EPTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(seleccionado ? EPTheme.primary : EPTheme.primary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor de actividad

struct ActividadEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: CronogramaViewModel
    let actividad: ActividadCronograma

    @State private var nombre = ""
    @State private var semana = 1
    @State private var dia = "Lunes"
    @State private var hora = "08:30"
    @State private var duracion = "45 min"
    @State private var unidadId = ""
    @State private var cursoOrigen = ""
    @State private var confirmandoEliminar = false

    private var esNueva: Bool {
        !viewModel.actividades.contains { $0.id == actividad.id }
    }

    private var unidadesDelCurso: [CronoUnidadInfo] {
        if viewModel.cursoSeleccionado == "__todos__", !cursoOrigen.isEmpty {
            return viewModel.unidades.filter { $0.curso == cursoOrigen }
        }
        return viewModel.unidades
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ProfileTextField(title: "Nombre", placeholder: "Ej. Ensayo general", text: $nombre)

                    if viewModel.cursoSeleccionado == "__todos__" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Curso")
                                .profileFieldLabel()
                            Picker("Curso", selection: $cursoOrigen) {
                                ForEach(viewModel.cursosDisponibles, id: \.self) { curso in
                                    Text(curso).tag(curso)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Semana ISO")
                                .profileFieldLabel()
                            Stepper("Semana \(semana)", value: $semana, in: 1...53)
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Día")
                                .profileFieldLabel()
                            Picker("Día", selection: $dia) {
                                ForEach(CronoDateHelpers.diasSemana, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }

                        BloqueHoraField(titulo: "Hora", hora: $hora)
                    }

                    ProfileTextField(title: "Duración", placeholder: "Ej. 45 min", text: $duracion)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unidad")
                            .profileFieldLabel()
                        Picker("Unidad", selection: $unidadId) {
                            Text("— Sin unidad —").tag("")
                            ForEach(unidadesDelCurso) { unidad in
                                Text(unidad.nombre).tag(unidad.unidadId)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    if !esNueva {
                        Button(role: .destructive) {
                            confirmandoEliminar = true
                        } label: {
                            Label("Eliminar actividad", systemImage: "trash")
                                .font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(esNueva ? "Nueva actividad" : "Editar actividad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        guardar()
                    }
                    .font(.subheadline.weight(.black))
                    .tint(EPTheme.primary)
                    .disabled(nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("¿Eliminar esta actividad?", isPresented: $confirmandoEliminar, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    viewModel.eliminar(id: actividad.id)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .onAppear {
            nombre = actividad.nombre
            semana = actividad.semana
            dia = actividad.dia
            hora = actividad.hora
            duracion = actividad.duracion
            unidadId = actividad.unidad
            cursoOrigen = actividad.cursoOrigen ?? viewModel.cursosDisponibles.first ?? ""
        }
    }

    private func guardar() {
        var copia = actividad
        copia.nombre = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        copia.semana = semana
        copia.dia = dia
        copia.hora = hora
        copia.duracion = duracion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "45 min" : duracion
        copia.unidad = unidadId
        copia.color = viewModel.colorUnidad(unidadId)
        copia.cursoOrigen = viewModel.cursoSeleccionado == "__todos__" ? cursoOrigen : nil
        viewModel.upsert(copia)
        dismiss()
    }
}
