import SwiftUI
import PhotosUI

struct SchoolLogoEditView: View {
    let repository: DashboardRepository

    @Environment(\.dismiss) private var dismiss

    @State private var school: InfoColegio = .empty
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveStatus: ProfileSaveStatus = .idle

    // PhotosPicker states
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando datos del colegio...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 24) {
                    // Logo Preview Card
                    VStack(spacing: 14) {
                        SchoolLogoView(base64: school.logoBase64)
                            .scaleEffect(1.4)
                            .frame(width: 124, height: 124)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color(.separator).opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

                        Text(school.logoBase64 == nil ? "Sin logo personalizado" : "Logo del colegio configurado")
                            .font(.subheadline.weight(.black))
                    }
                    .padding(.top, 28)

                    VStack(spacing: 12) {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Label("Seleccionar de fotos", systemImage: "photo.fill.on.rectangle.fill")
                                .font(.footnote.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(EPTheme.primary)

                        if school.logoBase64 != nil {
                            Button(role: .destructive) {
                                school.logoBase64 = nil
                                selectedItem = nil
                                selectedImageData = nil
                            } label: {
                                Label("Eliminar logo", systemImage: "trash.fill")
                                    .font(.footnote.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 24)

                    Form {
                        Section("Información del Colegio") {
                            TextField("Nombre de la institución", text: $school.nombre)
                                .font(.footnote)
                                .disabled(isSaving)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }

            if let errorMessage {
                ProfileErrorBanner(message: errorMessage)
                    .padding()
            }

            if saveStatus != .idle {
                HStack {
                    ProfileSaveBadge(status: saveStatus)
                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .navigationTitle("Logo del Colegio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Guardar") {
                    Task { await performSave() }
                }
                .font(.subheadline.weight(.black))
                .tint(EPTheme.primary)
                .disabled(isLoading || saveStatus == .saving || school.nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            await loadSchoolData()
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let newItem {
                    await loadImage(from: newItem)
                }
            }
        }
    }

    private func loadSchoolData() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard()
            school = next.school
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadImage(from item: PhotosPickerItem) async {
        isSaving = true
        errorMessage = nil
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = data
                // Limit size of image to avoid Firestore limit (4MB document limit, but let's keep base64 image < 1MB)
                // Downsample image if needed, or simple convert to base64
                if let uiImage = UIImage(data: data) {
                    // Resize to max 300x300
                    let resized = resizeImage(uiImage, targetSize: CGSize(width: 300, height: 300))
                    if let resizedData = resized.jpegData(compressionQuality: 0.6) {
                        let base64 = resizedData.base64EncodedString()
                        school.logoBase64 = "data:image/jpeg;base64," + base64
                    }
                }
            }
        } catch {
            errorMessage = "No se pudo cargar la imagen: " + error.localizedDescription
        }
        isSaving = false
    }

    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        let rect = CGRect(origin: .zero, size: newSize)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }

    private func performSave() async {
        saveStatus = .saving
        errorMessage = nil
        do {
            try await repository.saveSchool(school)
            saveStatus = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                saveStatus = .idle
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            saveStatus = .error
        }
    }
}
