import SwiftUI

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    let user: AuthenticatedUser

    init(repository: DashboardRepository, user: AuthenticatedUser) {
        _viewModel = State(initialValue: DashboardViewModel(repository: repository))
        self.user = user
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if viewModel.isLoading && viewModel.snapshot == nil {
                    loadingState
                } else if let snapshot = viewModel.snapshot {
                    dashboardContent(snapshot)
                } else {
                    emptyState
                }
            }
            .padding(18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Inicio")
        .task { await viewModel.load() }
        .refreshable { await viewModel.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting)
                .font(.largeTitle.bold())

            Text(Date.now.formatted(date: .complete, time: .shortened))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func dashboardContent(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if snapshot.horario.isEmpty {
                noScheduleCard
            } else {
                currentClassCard(snapshot)
                progressCard(snapshot)
                todayClassesSection(snapshot)
                pendingSection(snapshot)
                quickActions
            }
        }
    }

    private func currentClassCard(_ snapshot: DashboardSnapshot) -> some View {
        let item = snapshot.currentOrNextClass()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ahora / siguiente", systemImage: "clock.fill")
                    .font(.headline)
                Spacer()
                Text(snapshot.profile.tipoProfesor)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if let item {
                HStack(alignment: .top, spacing: 12) {
                    ColorChip(hex: item.colorHex)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                            .font(.title3.bold())
                        Text(item.timeRange)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.tipo.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(item.tipo.isFreeBlock ? .secondary : .pink)
                    }
                    Spacer()
                }
            } else {
                Text("No quedan bloques programados para hoy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func progressCard(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progreso del dia")
                    .font(.headline)
                Spacer()
                Text(viewModel.progressTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: viewModel.progressValue)
                .tint(.pink)

            HStack(spacing: 12) {
                StatPill(title: "Cursos", value: "\(Set(snapshot.academicTodayClasses.map(\.resumen)).count)")
                StatPill(title: "Pendientes", value: "\(snapshot.pendingClasses.count)")
                StatPill(title: "Alumnos", value: "\(snapshot.studentCounts.values.reduce(0, +))")
            }
        }
        .cardStyle()
    }

    private func todayClassesSection(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clases de hoy")
                .font(.headline)

            if snapshot.todayClasses.isEmpty {
                Text("No hay bloques para hoy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(snapshot.todayClasses) { item in
                        ClassRow(
                            item: item,
                            isCompleted: snapshot.classState[item.id] == true,
                            studentCount: snapshot.studentCounts[item.resumen] ?? 0
                        ) {
                            Task { await viewModel.toggleCompletion(for: item) }
                        }
                    }
                }
            }
        }
    }

    private func pendingSection(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pendientes")
                .font(.headline)

            if snapshot.pendingClasses.isEmpty {
                Label("No tienes clases lectivas pendientes.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.pendingClasses) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.orange)
                            Text("\(item.resumen) - \(item.timeRange)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accesos rapidos")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickActionCard(title: "Planificar", icon: "book.closed.fill", color: .pink)
                QuickActionCard(title: "Evaluar", icon: "checklist.checked", color: .indigo)
                QuickActionCard(title: "Clases", icon: "calendar.badge.clock", color: .orange)
                QuickActionCard(title: "Perfil", icon: "person.crop.circle.fill", color: .green)
            }
        }
    }

    private var noScheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title)
                .foregroundStyle(.pink)
            Text("Configura tu horario")
                .font(.title3.bold())
            Text("Cuando agregues tus bloques en la web, EduPanel los mostrara aqui para seguir tu jornada.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Sin datos para mostrar")
                .font(.headline)
            Button("Reintentar") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Cargando tu jornada...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        if hour < 12 {
            prefix = "Buenos dias"
        } else if hour < 19 {
            prefix = "Buenas tardes"
        } else {
            prefix = "Buenas noches"
        }
        return "\(prefix), \(user.firstName)"
    }
}

private struct ClassRow: View {
    let item: ClaseHorario
    let isCompleted: Bool
    let studentCount: Int
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!item.isAcademic)

            ColorChip(hex: item.colorHex)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.resumen.isEmpty ? item.tipo.label : item.resumen)
                    .font(.subheadline.bold())
                    .strikethrough(isCompleted)
                Text("\(item.timeRange) - \(item.tipo.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.isAcademic {
                Label("\(studentCount)", systemImage: "person.2.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ColorChip: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: hex))
            .frame(width: 12, height: 42)
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct QuickActionCard: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension View {
    func cardStyle() -> some View {
        self.padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
