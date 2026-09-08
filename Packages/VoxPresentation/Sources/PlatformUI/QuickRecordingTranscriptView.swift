#if os(macOS)
import SwiftUI
import UIShared

@MainActor
struct QuickRecordingTranscriptView: View {
    let text: String
    let highlightsLatest: Bool
    var onTextHeightChange: (CGFloat) -> Void = { _ in }
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
            styledText
                .font(.system(size: 22, weight: .regular))
                .lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onTextHeightChange($0) }
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

    private var styledText: Text {
        var result = AttributedString(text)
        result.foregroundColor = QuickRecordingColors.neutrals.text1
        if highlightsLatest {
            let count = Self.latestSegment(in: text).count
            let start = result.characters.index(result.endIndex, offsetBy: -count)
            result[start..<result.endIndex].foregroundColor = QuickRecordingColors.primary.primaryText
        }
        return Text(result)
    }

    /// 用最近短句边界强调识别末尾，不在中文词语或 emoji 中间切色。
    static func latestSegment(in text: String) -> String {
        let separators: Set<Character> = ["，", ",", "。", ".", "！", "!", "？", "?", ";", "；", "\n"]
        guard let lastContent = text.lastIndex(where: { !separators.contains($0) }) else { return "" }
        let boundary = text[..<lastContent].lastIndex(where: { separators.contains($0) })
        let start = boundary.map { text.index(after: $0) } ?? text.startIndex
        let segment = text[start...]
        return segment.count <= 80 ? String(segment) : ""
    }
}

private struct TranscriptScrollMetrics: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    var isAtBottom: Bool { offset + viewportHeight >= contentHeight - 8 }
}
#endif
