import SwiftUI
import CoreModels

struct DrawerSplitContainer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    let sidebar: Sidebar
    let content: Content

    init(isOpen: Binding<Bool>, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content) {
        self._isOpen = isOpen
        self.sidebar = sidebar()
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .disabled(isOpen)

            if isOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isOpen = false
                        }
                    }
            }

            sidebar
                .frame(maxWidth: 320)
                .offset(x: isOpen ? 0 : -340)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 8, y: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isOpen)
    }
}

#Preview {
    DrawerSplitContainer(isOpen: .constant(true)) {
        SidebarDrawerView(
            sessions: MockSessionListViewModel.sampleSessions,
            selectedSessionID: MockSessionListViewModel.sampleSessions.first?.id ?? UUID(),
            isRecording: true,
            searchText: .constant(""),
            onSelectSession: { _ in },
            onOpenMe: {}
        )
    } content: {
        ZStack {
            BackgroundAtmosphere()
            Text("Main Content")
                .foregroundColor(.white)
        }
    }
}
