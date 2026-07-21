import SwiftUI

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @State private var selectedTab: ProfileTabKey = .resumen
    @State private var showBannerPicker = false
    @Namespace private var profileTabNamespace
    @Environment(\.displayMode) private var displayMode

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
                    if let message = viewModel.operationMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .frame(height: displayMode.isSimple ? 30 : 44)

                Button {
                    showBannerPicker = true
                } label: {
                    Image(systemName: "paintpalette.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.18), in: Circle())
                        .padding(8)
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

                if !displayMode.isSimple {
                    kpiGrid(snapshot)
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

    private func kpiGrid(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 0) {
            Spacer()
            kpiStatItem(
                value: "\(snapshot.courses.count)",
                label: "Cursos",
                icon: "folder.fill",
                color: EPTheme.primary
            )
            
            Spacer()
            Divider()
                .frame(height: 24)
            Spacer()
            
            let hoursText = formatMinutes(snapshot.totalAcademicMinutes)
            kpiStatItem(
                value: hoursText,
                label: "Horas Clase",
                icon: "clock.fill",
                color: .blue
            )
            
            Spacer()
            Divider()
                .frame(height: 24)
            Spacer()
            
            kpiStatItem(
                value: "\(snapshot.totalStudents)",
                label: "Alumnos",
                icon: "person.2.fill",
                color: .green
            )
            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func kpiStatItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
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
            ProfileWeekTab(viewModel: viewModel, snapshot: snapshot, selectedTab: $selectedTab, teacherName: user.displayName ?? "")
        case .cursos:
            ProfileCoursesTab(viewModel: viewModel, snapshot: snapshot, selectedTab: $selectedTab)
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
