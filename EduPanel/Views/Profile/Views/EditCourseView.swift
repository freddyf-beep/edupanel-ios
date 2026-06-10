import SwiftUI

struct EditCourseView: View {
    let courseName: String
    let repository: DashboardRepository

    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var selectedColorHex = "#EC4899"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var saveStatus: ProfileSaveStatus = .idle

    // Preset colors from EduPanel design system
    private let colorPresets = [
        "#EC4899", // Rosa
        "#3B82F6", // Azul
        "#10B981", // Verde
        "#F59E0B", // Naranja
        "#8B5CF6", // Morado
        "#EF4444", // Rojo
        "#06B6D4", // Celeste
        "#14B8A6", // Turquesa
        "#6B7280"  // Gris
    ]

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Cargando detalles del curso...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section("Nombre del curso") {
                        TextField("Ej: Música 4to Básico A", text: $newName)
                            .font(.footnote)
                            .autocorrectionDisabled()
                    }

                    Section("Color del curso") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                            ForEach(colorPresets, id: \.self) { hex in
                                Button {
                                    withAnimation(EPTheme.spring) {
                                        selectedColorHex = hex
                                    }
                                } label: {
                                    Circle()
                                        .fill(Color(profileHex: hex))
                                        .frame(height: 44)
                                        .overlay {
                                            if selectedColorHex.uppercased() == hex.uppercased() {
                                                Image(systemName: "checkmark")
                                                    .font(.headline.weight(.black))
                                                    .foregroundStyle(.white)
                                                    .transition(.scale.combined(with: .opacity))
                                            }
                                        }
                                        .overlay {
                                            if selectedColorHex.uppercased() == hex.uppercased() {
                                                Circle()
                                                    .stroke(Color(profileHex: hex).opacity(0.45), lineWidth: 3)
                                                    .padding(-4)
                                            }
                                        }
                                        .shadow(color: Color(profileHex: hex).opacity(0.3), radius: 5, y: 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Impacto de la actualización", systemImage: "info.circle.fill")
                                .font(.caption.weight(.bold))
                            Text("Cambiar el nombre del curso actualizará automáticamente todos los bloques en tu semana, migrará la lista de estudiantes y adaptará las planificaciones de unidad asociadas.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                        }
                    }
                    .listRowBackground(Color.clear)
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
        .navigationTitle("Editar Curso")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Guardar") {
                    Task { await performSave() }
                }
                .font(.subheadline.weight(.black))
                .tint(EPTheme.primary)
                .disabled(isLoading || saveStatus == .saving || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            await loadCourseDetails()
        }
    }

    private func loadCourseDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            let next = try await repository.fetchDashboard()
            // Find a block with this course name to get its color
            let matchingBlock = next.academicClasses.first { $0.resumen == courseName }
            newName = courseName
            selectedColorHex = matchingBlock?.colorHex ?? "#EC4899"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func performSave() async {
        saveStatus = .saving
        errorMessage = nil
        do {
            let cleanNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await repository.updateCourseDetails(
                oldName: courseName,
                newName: cleanNewName,
                newColorHex: selectedColorHex
            )
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
