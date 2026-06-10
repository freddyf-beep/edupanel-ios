import SwiftUI
import PhotosUI
import UIKit

struct ProfileIdentityTab: View {
    @Bindable var viewModel: ProfileViewModel

    @State private var logoPrincipalItem: PhotosPickerItem?
    @State private var logoDerechoItem: PhotosPickerItem?

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
                            .scrollContentBackground(.hidden)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    Button {
                        Task { await viewModel.saveProfile() }
                    } label: {
                        Label("Guardar datos profesionales", systemImage: viewModel.saveProfileStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EPTheme.primary)
                    .disabled(viewModel.saveProfileStatus == .saving)
                }
            }

            ProfileSection(title: "Mi colegio", icon: "building.2.fill", hint: "Aparece en exportaciones") {
                ProfileSaveBadge(status: viewModel.saveSchoolStatus)

                VStack(alignment: .leading, spacing: 14) {
                    ProfileTextField(title: "Nombre del colegio", placeholder: "Ej: Colegio San Ignacio", text: $viewModel.draftSchool.nombre)

                    logoRow(
                        titulo: "Logo principal",
                        base64: viewModel.draftSchool.logoBase64,
                        item: $logoPrincipalItem
                    ) {
                        viewModel.draftSchool.logoBase64 = nil
                        logoPrincipalItem = nil
                    }

                    encabezadoBlock

                    Button {
                        Task { await viewModel.saveSchool() }
                    } label: {
                        Label("Guardar colegio", systemImage: viewModel.saveSchoolStatus == .saving ? "hourglass" : "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(EPTheme.primary)
                    .disabled(viewModel.saveSchoolStatus == .saving)
                }
            }
        }
        .onChange(of: logoPrincipalItem) { _, item in
            guard let item else { return }
            Task { await cargarLogo(item) { viewModel.draftSchool.logoBase64 = $0 } }
        }
        .onChange(of: logoDerechoItem) { _, item in
            guard let item else { return }
            Task { await cargarLogo(item) { viewModel.draftSchool.logoDerBase64 = $0 } }
        }
        .onChange(of: viewModel.draftSchool) { old, new in
            if old != new {
                viewModel.saveSchoolDebounced()
            }
        }
    }

    // MARK: - Logos

    private func logoRow(titulo: String, base64: String?, item: Binding<PhotosPickerItem?>, onRemove: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo)
                .profileFieldLabel()

            HStack(spacing: 12) {
                SchoolLogoView(base64: base64)

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: item, matching: .images) {
                        Label(base64 == nil ? "Subir" : "Cambiar", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.black))
                            .foregroundStyle(EPTheme.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(EPTheme.primary.opacity(0.1), in: Capsule())
                    }

                    if base64 != nil {
                        Button {
                            onRemove()
                        } label: {
                            Label("Quitar", systemImage: "xmark")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(.red.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("PNG/JPG · se comprime a 300px automáticamente.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func cargarLogo(_ item: PhotosPickerItem, asignar: @escaping (String) -> Void) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let imagen = UIImage(data: data) else { return }

        let maxPx: CGFloat = 300
        let escala = min(1, maxPx / max(imagen.size.width, imagen.size.height))
        let nuevoTamano = CGSize(width: imagen.size.width * escala, height: imagen.size.height * escala)

        UIGraphicsBeginImageContextWithOptions(nuevoTamano, false, 1.0)
        imagen.draw(in: CGRect(origin: .zero, size: nuevoTamano))
        let redimensionada = UIGraphicsGetImageFromCurrentImageContext() ?? imagen
        UIGraphicsEndImageContext()

        guard let jpeg = redimensionada.jpegData(compressionQuality: 0.85) else { return }
        asignar("data:image/jpeg;base64," + jpeg.base64EncodedString())
    }

    // MARK: - Encabezado de exportaciones

    private var encabezadoBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Encabezado de exportaciones")
                        .font(.footnote.weight(.black))
                    Text("Aparece en planificaciones, pruebas y guías Word.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $viewModel.draftSchool.encabezadoHabilitado)
                    .labelsHidden()
                    .tint(EPTheme.primary)
            }

            if viewModel.draftSchool.encabezadoHabilitado {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lado izquierdo")
                            .profileFieldLabel()
                        TextField("NOMBRE DEL COLEGIO\nDEPARTAMENTO ACADÉMICO", text: $viewModel.draftSchool.encabezadoTextoIzq, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    logoRow(
                        titulo: "Logo lado derecho",
                        base64: viewModel.draftSchool.logoDerBase64,
                        item: $logoDerechoItem
                    ) {
                        viewModel.draftSchool.logoDerBase64 = nil
                        logoDerechoItem = nil
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lado derecho")
                            .profileFieldLabel()
                        TextField("FUNDACIÓN / SOSTENEDOR\nCOMUNA, REGIÓN", text: $viewModel.draftSchool.encabezadoTextoDer, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    encabezadoPreview
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(EPTheme.spring, value: viewModel.draftSchool.encabezadoHabilitado)
    }

    private var encabezadoPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vista previa")
                .profileFieldLabel()

            HStack(alignment: .top, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    if viewModel.draftSchool.logoBase64 != nil {
                        SchoolLogoView(base64: viewModel.draftSchool.logoBase64)
                            .scaleEffect(0.7)
                            .frame(width: 44, height: 44)
                    }
                    Text(viewModel.draftSchool.encabezadoTextoIzq.isEmpty ? "Lado izquierdo…" : viewModel.draftSchool.encabezadoTextoIzq)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(viewModel.draftSchool.encabezadoTextoIzq.isEmpty ? .secondary : .primary)
                        .lineLimit(4)
                }

                Spacer(minLength: 12)

                HStack(alignment: .top, spacing: 8) {
                    Text(viewModel.draftSchool.encabezadoTextoDer.isEmpty ? "Lado derecho…" : viewModel.draftSchool.encabezadoTextoDer)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(viewModel.draftSchool.encabezadoTextoDer.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(4)
                    if viewModel.draftSchool.logoDerBase64 != nil {
                        SchoolLogoView(base64: viewModel.draftSchool.logoDerBase64)
                            .scaleEffect(0.7)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
    }
}
