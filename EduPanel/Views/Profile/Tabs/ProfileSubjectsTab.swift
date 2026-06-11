import SwiftUI

struct ProfileSubjectsTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot

    @Environment(\.displayMode) private var displayMode

    private let gridColumns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Asignaturas que enseño", icon: "book.closed.fill", hint: "Filtra el selector del header") {
                ProfileSaveBadge(status: viewModel.savePreferencesStatus)

                if !displayMode.isSimple {
                    Text("Solo las marcadas aparecerán en el selector de asignatura. Si desmarcas todas, se mostrarán todas (compatibilidad). Tu elección se guarda automáticamente.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                let subjects = subjectCandidates(snapshot)

                if subjects.isEmpty {
                    Text("No hay asignaturas detectadas en tu horario. Agrega bloques con asignatura en Mi Semana.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 8) {
                        ForEach(subjects, id: \.self) { subject in
                            subjectCheckbox(subject, candidates: subjects)
                        }
                    }

                    Button {
                        viewModel.draftPreferences.asignaturasHabilitadas = []
                        viewModel.savePreferencesDebounced()
                    } label: {
                        Label("Mostrar todas", systemImage: "checklist")
                            .font(.footnote.weight(.black))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(EPTheme.primary)
                }
            }

            ProfileSection(title: "Mapeo de niveles curriculares", icon: "graduationcap.fill", hint: "Mineduc") {
                ProfileSaveBadge(status: viewModel.saveMappingStatus)

                if !displayMode.isSimple {
                    Text("Esto permite que el copiloto IA y el currículum carguen los contenidos correctos al planificar. Se guarda automáticamente.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if snapshot.courses.isEmpty {
                    Text("Primero agrega cursos en Mi Semana.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 10) {
                        ForEach(snapshot.courses, id: \.self) { course in
                            mappingRow(course)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Asignaturas habilitadas

    private func subjectCheckbox(_ subject: String, candidates: [String]) -> some View {
        let isEnabled = isSubjectEnabled(subject, candidates: candidates)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                toggleSubject(subject, candidates: candidates)
            }
            viewModel.savePreferencesDebounced()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isEnabled ? EPTheme.primary : .secondary)
                Text(subject)
                    .font(.caption.weight(isEnabled ? .black : .semibold))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                isEnabled ? EPTheme.primary.opacity(0.08) : Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isEnabled ? EPTheme.primary.opacity(0.4) : Color(.separator).opacity(0.1), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func subjectCandidates(_ snapshot: DashboardSnapshot) -> [String] {
        Array(Set(snapshot.academicClasses.compactMap(\.asignatura) + viewModel.draftPreferences.asignaturasHabilitadas))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func isSubjectEnabled(_ subject: String, candidates: [String]) -> Bool {
        let enabled = viewModel.draftPreferences.asignaturasHabilitadas
        return enabled.isEmpty ? candidates.contains(subject) : enabled.contains(subject)
    }

    private func toggleSubject(_ subject: String, candidates: [String]) {
        var enabled = viewModel.draftPreferences.asignaturasHabilitadas
        if enabled.isEmpty {
            enabled = candidates
        }

        if enabled.contains(subject) {
            enabled.removeAll { $0 == subject }
        } else {
            enabled.append(subject)
        }

        viewModel.draftPreferences.asignaturasHabilitadas = enabled.sorted()
    }

    // MARK: - Mapeo de niveles

    private func mappingRow(_ course: String) -> some View {
        let tipo = viewModel.draftCursoTipos[course] ?? .oficial
        let nivel = viewModel.draftNivelMapping[course] ?? ""

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(course)
                    .font(.footnote.weight(.black))
                Spacer()
                if tipo == .oficial && nivel.isEmpty {
                    Label("Sin nivel", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
            }

            Picker("Tipo curricular", selection: tipoBinding(course)) {
                Text(TipoCurricular.oficial.label).tag(TipoCurricular.oficial)
                Text(TipoCurricular.taller.label).tag(TipoCurricular.taller)
                Text(TipoCurricular.libre.label).tag(TipoCurricular.libre)
            }
            .pickerStyle(.segmented)

            if tipo == .oficial {
                Picker("Nivel curricular", selection: nivelBinding(course)) {
                    Text("— Sin configurar —").tag("")
                    ForEach(CurriculumLevels.all, id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(nivel.isEmpty ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
            } else {
                Label(tipo == .taller ? "Sin nivel curricular (taller / electivo)." : "Sin currículum oficial (uso libre).", systemImage: "info.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tipoBinding(_ course: String) -> Binding<TipoCurricular> {
        Binding(
            get: { viewModel.draftCursoTipos[course] ?? .oficial },
            set: { nuevo in
                if nuevo == .oficial {
                    viewModel.draftCursoTipos.removeValue(forKey: course)
                } else {
                    viewModel.draftCursoTipos[course] = nuevo
                    viewModel.draftNivelMapping.removeValue(forKey: course)
                }
                viewModel.saveMappingDebounced()
            }
        )
    }

    private func nivelBinding(_ course: String) -> Binding<String> {
        Binding(
            get: { viewModel.draftNivelMapping[course] ?? "" },
            set: { nuevo in
                if nuevo.isEmpty {
                    viewModel.draftNivelMapping.removeValue(forKey: course)
                } else {
                    viewModel.draftNivelMapping[course] = nuevo
                }
                viewModel.saveMappingDebounced()
            }
        )
    }
}
