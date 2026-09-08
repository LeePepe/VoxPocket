#if os(macOS)
import SwiftUI
import UIShared

@MainActor
public struct QuickRecordingView: View {
    @ObservedObject private var viewModel: QuickRecordingViewModel
    private let placement: QuickRecordingPlacement

    public init(viewModel: QuickRecordingViewModel, placement: QuickRecordingPlacement = .floating) {
        self.viewModel = viewModel
        self.placement = placement
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            QuickRecordingIslandView(
                status: viewModel.recorderStatus,
                transcript: viewModel.displayedTranscription,
                audioLevel: viewModel.normalizedAudioLevel,
                elapsed: viewModel.elapsedRecordingTime(at: context.date),
                placement: placement,
                onStop: { Task { await viewModel.stopRecording() } },
                onCancel: { Task { await viewModel.cancelFromPanel() } },
                onCopy: { viewModel.copyRecognizedText() }
            )
        }
    }
}

/// 「声音落岛」值驱动视图；真实录音、离屏渲染和预览共用同一套布局。
@MainActor
struct QuickRecordingIslandView: View {
    let status: RecorderStatus
    let transcript: String
    var audioLevel: Double?
    var elapsed: TimeInterval = 0
    var placement: QuickRecordingPlacement = .floating
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}
    var onCopy: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var textHeight: CGFloat = 84

    private var showsTranscript: Bool {
        status != .idle && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var size: CGSize {
        QuickRecordingLayout.size(for: status, showsTranscript: showsTranscript, placement: placement, textHeight: textHeight)
    }
    private var outline: QuickRecordingIslandOutline {
        QuickRecordingIslandOutline(cameraSize: placement.cameraSize)
    }
    private var tint: Color {
        switch status {
        case .done: QuickRecordingColors.success
        case .error: QuickRecordingColors.danger
        default: QuickRecordingColors.primary.primaryText
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if status != .idle && status != .done { footer }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(QuickRecordingColors.neutrals.card)
        .clipShape(outline, style: FillStyle(eoFill: true))
        .overlay(outline.stroke(contrast == .increased ? QuickRecordingColors.neutrals.text2 : QuickRecordingColors.neutrals.border,
                                lineWidth: contrast == .increased ? 1.5 : 1))
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9), value: size)
        .frame(width: placement.panelFrame.width, height: placement.panelFrame.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.quick.panel")
    }

    private var header: some View {
        HStack(spacing: 0) {
            Label(statusLabel, systemImage: statusSymbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(status == .error ? QuickRecordingColors.neutrals.text1 : tint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(tint.opacity(0.13), in: Capsule())
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("vox.quick.status")
            Color.clear.frame(width: placement.cameraSize.width).accessibilityHidden(true)
            HStack(spacing: 12) {
                Text(Self.elapsedLabel(elapsed))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(QuickRecordingColors.neutrals.text2)
                if status == .listening || status == .transcribing || status == .refining {
                    VoxWaveform(mode: waveformMode, tint: tint)
                        .frame(width: QuickRecordingLayout.waveformWidth, height: 22)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: max(QuickRecordingLayout.headerHeight, placement.cameraSize.height + 16))
    }

    @ViewBuilder private var content: some View {
        if showsTranscript {
            VStack(alignment: .leading, spacing: 12) {
                Text(status == .error ? "已保留的文字" : status == .done ? "最终文字" : "实时转写")
                    .font(.system(size: 12))
                    .foregroundStyle(QuickRecordingColors.neutrals.text2)
                QuickRecordingTranscriptView(text: transcript, highlightsLatest: status == .listening) { textHeight = $0 }
                    .frame(height: min(textHeight, QuickRecordingLayout.readingHeight))
                if status == .error {
                    Text("本次处理未完成，识别文字仍保留在这里。")
                        .font(.system(size: 12))
                        .foregroundStyle(QuickRecordingColors.neutrals.text2)
                }
            }
            .padding(.horizontal, QuickRecordingLayout.contentInset)
            .padding(.top, 12).padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            Text(emptyMessage)
                .font(.system(size: 18))
                .foregroundStyle(QuickRecordingColors.neutrals.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, QuickRecordingLayout.contentInset)
                .padding(.bottom, 16)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(QuickRecordingColors.neutrals.border).frame(height: 1)
            HStack {
                if status == .listening {
                    Button("取消", action: onCancel).buttonStyle(.plain)
                        .accessibilityIdentifier("vox.quick.cancel")
                } else {
                    Text(status == .error ? "请重新按住 Fn 重试" : "正在处理，请稍候")
                }
                Spacer()
                if status == .listening {
                    Button(action: onStop) {
                        HStack(spacing: 8) {
                            Text("fn").font(.system(size: 11)).padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(QuickRecordingColors.neutrals.border))
                            Text("松开结束")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(QuickRecordingColors.neutrals.inner, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("结束转写，也可松开 Fn")
                    .accessibilityIdentifier("vox.quick.stop")
                } else if status == .error && showsTranscript {
                    Button("复制原文", action: onCopy).buttonStyle(.plain)
                        .foregroundStyle(QuickRecordingColors.primary.primaryText)
                        .accessibilityIdentifier("vox.quick.copy")
                }
                if status == .error {
                    Button("关闭", action: onCancel).buttonStyle(.plain)
                        .accessibilityIdentifier("vox.quick.dismiss")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(QuickRecordingColors.neutrals.text2)
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private var emptyMessage: String {
        switch status {
        case .idle, .listening: "说点什么，让想法留下来。"
        case .transcribing, .refining: "正在整理刚才的语音…"
        case .done: "文字已处理完成。"
        case .error: "暂时无法完成录音，请重试。"
        }
    }

    private var statusLabel: String {
        switch status {
        case .idle: "准备聆听"
        case .listening: "正在聆听"
        case .transcribing: "正在转写"
        case .refining: "正在润色"
        case .done: "处理完成"
        case .error: "录音出错"
        }
    }

    private var statusSymbol: String {
        switch status {
        case .idle, .listening: "mic.fill"
        case .transcribing: "text.alignleft"
        case .refining: "sparkles"
        case .done: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var waveformMode: VoxWaveform.Mode {
        switch status {
        case .listening: .live(level: audioLevel ?? 0)
        case .transcribing, .refining: .shimmer
        default: .rest
        }
    }

    static func elapsedLabel(_ elapsed: TimeInterval) -> String {
        let seconds = elapsed.isFinite ? Int(max(0, min(elapsed, 359999))) : 0
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// 刘海区透明挖空；无刘海时完全不绘制摄像头占位。
struct QuickRecordingIslandOutline: Shape {
    var cameraSize: CGSize

    func path(in rect: CGRect) -> Path {
        let attached = cameraSize.height > 0
        var path = UnevenRoundedRectangle(topLeadingRadius: attached ? 0 : 32,
                                         bottomLeadingRadius: 32, bottomTrailingRadius: 32,
                                         topTrailingRadius: attached ? 0 : 32).path(in: rect)
        if attached {
            let camera = CGRect(x: rect.midX - cameraSize.width / 2, y: rect.minY,
                                width: cameraSize.width, height: cameraSize.height)
            path.addPath(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).path(in: camera))
        }
        return path
    }
}

#Preview("声音落岛") {
    QuickRecordingIslandView(status: .listening, transcript: "我想做一个更安静的语音工具，\n按下 Fn，就能把想法留下来。", audioLevel: 0.6, elapsed: 8)
}
#endif
