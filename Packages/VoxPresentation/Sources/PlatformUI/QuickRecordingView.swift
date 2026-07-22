#if os(macOS)
import SwiftUI
import UIShared

/// 快捷录音「灵动岛」。
///
/// 一个玻璃形状，随 `recorderStatus` 在收起（idle）↔ 展开（listening/…）之间弹簧形变，
/// 借鉴 Dynamic Island 的交互语法。**纯视觉状态语言**：不显示任何词句/状态标签/实时
/// 转写/错误文本。各阶段仅靠波形模式、语义色、形状包络与终态图标传达当前处于哪一态；
/// VoiceOver 通过 `.accessibilityLabel` / `.accessibilityValue` 感知状态，保证不因去掉
/// 可见文字而对辅助技术不可用（宪法 IV：转写/精炼文本不落 UI 也不入日志）。
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
                iconContent(symbol: "checkmark", tint: GlassInk.status(.done))
            case .error:
                iconContent(symbol: "exclamationmark.triangle.fill", tint: GlassInk.status(.error))
            }
        }
        .transition(contentTransition)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("vox.quick.status")
        .accessibilityLabel(Text(accessibilityStatusLabel))
        .accessibilityValue(Text(accessibilityStatusValue))
    }

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom))
    }

    /// 收起态：一个安静的中性色圆点。无字标。
    private var idleContent: some View {
        Circle()
            .fill(GlassInk.status(.idle))
            .frame(width: 6, height: 6)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 展开态：波形（音频/流光/静止）居中，无状态标签、无实时转写文本。
    private var expandedContent: some View {
        VoxWaveform(mode: waveformMode, tint: GlassInk.status(status))
            .frame(width: QuickRecordingLayout.waveformWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var waveformMode: VoxWaveform.Mode {
        switch status {
        case .listening: return .live(level: viewModel.normalizedAudioLevel ?? 0)
        case .transcribing, .refining: return .shimmer
        default: return .rest
        }
    }

    /// 终态：仅图标 + 语义色，不带任何词句。
    private func iconContent(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Accessibility（VoiceOver 感知，屏幕上不可见）

    private var accessibilityStatusLabel: String {
        switch status {
        case .idle: return "快捷录音待命"
        case .listening: return "正在录音"
        case .transcribing: return "正在转写"
        case .refining: return "正在润色"
        case .done: return "已完成并粘贴"
        case .error: return "录音出错"
        }
    }

    private var accessibilityStatusValue: String {
        switch status {
        case .idle: return "空闲"
        case .listening: return "聆听中"
        case .transcribing: return "转写中"
        case .refining: return "润色中"
        case .done: return "已粘贴"
        case .error: return "出错"
        }
    }
}
#endif
