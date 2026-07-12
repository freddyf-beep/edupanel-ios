import SwiftUI

private struct GuiaUnitOption: Identifiable {
    let id: String
    let name: String
}

struct GuiasHubView: View {
    @Bindable var viewModel: EvaluacionesViewModel
    @State private var searchText = ""
    @State private var typeFilter = "todas"
    @State private var statusFilter = "todas"
    @State private var unitFilter = "todas"
    @State private var guideToDelete: GuiaTemplate?
    @State private var guideToDuplicate: GuiaTemplate?

    private var filteredGuides: [GuiaTemplate] {
        viewModel.guias.filter { guide in
            let query = normalized(searchText)
            let matchesSearch = query.isEmpty || [guide.nombre, guide.objetivo, guide.unidadNombre ?? ""]
                .contains { normalized($0).contains(query) }
            let matchesType = typeFilter == "todas" || guide.tipoGuia == typeFilter
            let matchesStatus = statusFilter == "todas" || guide.estado == statusFilter
            let matchesUnit = unitFilter == "todas" || guide.unidadId == unitFilter
            return matchesSearch && matchesType && matchesStatus && matchesUnit
        }
    }

    private var units: [GuiaUnitOption] {
        var seen = Set<String>()
        return viewModel.guias.compactMap { guide in
            guard let id = guide.unidadId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name = guide.unidadNombre.flatMap { $0.isEmpty ? nil : $0 } ?? id
            return GuiaUnitOption(id: id, name: name)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                EPSectionHeader(title: "Guías de aprendizaje", subtitle: "Contenido didáctico y actividades intercaladas.", icon: "book.pages.fill")
                NavigationLink(value: AppRoute.guiaEditor(
                    guiaId: nil,
                    curso: viewModel.selectedCurso,
                    asignatura: viewModel.activeSubject,
                    scope: viewModel.evaluacionScope
                )) {
                    Label("Nueva guía", systemImage: "plus")
                        .font(.caption.weight(.black)).foregroundStyle(.white)
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .background(EPTheme.primary, in: Capsule())
                }
            }

            metrics

            if viewModel.guiasDesdeCache {
                banner(icon: "icloud.slash.fill", title: "Guías desde caché", message: "Puede faltar algún cambio reciente.", tint: .orange)
            }
            if viewModel.guiasConAdvertencias > 0 {
                banner(icon: "exclamationmark.triangle.fill", title: "Contenido compatible",
                       message: "\(viewModel.guiasConAdvertencias) guía(s) incluyen bloques heredados o futuros.", tint: .orange)
            }

            filters

            if let error = viewModel.guiasErrorMessage {
                EvaluacionesRetryCard(title: "No se pudieron cargar las guías", message: error,
                                      isLoading: viewModel.isLoadingContenido) {
                    Task { await viewModel.loadContenido() }
                }
            } else if viewModel.isLoadingContenido && viewModel.guias.isEmpty {
                EvaluacionesLoadingCard(texto: "Cargando guías...")
            } else if viewModel.guias.isEmpty {
                EPWebCard {
                    EPEmptyState(icon: "book.pages.fill", title: "Aún no hay guías para \(viewModel.selectedCurso)",
                                 message: "Las guías creadas en EduPanel web aparecerán aquí con su contenido y actividades.")
                }
            } else if filteredGuides.isEmpty {
                EPWebCard {
                    EPEmptyState(icon: "line.3.horizontal.decrease.circle", title: "Sin coincidencias",
                                 message: "Prueba otra búsqueda o limpia los filtros.")
                }
            } else {
                LazyVStack(spacing: 11) {
                    ForEach(filteredGuides) { guide in
                        GuiaCard(
                            guide: guide,
                            onDuplicate: { guideToDuplicate = guide },
                            onDelete: { guideToDelete = guide }
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "¿Eliminar esta guía?",
            isPresented: Binding(get: { guideToDelete != nil }, set: { if !$0 { guideToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let guide = guideToDelete { Task { await viewModel.eliminarGuia(guide) } }
                guideToDelete = nil
            }
            Button("Cancelar", role: .cancel) { guideToDelete = nil }
        } message: {
            Text("Se eliminará el documento del usuario y colegio activos. Esta acción no se puede deshacer.")
        }
        .confirmationDialog(
            "Duplicar guía en...",
            isPresented: Binding(get: { guideToDuplicate != nil }, set: { if !$0 { guideToDuplicate = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(viewModel.cursos, id: \.self) { course in
                Button(course) {
                    if let guide = guideToDuplicate { Task { await viewModel.duplicarGuia(guide, cursoDestino: course) } }
                    guideToDuplicate = nil
                }
            }
            Button("Cancelar", role: .cancel) { guideToDuplicate = nil }
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            metric("Total", "\(viewModel.guias.count)", .blue)
            metric("Con contenido", "\(viewModel.guias.filter { $0.totalBloques > 0 }.count)", .purple)
            metric("Actividades", "\(viewModel.guias.reduce(0) { $0 + $1.totalActividades })", .orange)
            metric("Listas", "\(viewModel.guias.filter { $0.estado == "lista" }.count)", .green)
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar guía, objetivo o unidad", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(EPTheme.border))

            HStack(spacing: 8) {
                filterMenu(title: typeLabel, icon: "book.closed.fill") {
                    Button("Todos los tipos") { typeFilter = "todas" }
                    ForEach(["aprendizaje", "refuerzo", "ejercitacion", "evaluacion_formativa"], id: \.self) { value in
                        Button(typeName(value)) { typeFilter = value }
                    }
                }
                filterMenu(title: statusFilter == "todas" ? "Estados" : statusName(statusFilter), icon: "circle.dashed") {
                    Button("Todos los estados") { statusFilter = "todas" }
                    ForEach(["borrador", "lista", "archivada"], id: \.self) { value in
                        Button(statusName(value)) { statusFilter = value }
                    }
                }
                if !units.isEmpty {
                    filterMenu(title: unitFilter == "todas" ? "Unidades" : (units.first { $0.id == unitFilter }?.name ?? "Unidad"),
                               icon: "square.stack.3d.up.fill") {
                        Button("Todas las unidades") { unitFilter = "todas" }
                        ForEach(units, id: \.id) { unit in Button(unit.name) { unitFilter = unit.id } }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.weight(.black)).foregroundStyle(tint)
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func filterMenu<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Label(title, systemImage: icon).font(.caption.weight(.black)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(EPTheme.primary.opacity(0.09), in: Capsule())
        }
        .foregroundStyle(EPTheme.primary)
    }

    private func banner(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.black))
                Text(message).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(11)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var typeLabel: String { typeFilter == "todas" ? "Tipos" : typeName(typeFilter) }
    private func typeName(_ value: String) -> String {
        switch value {
        case "refuerzo": return "Refuerzo"
        case "ejercitacion": return "Ejercitación"
        case "evaluacion_formativa": return "Eval. formativa"
        default: return "Aprendizaje"
        }
    }
    private func statusName(_ value: String) -> String {
        switch value { case "lista": return "Lista"; case "archivada": return "Archivada"; default: return "Borrador" }
    }
    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL")).lowercased()
    }
}

private struct GuiaCard: View {
    let guide: GuiaTemplate
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "book.pages.fill").foregroundStyle(.purple)
                        .frame(width: 34, height: 34).background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if let number = guide.numeroGuia, !number.isEmpty { EPStatusPill(text: number, icon: "number") }
                            EPStatusPill(text: guide.estado.capitalized, icon: guide.estado == "lista" ? "checkmark.circle.fill" : "pencil.circle")
                        }
                        Text(guide.nombre.isEmpty ? "Guía sin nombre" : guide.nombre).font(.subheadline.weight(.black))
                        Text([guide.asignatura, guide.curso, guide.unidadNombre ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Duplicar", systemImage: "doc.on.doc", action: onDuplicate)
                        Button("Eliminar", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis").font(.caption.weight(.black)).foregroundStyle(.secondary)
                            .frame(width: 30, height: 30).background(.secondary.opacity(0.08), in: Circle())
                    }
                }
                if !guide.objetivo.isEmpty { Text(guide.objetivo).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 13) {
                    Label("\(guide.secciones.count) secciones", systemImage: "rectangle.3.group")
                    Label("\(guide.totalActividades) actividades", systemImage: "pencil.and.list.clipboard")
                    if guide.puntajeMaximo > 0 { Label("\(guide.puntajeMaximo.formatted(.number.precision(.fractionLength(0...1)))) pts", systemImage: "star.fill") }
                    if let minutes = guide.tiempoMinutos { Label("\(minutes) min", systemImage: "clock") }
                }
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    NavigationLink(value: AppRoute.guiaDetalle(guiaId: guide.id, scope: guide.scope)) {
                        GuiaActionLabel(title: "Ver", icon: "eye.fill", filled: false)
                    }
                    NavigationLink(value: AppRoute.guiaEditor(
                        guiaId: guide.id, curso: guide.curso, asignatura: guide.asignatura, scope: guide.scope
                    )) {
                        GuiaActionLabel(title: "Editar", icon: "pencil", filled: true)
                    }
                }
            }
        }
    }
}

private struct GuiaActionLabel: View {
    let title: String
    let icon: String
    let filled: Bool

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(filled ? .white : EPTheme.primary)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(filled ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(EPTheme.primary.opacity(0.1)), in: Capsule())
    }
}
