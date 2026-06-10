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
            let actualSidebarWidth = min(width * 0.82, 290)
            
            ZStack(alignment: .leading) {
                // Main Content View
                content()
                    .frame(width: width, height: geometry.size.height)
                    .overlay(
                        Group {
                            if isOpen {
                                Color.black
                                    .opacity(0.3)
                                    .ignoresSafeArea()
                                    .transition(.opacity)
                                    .onTapGesture {
                                        withAnimation(EPTheme.spring) {
                                            isOpen = false
                                        }
                                    }
                            }
                        }
                    )

                // Sidebar Menu View
                sidebar()
                    .frame(width: actualSidebarWidth)
                    .clipShape(.rect(bottomTrailingRadius: 28, topTrailingRadius: 28))
                    .offset(x: isOpen
                            ? max(-actualSidebarWidth, min(0, dragOffset))
                            : -actualSidebarWidth + max(0, min(actualSidebarWidth, dragOffset)))
                    .shadow(color: Color.black.opacity(isOpen ? 0.22 : 0.0), radius: 24, x: 8, y: 0)
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
                        if isOpen {
                            // Dragged to the left enough to close
                            if value.translation.width < -threshold {
                                withAnimation(EPTheme.spring) {
                                    isOpen = false
                                }
                            }
                        } else {
                            // Dragged to the right enough starting from the edge to open
                            if value.startLocation.x < 45 && value.translation.width > threshold {
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
