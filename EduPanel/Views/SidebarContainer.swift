import SwiftUI

struct SidebarContainer<SidebarContent: View, MainContent: View>: View {
    @Binding var isOpen: Bool
    @Binding var navigationPath: NavigationPath
    
    let sidebar: () -> SidebarContent
    let content: () -> MainContent
    
    @GestureState private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let actualSidebarWidth = min(width * 0.78, 330)
            // 0 = cerrado, 1 = abierto. El scrim y la sombra siguen el dedo
            // durante el arrastre, igual que en el menu de Twitter/X.
            let openProgress = max(0, min(1, isOpen
                ? 1 + dragOffset / actualSidebarWidth
                : dragOffset / actualSidebarWidth))

            ZStack(alignment: .leading) {
                // Main Content View
                content()
                    .frame(width: width, height: geometry.size.height)
                    .overlay(
                        Color.black
                            .opacity(0.45 * openProgress)
                            .ignoresSafeArea()
                            .allowsHitTesting(isOpen)
                            .onTapGesture {
                                withAnimation(EPTheme.spring) {
                                    isOpen = false
                                }
                            }
                    )

                // Sidebar Menu View (full-bleed y bordes cuadrados, como X)
                sidebar()
                    .frame(width: actualSidebarWidth)
                    .ignoresSafeArea()
                    .offset(x: isOpen
                            ? max(-actualSidebarWidth, min(0, dragOffset))
                            : -actualSidebarWidth + max(0, min(actualSidebarWidth, dragOffset)))
                    .shadow(color: Color.black.opacity(0.25 * openProgress), radius: 24, x: 8, y: 0)
            }
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        if isOpen {
                            // If open, only track left drag to close
                            if value.translation.width < 0 {
                                state = value.translation.width
                            }
                        } else {
                            // If closed, only track right drag starting from the left edge (x < 45)
                            if value.startLocation.x < 45 {
                                state = value.translation.width
                            }
                        }
                    }
                    .onEnded { value in
                        let threshold = actualSidebarWidth * 0.35
                        let predicted = value.predictedEndTranslation.width
                        if isOpen {
                            // Dragged or flung to the left enough to close
                            if predicted < -threshold {
                                withAnimation(EPTheme.spring) {
                                    isOpen = false
                                }
                            }
                        } else {
                            // Dragged or flung to the right enough starting from the edge to open
                            if value.startLocation.x < 45 && predicted > threshold {
                                withAnimation(EPTheme.spring) {
                                    isOpen = true
                                }
                            }
                        }
                    },
                including: navigationPath.isEmpty ? .all : .none
            )
        }
    }
}
