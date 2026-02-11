import SwiftUI
import CoreModels

struct SidebarDrawerView: View {
    @Environment(\.colorScheme) private var colorScheme
    let sessions: [Session]
    let selectedSessionID: UUID
    let isRecording: Bool
    @Binding var searchText: String
    let onSelectSession: (Session) -> Void
    let onNewSession: () -> Void
    let onOpenMe: () -> Void

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            // 中间区域：header 悬浮 + 列表滚动
            ZStack(alignment: .top) {
                // 会话列表（底层，内容可滚动到 header 下方透出模糊）
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sessions) { session in
                            Button {
                                onSelectSession(session)
                            } label: {
                                HistoryRowView(session: session, isSelected: session.id == selectedSessionID)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    // 顶部留出 header 高度的空间
                    .padding(.top, 110)
                }

                // 固定头部 + 搜索栏（悬浮，模糊背景 + 渐变淡出边界）
                VStack(spacing: 0) {
                    HStack {
                        SidebarHeaderView(isRecording: isRecording)
                        Button(action: onNewSession) {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                                .foregroundColor(.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 18)
                    }

                    SearchField(text: $searchText)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                }
                .background(.ultraThinMaterial)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 16)
                    }
                )
            }

            // 底部 Me 入口
            Button(action: onOpenMe) {
                MeEntryRow()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.backgroundBase)
    }
}

struct SidebarHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    let isRecording: Bool

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("VoxPocket")
                    .font(.title)
                    .foregroundColor(.textPrimary)
                HStack(spacing: 8) {
                    Circle()
                        .fill(isRecording ? theme.palette.statusListening : theme.palette.statusDone)
                        .frame(width: 8, height: 8)
                    Text(isRecording ? "Recording" : "Ready")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textTertiary)
            TextField("Search history", text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.palette.surfaceGlass)
        )
    }
}

struct HistoryRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let session: Session
    var isSelected: Bool = false

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title.isEmpty ? "未命名会话" : session.title)
                .font(.callout)
                .foregroundColor(.textPrimary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(session.createdAt.formatted(date: .numeric, time: .shortened))
                Text("· \(session.state.rawValue)")
            }
            .font(.caption)
            .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? theme.palette.surfaceGlassStrong : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("Profile & Settings")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.textTertiary)
        }
    }
}

#Preview {
    SidebarDrawerView(
        sessions: MockSessionListViewModel.sampleSessions,
        selectedSessionID: MockSessionListViewModel.sampleSessions.first?.id ?? UUID(),
        isRecording: true,
        searchText: .constant(""),
        onSelectSession: { _ in },
        onNewSession: {},
        onOpenMe: {}
    )
}
