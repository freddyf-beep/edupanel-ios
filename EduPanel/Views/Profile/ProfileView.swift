import SwiftUI

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @State private var selectedTab: ProfileTabKey = .resumen
    @State private var showBannerPicker = false
    @Namespace private var profileTabNamespace

    let user: AuthenticatedUser

    init(repository: DashboardRepository, user: AuthenticatedUser) {
        _viewModel = State(initialValue: ProfileViewModel(repository: repository))
        self.user = user
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    profileLoading
                } else if let snapshot = viewModel.snapshot {
                    if let error = viewModel.errorMessage {
                        ProfileErrorBanner(message: error)
                    }

                    profileHero(snapshot)
                    profileTabs
                    selectedContent(snapshot)
                } else {
                    profileEmpty
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Perfil")
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
        .sheet(isPresented: $showBannerPicker) {
            ProfileBannerSheet(viewModel: viewModel)
                .presentationDetents([.medium])
        }
    }

    private func profileHero(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: bannerColors(for: viewModel.draftPreferences.bannerStyle),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 132)

                Button {
                    showBannerPicker = true
                } label: {
                    Image(systemName: "paintpalette.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.18), in: Circle())
                        .padding(12)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    AsyncUserAvatar(user: user)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(user.displayName ?? "Profesor EduPanel")
                            .font(.title2.weight(.black))
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            ProfilePill(text: snapshot.profile.tipoProfesor.isEmpty ? "Docente" : snapshot.profile.tipoProfesor, icon: "briefcase.fill")
                            if !snapshot.profile.especialidad.isEmpty {
                                ProfilePill(text: snapshot.profile.especialidad, icon: "music.note")
                            }
                        }

                        if !snapshot.school.nombre.isEmpty {
                            Label(snapshot.school.nombre, systemImage: "building.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("Configuración")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(snapshot.setupProgress), total: 100)
                        .tint(snapshot.setupProgress == 100 ? .green : EPTheme.primary)
                    Text("\(snapshot.setupProgress)%")
                        .font(.caption.weight(.black))
                        .foregroundStyle(snapshot.setupProgress == 100 ? .green : EPTheme.primary)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ProfileKPI(label: "Cursos", value: "\(snapshot.courses.count)", icon: "folder.fill", color: EPTheme.primary)
                    ProfileKPI(label: "Bloques clase", value: "\(snapshot.academicClasses.count)", icon: "clock.fill", color: .blue, hint: "\(formatMinutes(snapshot.totalAcademicMinutes)) semanales")
                    ProfileKPI(label: "Estudiantes", value: "\(snapshot.totalStudents)", icon: "person.2.fill", color: .green)
                    ProfileKPI(label: "PIE", value: "\(snapshot.totalPIEStudents)", icon: "number", color: .orange, hint: snapshot.totalStudents > 0 ? "\(Int(round(Double(snapshot.totalPIEStudents) / Double(snapshot.totalStudents) * 100)))% del total" : nil)
                    ProfileKPI(label: "Bloques libres", value: "\(snapshot.nonTeachingBlocks.count)", icon: "cup.and.saucer.fill", color: .purple, hint: "\(formatMinutes(snapshot.totalFreeMinutes)) sem.")
                    ProfileKPI(label: "Tu perfil", value: "\(snapshot.setupProgress)%", icon: "sparkles", color: snapshot.setupProgress == 100 ? .green : .teal, hint: snapshot.setupProgress == 100 ? "Perfil completo" : "completado")
                }
            }
            .padding(18)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
                .stroke(Color(.separator).opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }

    private var profileTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProfileTabKey.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(EPTheme.spring) {
                            selectedTab = tab
                        }
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.system(size: 12, weight: .black))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(EPTheme.primary)
                                        .matchedGeometryEffect(id: "profile-tab", in: profileTabNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    @ViewBuilder
    private func selectedContent(_ snapshot: DashboardSnapshot) -> some View {
        switch selectedTab {
        case .resumen:
            ProfileSummaryTab(viewModel: viewModel, snapshot: snapshot, selectedTab: $selectedTab)
        case .semana:
            ProfileWeekTab(viewModel: viewModel, snapshot: snapshot, selectedTab: $selectedTab)
        case .cursos:
            ProfileCoursesTab(viewModel: viewModel, snapshot: snapshot, selectedTab: $selectedTab)
        case .asignaturas:
            ProfileSubjectsTab(viewModel: viewModel, snapshot: snapshot)
        case .identidad:
            ProfileIdentityTab(viewModel: viewModel)
        case .conexiones:
            ProfileConnectionsTab(viewModel: viewModel, snapshot: snapshot)
        }
    }

    private var profileLoading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando Mi Perfil...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var profileEmpty: some View {
        ContentUnavailableView {
            Label("No se pudo cargar Mi Perfil", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("Revisa tu conexión e inténtalo de nuevo.")
        } actions: {
            Button("Reintentar") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(EPTheme.primary)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0 h" }
        let hours = Double(minutes) / 60.0
        if minutes % 60 == 0 {
            return "\(minutes / 60) h"
        }
        return String(format: "%.1f h", hours)
    }

    private func bannerColors(for style: String) -> [Color] {
        switch style {
        case "oceano": return [.cyan, .blue]
        case "atardecer": return [.orange, .pink, .purple]
        case "esmeralda": return [.green, .teal]
        case "indigo": return [.indigo, .purple]
        case "grafito": return [.gray, .black]
        case "bosque": return [.green, .mint]
        case "lavanda": return [.purple, .pink]
        default: return [.pink, .red]
        }
    }
}
