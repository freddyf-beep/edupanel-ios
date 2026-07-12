import SwiftUI

enum ItemBankTarget {
    case prueba
    case guia

    var title: String { self == .prueba ? "Banco para Pruebas" : "Banco para Guías" }
}

struct ItemBankSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: ItemBankTarget
    let asignatura: String
    let curso: String
    let onInsert: (ItemBankEntry) -> Bool

    private let repository = ItemBankRepository()

    @State private var entries: [ItemBankEntry] = []
    @State private var search = ""
    @State private var origin: ItemBankOrigin?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var entryToDelete: ItemBankEntry?
    @State private var message: String?

    private var filteredEntries: [ItemBankEntry] {
        entries.filter { entry in
            let matchesOrigin = origin == nil || entry.metadata.origen == origin
            let query = normalized(search)
            let matchesSearch = query.isEmpty || normalized(entry.prompt).contains(query) || normalized(entry.type).contains(query)
            return matchesOrigin && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    contextCard
                    filters

                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    }

                    if isLoading {
                        EvaluacionesLoadingCard(texto: "Cargando banco de ítems...")
                    } else if let errorMessage {
                        EvaluacionesRetryCard(
                            title: "No se pudo cargar el banco",
                            message: errorMessage,
                            isLoading: isLoading
                        ) {
                            Task { await load() }
                        }
                    } else if filteredEntries.isEmpty {
                        EPWebCard {
                            EPEmptyState(
                                icon: "tray.full",
                                title: "Banco sin coincidencias",
                                message: entries.isEmpty
                                    ? "Guarda preguntas o actividades desde sus menús para reutilizarlas aquí."
                                    : "Prueba otra búsqueda o filtro de origen."
                            )
                        }
                    } else {
                        ForEach(filteredEntries) { entry in
                            entryCard(entry)
                        }
                    }
                }
                .padding(16)
            }
            .background(EPTheme.background)
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .confirmationDialog(
            "¿Eliminar del banco?",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                guard let entry = entryToDelete else { return }
                entryToDelete = nil
                Task { await delete(entry) }
            }
            Button("Cancelar", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("La entrada se eliminará del banco compartido entre Pruebas y Guías.")
        }
        .task { await load() }
    }

    private var contextCard: some View {
        EPWebCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(EPTheme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(asignatura) · \(curso)")
                        .font(.caption.weight(.black))
                    Text("Las entradas de Pruebas y Guías compatibles se convierten al insertarlas.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar por enunciado o tipo", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))

            HStack(spacing: 7) {
                filterButton("Todos", selected: origin == nil) { origin = nil }
                filterButton("Pruebas", selected: origin == .prueba) { origin = .prueba }
                filterButton("Guías", selected: origin == .guia) { origin = .guia }
                Spacer()
            }
        }
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(selected ? .white : EPTheme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? EPTheme.primary : EPTheme.primary.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func entryCard(_ entry: ItemBankEntry) -> some View {
        let compatible = isCompatible(entry)
        return EPWebCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: entry.metadata.origen == .prueba ? "doc.text.fill" : "book.pages.fill")
                        .foregroundStyle(entry.metadata.origen == .prueba ? EPTheme.rose : .purple)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            EPStatusPill(text: entry.metadata.origen.label, tint: entry.metadata.origen == .prueba ? EPTheme.rose : .purple)
                            EPStatusPill(text: typeLabel(entry.type), tint: .blue)
                        }
                        Text(entry.prompt.isEmpty ? "Sin enunciado" : entry.prompt)
                            .font(.subheadline.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !entry.metadata.oas.isEmpty {
                            Text(entry.metadata.oas.joined(separator: " · "))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("Eliminar del banco", systemImage: "trash", role: .destructive) {
                            entryToDelete = entry
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 30)
                    }
                }

                Button {
                    if onInsert(entry) {
                        message = target == .prueba ? "Pregunta insertada en la última sección." : "Actividad insertada en la última sección."
                    }
                } label: {
                    Label(
                        compatible ? "Insertar en el documento" : "Tipo no compatible con este editor",
                        systemImage: compatible ? "plus.circle.fill" : "nosign"
                    )
                    .font(.caption.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
                .disabled(!compatible)
            }
        }
    }

    private func isCompatible(_ entry: ItemBankEntry) -> Bool {
        switch target {
        case .prueba: return entry.pruebaDraft() != nil
        case .guia: return entry.guiaActivityDraft() != nil
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entries = try await repository.load(asignatura: asignatura, curso: curso)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ entry: ItemBankEntry) async {
        do {
            try await repository.delete(id: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func typeLabel(_ value: String) -> String {
        if let type = PruebaEditorItemType.resolve(value) { return type.label }
        return GuiaActividadKind.resolve(value).label
    }
}
