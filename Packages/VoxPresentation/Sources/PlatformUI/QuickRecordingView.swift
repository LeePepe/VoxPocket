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
        QuickRecordingIslandView(
            status: viewModel.recorderStatus,
            transcript: viewModel.displayedTranscription,
            audioLevel: viewModel.normalizedAudioLevel,
            placement: placement,
            onStop: { Task { await viewModel.stopRecording() } },
            onCancel: { Task { await viewModel.cancelFromPanel() } },
            onCopy: { viewModel.copyRecognizedText() }
        )
    }
}

/// 常态只呈现文字与状态色；操作在悬停、右键菜单和辅助功能中提供。
@MainActor
struct QuickRecordingIslandView: View {
    let status: RecorderStatus
    let transcript: String
    var audioLevel: Double?
    var placement: QuickRecordingPlacement = .floating
    /// 原生预览可主动减少动画；不能覆盖系统的减少动态效果设置。
    var forceReducedMotion = false
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}
    var onCopy: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var revealsTranscript = false
    @State private var entranceProgress: CGFloat = 0
    @State private var hasEntered = false

    private var reduceMotion: Bool { systemReduceMotion || forceReducedMotion }

    private var showsTranscript: Bool {
        status != .idle && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var size: CGSize {
        QuickRecordingLayout.size(for: status, showsTranscript: showsTranscript, placement: placement)
    }
    private var tint: Color { QuickRecordingColors.status(status, colorScheme: colorScheme) }
    private var outline: QuickRecordingIslandOutline { QuickRecordingIslandOutline(cameraSize: placement.cameraSize) }
    private var canDismiss: Bool { status == .listening || status == .error }
    private var wingWidth: CGFloat { max(0, (size.width - placement.cameraSize.width - 48) / 2) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsTranscript {
                QuickRecordingTranscriptView(text: transcript)
                    .frame(width: size.width - 2 * QuickRecordingLayout.contentInset,
                           height: min(QuickRecordingLayout.readingHeight, max(0, size.height - QuickRecordingLayout.headerHeight - 16)))
                    .padding(.bottom, 16)
                    // 岛体揭开文字；文字不继承外轮廓的缩放、位移或弹簧动画。
                    .transaction { $0.animation = nil }
                    .opacity(revealsTranscript ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(QuickRecordingPhaseSurface(status: status, audioLevel: audioLevel))
        .clipShape(outline, style: FillStyle(eoFill: true))
        .overlay(phaseRim)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: showsTranscript)
        .clipShape(QuickRecordingEntranceMask(progress: reduceMotion ? 1 : entranceProgress,
                                              cameraSize: placement.cameraSize))
        .frame(width: placement.panelFrame.width, height: placement.panelFrame.height, alignment: .top)
        .onHover { isHovering = $0 }
        .task(id: reduceMotion) { await revealIsland() }
        .task(id: [showsTranscript, hasEntered, reduceMotion]) { await revealTranscript() }
        .onDisappear {
            entranceProgress = 0
            hasEntered = false
            revealsTranscript = false
        }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityActions { actions }
        .accessibilityIdentifier("vox.quick.panel")
    }

    private var header: some View {
        HStack(spacing: 0) {
            // 某些 SF Symbols 自带颜色层；用 alpha 遮罩保证图标与波形状态色一致。
            tint
                .frame(width: 24, height: 28)
                .mask {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.identity)
                        .transaction { $0.animation = nil }
                }
                .frame(width: wingWidth, alignment: .leading)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(Text(statusLabel))
                .accessibilityIdentifier("vox.quick.status")
            Color.clear.frame(width: placement.cameraSize.width).accessibilityHidden(true)
            ZStack {
                if status == .listening || status == .transcribing || status == .refining {
                    VoxWaveform(mode: waveformMode, tint: tint)
                        .frame(width: QuickRecordingLayout.waveformWidth, height: 20)
                        .opacity(isHovering && canDismiss ? 0 : 1)
                        .accessibilityHidden(true)
                }
                if canDismiss {
                    Button(action: onCancel) { Image(systemName: "xmark").frame(width: 32, height: 28) }
                        .buttonStyle(.plain).foregroundStyle(QuickRecordingColors.neutrals(for: colorScheme).text1)
                        .opacity(isHovering ? 1 : 0)
                        .allowsHitTesting(isHovering)
                        .accessibilityLabel(status == .error ? "关闭" : "取消录音")
                        .accessibilityIdentifier("vox.quick.cancel")
                }
            }
            .frame(width: QuickRecordingLayout.waveformWidth, height: 28)
            .frame(width: wingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: QuickRecordingLayout.headerHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: QuickRecordingColors.transitionDuration), value: status)
    }

    @ViewBuilder private var phaseRim: some View {
        if contrast == .increased {
            outline.stroke(tint, lineWidth: 1.5)
        } else {
            ZStack {
                outline.stroke(LinearGradient(colors: QuickRecordingColors.rim(status, colorScheme: colorScheme),
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
                    .id(status)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: QuickRecordingColors.transitionDuration), value: status)
        }
    }

    private func revealIsland() async {
        guard !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                entranceProgress = 1
                hasEntered = true
            }
            return
        }
        guard !hasEntered else { return }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: QuickRecordingLayout.entranceDuration)) {
            entranceProgress = 1
        }
        do { try await Task.sleep(for: .seconds(QuickRecordingLayout.entranceDuration)) } catch { return }
        hasEntered = true
    }

    private func revealTranscript() async {
        revealsTranscript = false
        guard showsTranscript && hasEntered else { return }
        guard !reduceMotion else { revealsTranscript = true; return }
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        // 等轮廓基本展开后再淡入，避免文字首字在中途被缩窄的边界切掉。
        withAnimation(.easeOut(duration: 0.12)) { revealsTranscript = true }
    }

    @ViewBuilder private var actions: some View {
        if status == .listening {
            Button("结束录音", action: onStop)
            Button("取消录音", action: onCancel)
        }
        if status == .error {
            if showsTranscript { Button("复制原文", action: onCopy) }
            Button("关闭", action: onCancel)
        }
    }

    private var statusLabel: String {
        switch status {
        case .idle: "准备聆听"
        case .listening: "正在录音"
        case .transcribing: "正在转写"
        case .refining: "正在润色"
        case .done: "处理完成"
        case .error: "处理失败，可右键复制原文或关闭后重试"
        }
    }

    private var statusSymbol: String {
        switch status {
        case .idle, .listening: "circle.fill"
        case .transcribing: "ellipsis"
        case .refining: "sparkles"
        case .done: "checkmark"
        case .error: "exclamationmark"
        }
    }

    private var waveformMode: VoxWaveform.Mode {
        switch status {
        case .listening: .live(level: audioLevel ?? 0)
        case .transcribing, .refining: .shimmer
        default: .rest
        }
    }
}

