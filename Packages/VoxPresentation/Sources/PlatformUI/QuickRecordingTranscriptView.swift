#if os(macOS)
import SwiftUI
import UIShared

@MainActor
struct QuickRecordingTranscriptView: View {
    let text: String
    @State private var followsLatest = true
    @State private var hasEarlierText = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                transcriptContent
            }
            .scrollIndicators(.visible)
            .onScrollGeometryChange(for: TranscriptScrollMetrics.self) { geometry in
                TranscriptScrollMetrics(offset: geometry.contentOffset.y,
                                        contentHeight: geometry.contentSize.height,
                                        viewportHeight: geometry.containerSize.height)
            } action: { old, new in
                hasEarlierText = new.offset > 8
                // 文本增高不是用户上滚；只在内容尺寸不变时更新阅读意图。
                if old.contentHeight == new.contentHeight && old.offset != new.offset {
                    followsLatest = new.isAtBottom
                }
            }
            .onAppear { proxy.scrollTo("transcript-end", anchor: .bottom) }
            .onChange(of: text) { _, _ in
                if followsLatest { proxy.scrollTo("transcript-end", anchor: .bottom) }
            }
            .overlay(alignment: .top) {
                if hasEarlierText {
                    LinearGradient(colors: [QuickRecordingColors.neutrals.card, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) { resumeButton(proxy) }
        }
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .foregroundStyle(QuickRecordingColors.neutrals.text1)
                .font(.system(size: 20, weight: .regular))
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("识别文字")
                .accessibilityValue(Text(text))
                .accessibilityIdentifier("vox.quick.transcript")
            Color.clear.frame(height: 1).id("transcript-end")
        }
    }

    @ViewBuilder private func resumeButton(_ proxy: ScrollViewProxy) -> some View {
        if !followsLatest {
            Button("回到最新 ↓") {
                followsLatest = true
                proxy.scrollTo("transcript-end", anchor: .bottom)
            }
            .font(.system(size: 12)).buttonStyle(.plain)
            .foregroundStyle(QuickRecordingColors.primary.primaryText)
            .padding(8)
            .background(QuickRecordingColors.primary.primarySubtle, in: Capsule())
            .accessibilityIdentifier("vox.quick.followLatest")
        }
    }

}

private struct TranscriptScrollMetrics: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    var isAtBottom: Bool { offset + viewportHeight >= contentHeight - 8 }
}
#endif
