import SwiftUI

struct ProfileWeekTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot
    @Binding var selectedTab: ProfileTabKey

    @State private var showWizard = false
    @State private var editingBloque: ClaseHorario?
    @State private var editingGrupo: ProfileNonTeachingGroup?
    @State private var bloqueAEliminar: ClaseHorario?

    var body: some View {
        let nonTeachingList = nonTeachingGroups(snapshot)

        return VStack(spacing: 18) {
            ProfileSection(title: "Constructor de horario", icon: "calendar", hint: "Crea bloques de clases o libres") {
                HStack(alignment: .top) {
                    Text("Vista visual de tu semana. Toca un bloque para editarlo, o crea uno nuevo con el asistente.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ProfileSaveBadge(status: viewModel.saveHorarioStatus)
                        .fixedSize()
                }

                Button {
                    showWizard = true
                } label: {
                    Label("Nuevo bloque", systemImage: "plus")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(EPTheme.primary)
            }

            if !nonTeachingList.isEmpty {
                ProfileSection(title: "Bloques no lectivos", icon: "cup.and.saucer.fill", hint: "\(nonTeachingList.count) grupo\(nonTeachingList.count == 1 ? "" : "s")") {
                    Text("Estos bloques se ven en tu semana, pero no cuentan como clase, pendiente, leccionario ni asistencia.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        ForEach(nonTeachingList) { group in
                            ProfileNonTeachingGroupRow(group: group) {
                                editingGrupo = group
                            }
                        }
                    }
                }
            }

            ProfileSection(title: "Vista calendario", icon: "calendar", hint: "\(snapshot.horario.count) bloques · \(weekHourRange(snapshot).label)") {
                if snapshot.horario.isEmpty {
                    ProfileEmptyAction(
                        icon: "calendar.badge.plus",
                        title: "Tu semana está vacía",
                        message: "Agrega tu primer bloque con el asistente para ver la grilla semanal.",
                        buttonTitle: "Nuevo bloque"
                    ) {
                        showWizard = true
                    }
                } else {
                    ProfileWeekCalendar(snapshot: snapshot) { bloque in
                        editingBloque = bloque
                    }
                }
            }

            ProfileSection(title: "Lista detallada", icon: "clock.fill", hint: "Edita o elimina bloques uno por uno") {
                if snapshot.horario.isEmpty {
                    Text("Sin bloques aún.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(DateHelpers.workdays, id: \.self) { day in
                            let items = snapshot.horario
                                .filter { $0.dia == day }
                                .sorted { $0.horaInicio < $1.horaInicio }

                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(day.uppercased())
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.secondary)
                                    VStack(spacing: 8) {
                                        ForEach(items) { item in
                                            ProfileScheduleRow(item: item) {
                                                editingBloque = item
                                            } onDelete: {
                                                bloqueAEliminar = item
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showWizard) {
            BloqueWizardSheet(viewModel: viewModel)
        }
        .sheet(item: $editingBloque) { bloque in
            BloqueEditorSheet(viewModel: viewModel, bloque: bloque)
        }
        .sheet(item: $editingGrupo) { grupo in
            GrupoNoLectivoSheet(viewModel: viewModel, grupo: grupo)
        }
        .alert("¿Eliminar bloque?", isPresented: Binding(
            get: { bloqueAEliminar != nil },
            set: { if !$0 { bloqueAEliminar = nil } }
        ), presenting: bloqueAEliminar) { bloque in
            Button("Eliminar", role: .destructive) {
                viewModel.removeBloque(id: bloque.id)
                bloqueAEliminar = nil
            }
            Button("Cancelar", role: .cancel) {
                bloqueAEliminar = nil
            }
        } message: { bloque in
            Text("Se quitará \"\(bloque.resumen)\" del \(bloque.dia) \(bloque.timeRange).")
        }
    }

    private func weekHourRange(_ snapshot: DashboardSnapshot) -> (minHour: Int, maxHour: Int, label: String) {
        guard !snapshot.horario.isEmpty else { return (8, 18, "8:00-18:00") }
        let minMinutes = max(0, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaInicio) }.min() ?? 8 * 60) - 30)
        let maxMinutes = min(24 * 60, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaFin) }.max() ?? 18 * 60) + 30)
        let minHour = max(0, minMinutes / 60)
        let maxHour = min(24, Int(ceil(Double(maxMinutes) / 60.0)))
        return (minHour, maxHour, "\(minHour):00-\(maxHour):00")
    }

    private func nonTeachingGroups(_ snapshot: DashboardSnapshot) -> [ProfileNonTeachingGroup] {
        let grouped = Dictionary(grouping: snapshot.nonTeachingBlocks) { item in
            "\(item.tipo.rawValue)::\(item.resumen.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }

        return grouped.compactMap { key, blocks in
            let sorted = blocks.sorted {
                let leftDay = DateHelpers.workdays.firstIndex(of: $0.dia) ?? 0
                let rightDay = DateHelpers.workdays.firstIndex(of: $1.dia) ?? 0
                if leftDay != rightDay { return leftDay < rightDay }
                return $0.horaInicio < $1.horaInicio
            }
            guard let first = sorted.first else { return nil }
            let sameTime = sorted.allSatisfy { $0.horaInicio == first.horaInicio && $0.horaFin == first.horaFin }
            let total = sorted.reduce(0) { total, item in
                total + max(0, DateHelpers.minutes(from: item.horaFin) - DateHelpers.minutes(from: item.horaInicio))
            }

            return ProfileNonTeachingGroup(
                id: key,
                title: first.resumen.isEmpty ? first.tipo.label : first.resumen,
                typeLabel: first.tipo.label,
                colorHex: first.colorHex,
                days: sorted.map(\.dia),
                timeLabel: sameTime ? "\(first.horaInicio)-\(first.horaFin)" : "Horarios distintos",
                totalMinutes: total,
                sameTime: sameTime,
                bloques: sorted
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

struct ProfileNonTeachingGroup: Identifiable {
    let id: String
    let title: String
    let typeLabel: String
    let colorHex: String
    let days: [String]
    let timeLabel: String
    let totalMinutes: Int
    let sameTime: Bool
    let bloques: [ClaseHorario]
}

struct ProfileNonTeachingGroupRow: View {
    let group: ProfileNonTeachingGroup
    var onEdit: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(profileHex: group.colorHex))
                .frame(width: 12, height: 12)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(group.title)
                        .font(.footnote.weight(.black))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    Text(group.typeLabel)
                    Text(group.timeLabel)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Text("\(group.days.joined(separator: ", ")) · \(ProfileFormat.minutes(group.totalMinutes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button(action: onEdit) {
                Text("Editar grupo")
                    .font(.caption.weight(.black))
                    .foregroundStyle(EPTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(EPTheme.primary.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Helpers compartidos de bloques

enum BloqueHelpers {
    static let tiposLectivos: [TipoHorario] = [.clase, .taller, .orientacion]
    static let tiposLibres: [TipoHorario] = [.almuerzo, .planificacion, .recreo, .trabajoColaborativo, .consejo, .noLectivo, .libre]

    static let paleta = ["#3B82F6", "#EC4899", "#10B981", "#F59E0B", "#8B5CF6", "#EF4444", "#06B6D4", "#14B8A6", "#6B7280"]

    static func icono(_ tipo: TipoHorario) -> String {
        switch tipo {
        case .clase: return "book.closed.fill"
        case .taller: return "music.note"
        case .orientacion: return "person.2.fill"
        case .consejo: return "list.clipboard.fill"
        case .trabajoColaborativo: return "person.3.fill"
        case .noLectivo: return "doc.text"
        case .almuerzo: return "cup.and.saucer.fill"
        case .planificacion: return "brain.head.profile"
        case .recreo: return "figure.walk"
        case .libre, .desconocido: return "clock.fill"
        }
    }

    static func etiquetaLibre(_ tipo: TipoHorario) -> String {
        switch tipo {
        case .consejo: return "Consejo de profesores"
        case .trabajoColaborativo: return "Trabajo colaborativo"
        case .noLectivo: return "Bloque no lectivo"
        case .almuerzo: return "Almuerzo"
        case .planificacion: return "Planificación"
        case .recreo: return "Recreo"
        default: return "Bloque libre"
        }
    }

    static let etiquetasLibres = ["Consejo de profesores", "Trabajo colaborativo", "Bloque no lectivo", "Almuerzo", "Planificación", "Recreo", "Bloque libre"]

    static func colision(en horario: [ClaseHorario], dia: String, horaInicio: String, horaFin: String, excluyendo uid: String?) -> ClaseHorario? {
        let inicio = DateHelpers.minutes(from: horaInicio)
        let fin = DateHelpers.minutes(from: horaFin)
        return horario.first { bloque in
            guard bloque.dia == dia, bloque.id != uid else { return false }
            let bInicio = DateHelpers.minutes(from: bloque.horaInicio)
            let bFin = DateHelpers.minutes(from: bloque.horaFin)
            return inicio < bFin && fin > bInicio
        }
    }

    static func fecha(de hora: String) -> Date {
        let partes = hora.split(separator: ":").compactMap { Int($0) }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = partes.first ?? 8
        comps.minute = partes.count > 1 ? partes[1] : 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    static func hora(de fecha: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: fecha)
        return String(format: "%02d:%02d", comps.hour ?? 8, comps.minute ?? 0)
    }

    static func nuevoUid(dia: String, resumen: String, indice: Int) -> String {
        let slug = resumen.lowercased().replacingOccurrences(of: " ", with: "")
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(dia.lowercased().prefix(3))-\(slug)-\(stamp)-\(indice)"
    }

    @MainActor
    static func sugerenciasAsignatura(_ viewModel: ProfileViewModel) -> [String] {
        let enUso = viewModel.horarioActual.compactMap { $0.asignatura?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let habilitadas = viewModel.draftPreferences.asignaturasHabilitadas
        return Array(Set(enUso + habilitadas))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct BloqueHoraField: View {
    let titulo: String
    @Binding var hora: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo)
                .profileFieldLabel()
            DatePicker(
                "",
                selection: Binding(
                    get: { BloqueHelpers.fecha(de: hora) },
                    set: { hora = BloqueHelpers.hora(de: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct BloqueColorPalette: View {
    @Binding var colorHex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .profileFieldLabel()
            ReplicaFlowLayout(spacing: 10) {
                ForEach(BloqueHelpers.paleta, id: \.self) { hex in
                    let isSelected = colorHex.uppercased() == hex.uppercased()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            colorHex = hex
                        }
                    } label: {
                        Circle()
                            .fill(Color(profileHex: hex))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                if isSelected {
                                    Circle()
                                        .stroke(Color(profileHex: hex).opacity(0.4), lineWidth: 3)
                                        .padding(-4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct BloqueColisionAviso: View {
    let colision: ClaseHorario

    var body: some View {
        Label("Choca con \(colision.resumen) (\(colision.horaInicio)–\(colision.horaFin))", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Wizard de 4 pasos

struct BloqueWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProfileViewModel
    var presetCurso: String? = nil
    var presetAsignatura: String? = nil

    @State private var paso = 1
    @State private var tipo: TipoHorario = .clase
    @State private var dias: Set<String> = []
    @State private var horaInicio = "08:00"
    @State private var horaFin = "09:30"
    @State private var resumen = ""
    @State private var asignatura = ""
    @State private var colorHex = "#3B82F6"

    private var tipoLibre: Bool { tipo.isFreeBlock }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pasoHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch paso {
                        case 1: pasoTipo
                        case 2: pasoDias
                        case 3: pasoHorario
                        default: pasoDetalles
                        }
                    }
                    .padding(18)
                }

                footer
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nuevo bloque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            resumen = presetCurso ?? ""
            asignatura = presetAsignatura ?? ""
        }
    }

    private var pasoHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Paso \(paso) de 4")
                    .font(.caption.weight(.black))
                    .foregroundStyle(EPTheme.primary)
                Spacer()
                Text(tituloPaso)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { index in
                    Capsule()
                        .fill(index <= paso ? EPTheme.primary : Color(.systemGray5))
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .animation(EPTheme.spring, value: paso)
    }

    private var tituloPaso: String {
        switch paso {
        case 1: return "Tipo de bloque"
        case 2: return "Días de la semana"
        case 3: return "Horario"
        default: return "Detalles"
        }
    }

    private var pasoTipo: some View {
        VStack(alignment: .leading, spacing: 14) {
            tipoGrupo(titulo: "Bloques con curso", tipos: BloqueHelpers.tiposLectivos)
            tipoGrupo(titulo: "Bloques no lectivos", tipos: BloqueHelpers.tiposLibres)
        }
    }

    private func tipoGrupo(titulo: String, tipos: [TipoHorario]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(tipos, id: \.self) { opcion in
                    let isSelected = tipo == opcion
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tipo = opcion
                            if opcion.isFreeBlock {
                                let actual = resumen.trimmingCharacters(in: .whitespacesAndNewlines)
                                if actual.isEmpty || BloqueHelpers.etiquetasLibres.contains(actual) {
                                    resumen = BloqueHelpers.etiquetaLibre(opcion)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: BloqueHelpers.icono(opcion))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    isSelected ? AnyShapeStyle(EPTheme.primary) : AnyShapeStyle(Color(.systemGray6)),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            Text(opcion == .libre ? "Bloque libre" : opcion.label)
                                .font(.footnote.weight(isSelected ? .black : .semibold))
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(EPTheme.primary)
                            }
                        }
                        .padding(11)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? EPTheme.primary.opacity(0.4) : Color(.separator).opacity(0.1), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pasoDias: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selecciona uno o más días. Se creará un bloque por cada día.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(DateHelpers.workdays, id: \.self) { dia in
                    let isSelected = dias.contains(dia)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isSelected {
                                dias.remove(dia)
                            } else {
                                dias.insert(dia)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(isSelected ? EPTheme.primary : .secondary)
                            Text(dia)
                                .font(.footnote.weight(isSelected ? .black : .semibold))
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? EPTheme.primary.opacity(0.4) : Color(.separator).opacity(0.1), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pasoHorario: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BloqueHoraField(titulo: "Inicio", hora: $horaInicio)
                BloqueHoraField(titulo: "Fin", hora: $horaFin)
            }

            if DateHelpers.minutes(from: horaFin) <= DateHelpers.minutes(from: horaInicio) {
                Label("La hora de fin debe ser posterior al inicio.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
            }

            ForEach(Array(dias).sorted(by: ordenDias), id: \.self) { dia in
                if let colision = BloqueHelpers.colision(en: viewModel.horarioActual, dia: dia, horaInicio: horaInicio, horaFin: horaFin, excluyendo: nil) {
                    BloqueColisionAviso(colision: colision)
                }
            }
        }
    }

    private var pasoDetalles: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tipoLibre ? "Etiqueta" : "Curso")
                    .profileFieldLabel()
                TextField(tipoLibre ? BloqueHelpers.etiquetaLibre(tipo) : "Ej. 4° A", text: $resumen)
                    .textFieldStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .disabled(presetCurso != nil && !tipoLibre)
            }

            if !tipoLibre {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Asignatura")
                        .profileFieldLabel()
                    TextField("Ej. Música, Lenguaje…", text: $asignatura)
                        .textFieldStyle(.plain)
                        .font(.footnote.weight(.semibold))
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .disabled(presetAsignatura != nil)

                    let sugerencias = BloqueHelpers.sugerenciasAsignatura(viewModel)
                    if presetAsignatura == nil, !sugerencias.isEmpty {
                        ReplicaFlowLayout(spacing: 6) {
                            ForEach(sugerencias, id: \.self) { sugerencia in
                                Button {
                                    asignatura = sugerencia
                                } label: {
                                    Text(sugerencia)
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(EPTheme.primary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(EPTheme.primary.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            BloqueColorPalette(colorHex: $colorHex)

            resumenFinal
        }
    }

    private var resumenFinal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resumen")
                .profileFieldLabel()
            VStack(alignment: .leading, spacing: 4) {
                Label("\(tipo == .libre ? "Bloque libre" : tipo.label) · \(resumen.isEmpty ? "—" : resumen)", systemImage: BloqueHelpers.icono(tipo))
                Label(Array(dias).sorted(by: ordenDias).joined(separator: ", "), systemImage: "calendar")
                Label("\(horaInicio) – \(horaFin)", systemImage: "clock")
                if !tipoLibre, !asignatura.isEmpty {
                    Label(asignatura, systemImage: "book.closed")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if paso > 1 {
                Button {
                    withAnimation(EPTheme.spring) { paso -= 1 }
                } label: {
                    Label("Atrás", systemImage: "chevron.left")
                        .font(.footnote.weight(.black))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }

            Button {
                if paso < 4 {
                    withAnimation(EPTheme.spring) { paso += 1 }
                } else {
                    crearBloques()
                }
            } label: {
                Label(paso < 4 ? "Continuar" : "Crear bloque\(dias.count == 1 ? "" : "s")", systemImage: paso < 4 ? "chevron.right" : "plus")
                    .font(.footnote.weight(.black))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
            .disabled(!puedeContinuar)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .sensoryFeedback(.selection, trigger: paso)
    }

    private var puedeContinuar: Bool {
        switch paso {
        case 2:
            return !dias.isEmpty
        case 3:
            return DateHelpers.minutes(from: horaFin) > DateHelpers.minutes(from: horaInicio)
        case 4:
            let nombreOk = !resumen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let asignaturaOk = tipoLibre || !asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return nombreOk && asignaturaOk
        default:
            return true
        }
    }

    private func crearBloques() {
        let nombre = resumen.trimmingCharacters(in: .whitespacesAndNewlines)
        let materia = asignatura.trimmingCharacters(in: .whitespacesAndNewlines)
        for (indice, dia) in Array(dias).sorted(by: ordenDias).enumerated() {
            let bloque = ClaseHorario(
                id: BloqueHelpers.nuevoUid(dia: dia, resumen: nombre, indice: indice),
                resumen: nombre,
                dia: dia,
                horaInicio: horaInicio,
                horaFin: horaFin,
                colorHex: colorHex,
                tipo: tipo,
                asignatura: tipoLibre ? nil : materia
            )
            viewModel.upsertBloque(bloque)
        }
        dismiss()
    }

    private func ordenDias(_ lhs: String, _ rhs: String) -> Bool {
        (DateHelpers.workdays.firstIndex(of: lhs) ?? 9) < (DateHelpers.workdays.firstIndex(of: rhs) ?? 9)
    }
}

// MARK: - Editor de bloque individual

struct BloqueEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProfileViewModel
    let bloque: ClaseHorario

    @State private var dia = "Lunes"
    @State private var tipo: TipoHorario = .clase
    @State private var resumen = ""
    @State private var asignatura = ""
    @State private var horaInicio = "08:00"
    @State private var horaFin = "09:30"
    @State private var colorHex = "#3B82F6"
    @State private var confirmandoEliminar = false

    private var tipoLibre: Bool { tipo.isFreeBlock }

    private var colision: ClaseHorario? {
        BloqueHelpers.colision(en: viewModel.horarioActual, dia: dia, horaInicio: horaInicio, horaFin: horaFin, excluyendo: bloque.id)
    }

    private var puedeGuardar: Bool {
        !resumen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        DateHelpers.minutes(from: horaFin) > DateHelpers.minutes(from: horaInicio) &&
        (tipoLibre || !asignatura.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Día")
                                .profileFieldLabel()
                            Picker("Día", selection: $dia) {
                                ForEach(DateHelpers.workdays, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tipo")
                                .profileFieldLabel()
                            Picker("Tipo", selection: $tipo) {
                                ForEach(BloqueHelpers.tiposLectivos + BloqueHelpers.tiposLibres, id: \.self) { opcion in
                                    Text(opcion == .libre ? "Bloque libre" : opcion.label).tag(opcion)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }

                    ProfileTextField(title: tipoLibre ? "Etiqueta" : "Curso", placeholder: tipoLibre ? "Ej. Almuerzo" : "Ej. 4° A", text: $resumen)

                    if !tipoLibre {
                        ProfileTextField(title: "Asignatura", placeholder: "Ej. Música", text: $asignatura)
                    }

                    HStack(spacing: 10) {
                        BloqueHoraField(titulo: "Inicio", hora: $horaInicio)
                        BloqueHoraField(titulo: "Fin", hora: $horaFin)
                    }

                    if let colision {
                        BloqueColisionAviso(colision: colision)
                    }

                    BloqueColorPalette(colorHex: $colorHex)

                    Button(role: .destructive) {
                        confirmandoEliminar = true
                    } label: {
                        Label("Eliminar bloque", systemImage: "trash")
                            .font(.footnote.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Editar bloque")
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
                    .disabled(!puedeGuardar)
                }
            }
            .confirmationDialog("¿Eliminar este bloque?", isPresented: $confirmandoEliminar, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    viewModel.removeBloque(id: bloque.id)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .onAppear {
            dia = bloque.dia
            tipo = bloque.tipo == .desconocido ? .clase : bloque.tipo
            resumen = bloque.resumen
            asignatura = bloque.asignatura ?? ""
            horaInicio = bloque.horaInicio
            horaFin = bloque.horaFin
            colorHex = bloque.colorHex
        }
    }

    private func guardar() {
        let actualizado = ClaseHorario(
            id: bloque.id,
            resumen: resumen.trimmingCharacters(in: .whitespacesAndNewlines),
            dia: dia,
            horaInicio: horaInicio,
            horaFin: horaFin,
            colorHex: colorHex,
            tipo: tipo,
            asignatura: tipoLibre ? nil : asignatura.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        viewModel.upsertBloque(actualizado)
        dismiss()
    }
}

// MARK: - Editor de grupo no lectivo

struct GrupoNoLectivoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: ProfileViewModel
    let grupo: ProfileNonTeachingGroup

    @State private var etiqueta = ""
    @State private var horaInicio = "13:00"
    @State private var horaFin = "14:00"
    @State private var colorHex = "#6B7280"
    @State private var confirmandoEliminar = false

    private var puedeGuardar: Bool {
        !etiqueta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        DateHelpers.minutes(from: horaFin) > DateHelpers.minutes(from: horaInicio)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Se aplicará a \(grupo.days.joined(separator: ", ")).")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ProfileTextField(title: "Etiqueta", placeholder: grupo.typeLabel, text: $etiqueta)

                    HStack(spacing: 10) {
                        BloqueHoraField(titulo: "Inicio", hora: $horaInicio)
                        BloqueHoraField(titulo: "Fin", hora: $horaFin)
                    }

                    if !grupo.sameTime {
                        Label("Este grupo tenía horarios distintos por día. Al guardar, todos quedarán con el mismo inicio y fin.", systemImage: "info.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    BloqueColorPalette(colorHex: $colorHex)

                    Button(role: .destructive) {
                        confirmandoEliminar = true
                    } label: {
                        Label("Eliminar grupo (\(grupo.bloques.count) bloques)", systemImage: "trash")
                            .font(.footnote.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Editar bloque no lectivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aplicar al grupo") {
                        aplicar()
                    }
                    .font(.subheadline.weight(.black))
                    .tint(EPTheme.primary)
                    .disabled(!puedeGuardar)
                }
            }
            .confirmationDialog("¿Eliminar \(grupo.bloques.count) bloque(s) de \"\(grupo.title)\"?", isPresented: $confirmandoEliminar, titleVisibility: .visible) {
                Button("Eliminar grupo", role: .destructive) {
                    grupo.bloques.forEach { viewModel.removeBloque(id: $0.id) }
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            etiqueta = grupo.title
            colorHex = grupo.colorHex
            if grupo.sameTime, let primero = grupo.bloques.first {
                horaInicio = primero.horaInicio
                horaFin = primero.horaFin
            }
        }
    }

    private func aplicar() {
        let nombre = etiqueta.trimmingCharacters(in: .whitespacesAndNewlines)
        for bloque in grupo.bloques {
            viewModel.upsertBloque(bloque.copia(
                resumen: nombre,
                horaInicio: horaInicio,
                horaFin: horaFin,
                colorHex: colorHex
            ))
        }
        dismiss()
    }
}

// MARK: - Calendario semanal

struct ProfileWeekCalendar: View {
    let snapshot: DashboardSnapshot
    var onSelect: (ClaseHorario) -> Void = { _ in }

    private let dayWidth: CGFloat = 128
    private let hourColumnWidth: CGFloat = 52
    private let pixelsPerMinute: CGFloat = 0.92

    var body: some View {
        let range = hourRange
        let totalMinutes = max(60, (range.maxHour - range.minHour) * 60)
        let calendarHeight = CGFloat(totalMinutes) * pixelsPerMinute

        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 6) {
                    Text("")
                        .frame(height: 28)
                    ZStack(alignment: .topLeading) {
                        ForEach(range.minHour...range.maxHour, id: \.self) { hour in
                            Text("\(hour):00")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)
                                .offset(y: CGFloat((hour - range.minHour) * 60) * pixelsPerMinute - 2)
                        }
                    }
                    .frame(width: hourColumnWidth, height: calendarHeight, alignment: .topLeading)
                }

                ForEach(DateHelpers.workdays, id: \.self) { day in
                    VStack(spacing: 6) {
                        Text(day)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.primary)
                            .textCase(.uppercase)
                            .frame(width: dayWidth, height: 28)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(.systemGroupedBackground))

                            ForEach(0...(range.maxHour - range.minHour), id: \.self) { index in
                                Rectangle()
                                    .fill(Color(.separator).opacity(0.35))
                                    .frame(height: 1)
                                    .offset(y: CGFloat(index * 60) * pixelsPerMinute)
                            }

                            ForEach(blocks(for: day)) { item in
                                Button {
                                    onSelect(item)
                                } label: {
                                    calendarBlock(item, minHour: range.minHour)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: dayWidth, height: calendarHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .padding(8)
        }
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var hourRange: (minHour: Int, maxHour: Int) {
        guard !snapshot.horario.isEmpty else { return (8, 18) }
        let minMinutes = max(0, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaInicio) }.min() ?? 8 * 60) - 30)
        let maxMinutes = min(24 * 60, (snapshot.horario.map { DateHelpers.minutes(from: $0.horaFin) }.max() ?? 18 * 60) + 30)
        return (max(0, minMinutes / 60), min(24, Int(ceil(Double(maxMinutes) / 60.0))))
    }

    private func blocks(for day: String) -> [ClaseHorario] {
        snapshot.horario
            .filter { $0.dia == day }
            .sorted { $0.horaInicio < $1.horaInicio }
    }

    private func calendarBlock(_ item: ClaseHorario, minHour: Int) -> some View {
        let start = DateHelpers.minutes(from: item.horaInicio)
        let end = DateHelpers.minutes(from: item.horaFin)
        let top = max(0, CGFloat(start - minHour * 60) * pixelsPerMinute)
        let height = max(28, CGFloat(max(15, end - start)) * pixelsPerMinute - 2)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: BloqueHelpers.icono(item.tipo))
                    .font(.system(size: 9, weight: .black))
                Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                    .font(.system(size: 10, weight: .black))
                    .lineLimit(1)
            }

            if let asignatura = item.asignatura, !asignatura.isEmpty, height >= 38 {
                Text(asignatura)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
            }

            if height >= 48 {
                Text(item.timeRange)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: dayWidth - 8, height: height, alignment: .topLeading)
        .background(Color(profileHex: item.colorHex).opacity(item.tipo.isFreeBlock ? 0.88 : 1.0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
        .offset(x: 4, y: top)
    }
}

struct ProfileScheduleRow: View {
    let item: ClaseHorario
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(String(item.horaInicio.prefix(2)))
                    .font(.headline.weight(.black))
                Text(String(item.horaInicio.suffix(2)))
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 50)
            .background(Color(profileHex: item.colorHex), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                        .font(.footnote.weight(.black))
                        .lineLimit(1)
                    if let asignatura = item.asignatura, !asignatura.isEmpty {
                        Text(asignatura)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(EPTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(EPTheme.primary.opacity(0.1), in: Capsule())
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.timeRange)
                    Text(item.tipo.label)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.systemGray5), in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
                    .background(.red.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