/// 只揭开岛体，不改变文字、波形或图标的尺寸；真实摄像头挖空仍由外轮廓负责。
@MainActor
struct QuickRecordingEntranceMask: Shape {
    var progress: CGFloat
    var cameraSize: CGSize

    // SwiftUI 在非隔离上下文插值 Shape 值副本；这里只修改副本中的标量，不访问 UI 状态。
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    // Shape.path 的协议契约为非隔离；计算只依赖 Sendable 值字段，不读取界面或主 actor 状态。
    nonisolated func path(in rect: CGRect) -> Path {
        let reveal = QuickRecordingLayout.entranceRect(in: rect, cameraSize: cameraSize, progress: progress)
        // 中途也保持柔和圆角；完全展开时与原轮廓重合，刘海两翼恢复平直上沿。
        let radius = min(24, min(reveal.width, reveal.height) / 2)
        let topRadius = cameraSize.height > 0 ? radius * (1 - min(1, max(0, progress))) : radius
        return UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: radius,
                                      bottomTrailingRadius: radius, topTrailingRadius: topRadius).path(in: reveal)
    }
}

/// 真实刘海区透明挖空，不绘制硬件占位。
struct QuickRecordingIslandOutline: Shape {
    var cameraSize: CGSize

    func path(in rect: CGRect) -> Path {
        let attached = cameraSize.height > 0
        var path = UnevenRoundedRectangle(topLeadingRadius: attached ? 0 : 24,
                                         bottomLeadingRadius: 24, bottomTrailingRadius: 24,
                                         topTrailingRadius: attached ? 0 : 24).path(in: rect)
        if attached {
            let camera = CGRect(x: rect.midX - cameraSize.width / 2, y: rect.minY,
                                width: cameraSize.width, height: cameraSize.height)
            path.addPath(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).path(in: camera))
        }
        return path
    }
}

#Preview("精简语音岛") {
    QuickRecordingIslandView(status: .refining, transcript: "明天开会讨论计划。")
}
#endif
