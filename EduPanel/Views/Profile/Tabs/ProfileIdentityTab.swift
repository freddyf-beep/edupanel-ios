import SwiftUI

struct ProfileIdentityTab: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        VStack(spacing: 18) {
            ProfileSection(title: "Datos profesionales", icon: "briefcase.fill", hint: nil) {
                ProfileSaveBadge(status: viewModel.saveProfileStatus)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tipo de docente")
                            .profileFieldLabel()
                        Picker("Tipo de docente", selection: $viewModel.draftProfile.tipoProfesor) {
                            Text("Selecciona tu rol").tag("")
                            Text("Profesor(a) de Ed. General Básica").tag("General Básica")
                            Text("Profesor(a) de Educación Media").tag("Media")
                            Text("Educador(a) Diferencial").tag("Diferencial")
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ProfileTextField(title: "Especialidad / Asignatura", placeholder: "Ej: Música", text: $viewModel.draftProfile.especialidad)
                    ProfileTextField(title: "Estudios y títulos", placeholder: "Profesor de...", text: $viewModel.draftProfile.estudios)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Biografía")
                            .profileFieldLabel()
                        TextEditor(text: $viewModel.draftProfile.biografia)
                            .frame(minHeight: 96)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        Task { await viewModel.saveProfile() }
                    } label: {
                        Label("Guardar datos profesionales", systemImage: viewModel.saveProfileStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(viewModel.saveProfileStatus == .saving)
                }
            }

            ProfileSection(title: "Mi colegio", icon: "building.2.fill", hint: "Exportaciones") {
                ProfileSaveBadge(status: viewModel.saveSchoolStatus)

                VStack(alignment: .leading, spacing: 14) {
                    ProfileTextField(title: "Nombre del colegio", placeholder: "Ej: Colegio San Ignacio", text: $viewModel.draftSchool.nombre)

                    HStack(spacing: 12) {
                        SchoolLogoView(base64: viewModel.draftSchool.logoBase64)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(viewModel.draftSchool.logoBase64 == nil ? "Sin logo principal" : "Logo principal configurado")
                                .font(.footnote.weight(.black))
                            Text("Toca el botón de la derecha para cambiar o subir un nuevo logo.")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink(value: AppRoute.schoolLogo) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.pink)
                                .padding(10)
                                .background(Color.pink.opacity(0.12), in: Circle())
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Toggle("Activar encabezado de exportaciones", isOn: $viewModel.draftSchool.encabezadoHabilitado)
                        .font(.footnote.weight(.black))

                    if viewModel.draftSchool.encabezadoHabilitado {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Lado izquierdo")
                                .profileFieldLabel()
                            TextEditor(text: $viewModel.draftSchool.encabezadoTextoIzq)
                                .frame(minHeight: 74)
                                .padding(8)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Lado derecho")
                                .profileFieldLabel()
                            TextEditor(text: $viewModel.draftSchool.encabezadoTextoDer)
                                .frame(minHeight: 74)
                                .padding(8)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    Button {
                        Task { await viewModel.saveSchool() }
                    } label: {
                        Label("Guardar colegio", systemImage: viewModel.saveSchoolStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(viewModel.saveSchoolStatus == .saving)
                }
            }
        }
    }
}
