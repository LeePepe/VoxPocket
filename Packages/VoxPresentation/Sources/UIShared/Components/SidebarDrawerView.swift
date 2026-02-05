import SwiftUI
import CoreModels

struct SidebarDrawerView: View {
    let sessions: [Session]
    let selectedSessionID: UUID
    let isRecording: Bool
    @Binding var searchText: String
    let onSelectSession: (Session) -> Void
    let onOpenMe: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeaderView(isRecording: isRecording)

            SearchField(text: $searchText)
                .padding(.horizontal, 18)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(sessions) { session in
                        Button {
                            onSelectSession(session)
                        } label: {
                            HistoryRowView(session: session, isSelected: session.id == selectedSessionID)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            Button(action: onOpenMe) {
                MeEntryRow()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SidebarBackground())
    }
}

struct SidebarHeaderView: View {
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("VoxPocket")
                    .font(.custom("Avenir Next", size: 20).weight(.semibold))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Circle()
                        .fill(isRecording ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(isRecording ? "Recording" : "Ready")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))
            TextField("Search history", text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

struct HistoryRowView: View {
    let session: Session
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.title.isEmpty ? "未命名会话" : session.title)
                .font(.custom("Avenir Next", size: 14).weight(.medium))
                .foregroundColor(.white)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(session.createdAt.formatted(date: .numeric, time: .shortened))
                Text("· \(session.state.rawValue)")
            }
            .font(.custom("Avenir Next", size: 11))
            .foregroundColor(.white.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
}

struct MeEntryRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [Color.orange, Color.pink], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("Me")
                    .font(.custom("Avenir Next", size: 16).weight(.semibold))
                    .foregroundColor(.white)
                Text("Profile & Settings")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

struct SidebarBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.12, blue: 0.2), Color(red: 0.12, green: 0.16, blue: 0.28)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    SidebarDrawerView(
        sessions: MockSessionListViewModel.sampleSessions,
        selectedSessionID: MockSessionListViewModel.sampleSessions.first?.id ?? UUID(),
        isRecording: true,
        searchText: .constant(""),
        onSelectSession: { _ in },
        onOpenMe: {}
    )
}
