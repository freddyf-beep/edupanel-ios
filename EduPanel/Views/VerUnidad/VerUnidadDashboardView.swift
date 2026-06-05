import SwiftUI

struct VerUnidadDashboardView: View {
    let curso: String
    let unidadId: String
    let unidadNombre: String
    let dashboardRepository: DashboardRepository
    let planificacionRepository: PlanificacionRepository
    
    @State private var viewModel: VerUnidadViewModel
    @State private var selectedTab: String // "unidad", "cronograma", "clases"

    init(curso: String, unidadId: String, unidadNombre: String, initialTab: String, dashboardRepository: DashboardRepository, planificacionRepository: PlanificacionRepository) {
        self.curso = curso
        self.unidadId = unidadId
        self.unidadNombre = unidadNombre
        self.dashboardRepository = dashboardRepository
        self.planificacionRepository = planificacionRepository
        self._selectedTab = State(initialValue: initialTab)
        self._viewModel = State(initialValue: VerUnidadViewModel(
            dashboardRepository: dashboardRepository,
            planificacionRepository: planificacionRepository
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segments tab bar
            Picker("Sección", selection: $selectedTab) {
                Text("Unidad").tag("unidad")
                Text("Cronograma").tag("cronograma")
                Text("Clases").tag("clases")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .border(width: 1, edges: [.bottom], color: Color(.separator).opacity(0.15))
            
            // Content
            if viewModel.isLoading {
                ProgressView("Cargando detalles...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    switch selectedTab {
                    case "unidad":
                        VerUnidadBaseView(viewModel: viewModel)
                    case "cronograma":
                        VerUnidadCronogramaView(viewModel: viewModel, selectedTab: $selectedTab)
                    case "clases":
                        VerUnidadClasesView(viewModel: viewModel)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(unidadNombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if !viewModel.saveStatus.isEmpty {
                        Text(viewModel.saveStatus)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.saveStatus.contains("Error") ? .red : .gray, in: Capsule())
                    }
                    
                    Button {
                        Task { await viewModel.saveAll() }
                    } label: {
                        Text("Guardar")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(hex: "#F03E6E"))
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .task {
            await viewModel.load(curso: curso, unidadId: unidadId)
        }
    }
}

// Private separator helper
private struct BorderModifier: ViewModifier {
    var width: CGFloat
    var edges: [Edge]
    var color: Color

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geometry in
                ZStack {
                    ForEach(edges, id: \.self) { edge in
                        self.border(edge: edge, geometry: geometry)
                    }
                }
            }
        )
    }

    private func border(edge: Edge, geometry: GeometryProxy) -> some View {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat

        switch edge {
        case .top:
            x = 0
            y = 0
            w = geometry.size.width
            h = width
        case .bottom:
            x = 0
            y = geometry.size.height - width
            w = geometry.size.width
            h = width
        case .leading:
            x = 0
            y = 0
            w = width
            h = geometry.size.height
        case .trailing:
            x = geometry.size.width - width
            y = 0
            w = width
            h = geometry.size.height
        }

        return Rectangle()
            .fill(color)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }
}

private extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        modifier(BorderModifier(width: width, edges: edges, color: color))
    }
}

// Color Hex Helper (if not globally declared)
private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else {
            self = .pink
            return
        }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else {
            self = .pink
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
