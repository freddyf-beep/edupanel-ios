import SwiftUI

struct ProfileSubjectsTab: View {
    @Bindable var viewModel: ProfileViewModel
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Asignaturas que enseño", icon: "book.closed.fill", hint: "Selector web") {
                let subjects = subjectCandidates(snapshot)

                if subjects.isEmpty {
                    Text("No hay asignaturas detectadas en tu horario. Agrega bloques con asignatura en Mi Semana.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    ProfileSaveBadge(status: viewModel.savePreferencesStatus)

                    VStack(spacing: 8) {
                        ForEach(subjects, id: \.self) { subject in
                            Button {
                                toggleSubject(subject, candidates: subjects)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSubjectEnabled(subject, candidates: subjects) ? "checkmark.square.fill" : "square")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(isSubjectEnabled(subject, candidates: subjects) ? .pink : .secondary)
                                    Text(subject)
                                        .font(.footnote.weight(.semibold))
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            viewModel.draftPreferences.asignaturasHabilitadas = []
                        } label: {
                            Label("Mostrar todas", systemImage: "checklist")
                                .frame(maxWidth: .infinity)
                        }

                        Button {
                            Task { await viewModel.savePreferences() }
                        } label: {
                            Label("Guardar", systemImage: viewModel.savePreferencesStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(viewModel.savePreferencesStatus == .saving)
                    }
                    .font(.footnote.weight(.black))
                    .buttonStyle(.bordered)
                    .tint(.pink)
                }
            }

            ProfileSection(title: "Mapeo de niveles curriculares", icon: "graduationcap.fill", hint: "Mineduc") {
                if snapshot.courses.isEmpty {
                    Text("Primero agrega cursos en Mi Semana.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    ProfileSaveBadge(status: viewModel.saveMappingStatus)

                    VStack(spacing: 10) {
                        ForEach(snapshot.courses, id: \.self) { course in
                            let tipo = viewModel.draftCursoTipos[course] ?? .oficial
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(course)
                                        .font(.footnote.weight(.black))
                                    if tipo == .oficial && (viewModel.draftNivelMapping[course] ?? "").isEmpty {
                                        Text("Falta seleccionar nivel curricular.")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Picker("Tipo curricular", selection: Binding(
                                    get: { viewModel.draftCursoTipos[course] ?? .oficial },
                                    set: { next in setCourseType(next, for: course) }
                                )) {
                                    Text(TipoCurricular.oficial.label).tag(TipoCurricular.oficial)
                                    Text(TipoCurricular.taller.label).tag(TipoCurricular.taller)
                                    Text(TipoCurricular.libre.label).tag(TipoCurricular.libre)
                                }
                                .pickerStyle(.segmented)

                                if tipo == .oficial {
                                    Picker("Nivel curricular", selection: Binding(
                                        get: { viewModel.draftNivelMapping[course] ?? "" },
                                        set: { viewModel.draftNivelMapping[course] = $0 }
                                    )) {
                                        Text("Sin configurar").tag("")
                                        ForEach(CurriculumLevels.all, id: \.self) { level in
                                            Text(level).tag(level)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Label(tipo == .taller ? "Sin nivel curricular para taller/electivo." : "Sin curriculum oficial para uso libre.", systemImage: "info.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Button {
                        Task { await viewModel.saveLevelMapping() }
                    } label: {
                        Label("Guardar niveles", systemImage: viewModel.saveMappingStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .font(.footnote.weight(.black))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(viewModel.saveMappingStatus == .saving)
                }
            }
        }
    }

    private func subjectCandidates(_ snapshot: DashboardSnapshot) -> [String] {
        Array(Set(snapshot.academicClasses.compactMap(\.asignatura) + viewModel.draftPreferences.asignaturasHabilitadas))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
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

    private func setCourseType(_ type: TipoCurricular, for course: String) {
        if type == .oficial {
            viewModel.draftCursoTipos.removeValue(forKey: course)
        } else {
            viewModel.draftCursoTipos[course] = type
            viewModel.draftNivelMapping.removeValue(forKey: course)
        }
    }
}
