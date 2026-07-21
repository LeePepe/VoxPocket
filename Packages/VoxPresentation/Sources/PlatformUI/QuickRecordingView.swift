#if os(macOS)
import SwiftUI
import UIShared

/// 快捷录音「灵动岛」。
///
/// 一个玻璃形状，随 `recorderStatus` 在收起（idle）↔ 展开（listening/…）之间弹簧形变，
/// 借鉴 Dynamic Island 的交互语法，但完全用 VoxPocket 既有的高级玻璃语言渲染
/// （`BackgroundAtmosphere` 近白玻璃 + 宝石柔调光团）。文字一律深墨色（`GlassInk`），
/// 修正过去白字压近白玻璃几乎不可见的问题。
public struct QuickRecordingView: View {
    @ObservedObject var viewModel: QuickRecordingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: QuickRecordingViewModel) {
        self.viewModel = viewModel
    }

    private var status: RecorderStatus { viewModel.recorderStatus }
    private var size: CGSize { QuickRecordingLayout.islandSize(for: status) }
    private var corner: CGFloat { QuickRecordingLayout.islandCorner(for: status) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }

    public var body: some View {
        // 岛在固定宿主内居中变形。
        ZStack {
            island
        }
        .frame(width: QuickRecordingLayout.panelWidth,
               height: QuickRecordingLayout.panelHeight,
               alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.quick.panel")
    }

    private var island: some View {
        ZStack {
            BackgroundAtmosphere(status: status, audioLevel: viewModel.normalizedAudioLevel)
            content
                .padding(.leading, QuickRecordingLayout.contentLeadingInset)
                .padding(.trailing, QuickRecordingLayout.contentTrailingInset)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(GlassInk.strokeSubtle, lineWidth: 1))
        .animation(morphAnimation, value: status)
        .padding(.top, 16)
    }

    private var morphAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)
    }

    // MARK: - 分状态内容

    @ViewBuilder
    private var content: some View {
        Group {
            switch status {
            case .idle:
                idleContent
            case .listening, .transcribing, .refining:
                expandedContent
            case .done:
                badgeContent(symbol: "checkmark", text: "已粘贴", tint: GlassInk.status(.done))
            case .error:
                errorContent
            }
        }
        .transition(contentTransition)
    }

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom))
    }

    /// 收起态：一个安静的圆点 + 应用名。
    private var idleContent: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(GlassInk.status(.idle))
                .frame(width: 6, height: 6)
            Text("VoxPocket")
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(GlassInk.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 展开态：波形簇 + 状态标签 + 实时文字。
    private var expandedContent: some View {
        HStack(spacing: QuickRecordingLayout.waveformTextGap) {
            VoxWaveform(mode: waveformMode, tint: GlassInk.status(status))
                .frame(width: QuickRecordingLayout.waveformWidth)

            VStack(alignment: .leading, spacing: 2) {
                statusLabel
                liveText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var waveformMode: VoxWaveform.Mode {
        switch status {
        case .listening: return .live(level: viewModel.normalizedAudioLevel ?? 0)
        case .transcribing, .refining: return .shimmer
        default: return .rest
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(GlassInk.status(status))
                .frame(width: 5, height: 5)
            Text(phaseTitle)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(GlassInk.textSecondary)
        }
    }

    private var phaseTitle: String {
        switch status {
        case .listening: return "正在聆听"
        case .transcribing: return "转写中"
        case .refining: return "润色中"
        default: return ""
        }
    }

    /// 实时文字：单行，头部截断，左缘渐出（延续旧遮罩手法）。
    private var liveText: some View {
        Text(displayText)
            .font(.system(.footnote, design: .rounded).weight(.medium))
            .foregroundStyle(GlassInk.textPrimary)
            .lineLimit(1)
            .truncationMode(.head)
            .allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .compositingGroup()
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                        .frame(width: QuickRecordingLayout.textLeftFadeWidth)
                    Rectangle().fill(.black)
                }
            }
            .accessibilityIdentifier("vox.quick.status")
    }

    private var displayText: String {
        if status == .refining, !viewModel.refinedText.isEmpty {
            return viewModel.refinedText
        }
        return viewModel.liveTranscription
    }

    /// 徽章态（done）：图标 + 短语。
    private func badgeContent(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(GlassInk.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 错误态：警示图标 + 两行错误信息。
    private var errorContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GlassInk.status(.error))
            Text(viewModel.errorMessage ?? "出错了")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(GlassInk.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
