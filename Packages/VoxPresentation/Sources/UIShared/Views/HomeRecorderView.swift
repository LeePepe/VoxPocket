import SwiftUI
import CoreModels

public struct HomeRecorderView<VM: EditorViewState>: View {
    @ObservedObject var viewModel: VM
    let recorderStatus: RecorderStatus
    let onCopyRefined: (String) -> Void
    let onCopyRaw: (String) -> Void

    public init(
        viewModel: VM,
        recorderStatus: RecorderStatus,
        onCopyRefined: @escaping (String) -> Void,
        onCopyRaw: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.recorderStatus = recorderStatus
        self.onCopyRefined = onCopyRefined
        self.onCopyRaw = onCopyRaw
    }

    @State private var reveal = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 上方面板（精炼文本）显示内容
    private var refinedPaneText: String {
        if viewModel.isRecording {
            return viewModel.liveTranscription.isEmpty
                ? "正在聆听…"
                : viewModel.liveTranscription
        } else if viewModel.isRefining {
            return viewModel.streamingRefinedText.isEmpty
                ? "正在优化…"
                : viewModel.streamingRefinedText
        } else {
            return viewModel.text.isEmpty
                ? "开始说话，自动生成高质量文本。"
                : viewModel.text
        }
    }

    /// 下方面板（原始转录）显示内容
    private var rawPaneText: String {
        if viewModel.isRecording {
            return viewModel.liveTranscription.isEmpty
                ? "原始转写会显示在这里。"
                : viewModel.liveTranscription
        } else {
            return viewModel.rawTranscription.isEmpty
                ? "原始转写会显示在这里。"
                : viewModel.rawTranscription
        }
    }

    /// 是否显示下方原始转录面板
    private var shouldShowRawPane: Bool {
        // iPhone 竖屏(compact)隐藏原始面板以省空间；iPad/横屏/macOS(regular)显示
        let hasContent = !viewModel.rawTranscription.isEmpty || viewModel.isRecording
#if os(iOS)
        let isCompact = horizontalSizeClass == .compact
        return hasContent && !isCompact
#else
        return hasContent
#endif
    }

    /// 原始面板入场/退场过渡：开启「减弱动态效果」时使用纯淡入，避免位移
    private var rawPaneTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    public var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                RefinedTextPane(
                    text: refinedPaneText
                )
                .frame(maxHeight: .infinity, alignment: .top)

                Spacer(minLength: 0)

                Group {
                    if shouldShowRawPane {
                        RawInlinePane(
                            text: rawPaneText,
                            onCopy: { onCopyRaw(rawPaneText) }
                        )
                        .transition(rawPaneTransition)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.3), value: shouldShowRawPane)

            BottomControls(
                status: recorderStatus,
                onStopOrRestart: {
                    Task {
                        await viewModel.toggleRecording()
                    }
                },
                onCopy: {
                    onCopyRefined(viewModel.text)
                },
                onNewSession: {
                    Task { await viewModel.startNewSession() }
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .voxTheme()
        .background(
            BackgroundAtmosphere(
                status: recorderStatus,
                audioLevel: Double(viewModel.audioLevel)
            )
        )
        .opacity(reveal ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (reveal ? 0 : 12))
        .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.4), value: reveal)
        .onAppear {
            reveal = true
        }
        .onChange(of: viewModel.autoCopiedText) { _, newValue in
            if let text = newValue, !text.isEmpty {
                onCopyRefined(text)
                viewModel.autoCopiedText = nil
            }
        }
    }
}

// MARK: - Sub-components

struct RefinedTextPane: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text)
                .font(FontToken.title)
                .foregroundColor(.textPrimary)
                .lineSpacing(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("vox.transcript.final")
        }
        .padding(22)
    }
}

struct RawInlinePane: View {
    let text: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("原始转写")
                    .font(FontToken.callout)
                    .foregroundColor(.textSecondary)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(GlassIconButtonStyle())
                .accessibilityLabel("复制原始转写")
            }
            Text(text)
                .font(FontToken.body)
                .foregroundColor(.textSecondary)
                .accessibilityIdentifier("vox.transcript.live")
        }
        .padding(18)
    }
}

struct StatusBar: View {
    let status: RecorderStatus

    var body: some View {
        HStack(spacing: 12) {
            if status == .listening {
                Image(systemName: "mic.fill")
                    .foregroundColor(.statusListening)
                Text("聆听中")
                    .font(FontToken.callout)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("麦克风已开")
                    .font(FontToken.callout)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(GlassCapsuleBackground())
            } else {
                Image(systemName: status == .error ? "exclamationmark.triangle" : "sparkles")
                    .foregroundColor(status == .error ? .statusError : .accentPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status == .error ? "精炼失败" : "精炼状态")
                        .font(FontToken.callout)
                        .foregroundColor(.textPrimary)
                    Text(status == .error ? "点按重试" : "准备就绪")
                        .font(FontToken.caption)
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(GlassCardBackground(cornerRadius: 20, strength: 0.12))
    }
}

struct BottomControls: View {
    let status: RecorderStatus
    let onStopOrRestart: () -> Void
    let onCopy: () -> Void
    let onNewSession: () -> Void
    @Environment(\.theme) private var theme

    private var primaryTitle: String {
        (status == .listening || status == .transcribing || status == .refining) ? "停止" : "继续"
    }

    private var primaryIcon: String {
        (status == .listening || status == .transcribing || status == .refining) ? "stop.fill" : "mic.fill"
    }

    private func primaryColor(for theme: Theme) -> Color {
        switch status {
        case .listening, .transcribing:
            return theme.palette.statusListening
        case .refining:
            return theme.palette.statusRefining
        case .done:
            return theme.palette.statusDone
        case .error:
            return theme.palette.statusError
        case .idle:
            return theme.palette.accentPrimary
        }
    }

    var body: some View {
        let primaryColor = primaryColor(for: theme)
        HStack(spacing: 10) {
            ControlButton("新建", systemImage: "plus", color: theme.palette.surfaceElevated, action: onNewSession)

            Spacer()

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
            }
            .buttonStyle(GlassIconButtonStyle())
            .accessibilityLabel("复制精炼文本")

            ControlButton(primaryTitle, systemImage: primaryIcon, color: primaryColor, emphasis: true, action: onStopOrRestart)
                .accessibilityIdentifier(
                    (status == .listening || status == .transcribing || status == .refining)
                        ? "vox.stop.button"
                        : "vox.record.button"
                )
        }
    }
}

/// 统一尺寸的控制按钮组件
struct ControlButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let emphasis: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    init(
        _ title: String,
        systemImage: String,
        color: Color,
        emphasis: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.emphasis = emphasis
        self.action = action
    }

    var body: some View {
        let iconColor = emphasis ? theme.palette.textPrimary : theme.palette.accentPrimary
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(FontToken.caption)
            }
            .foregroundColor(.textPrimary)
            .frame(minWidth: 56)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(PrimaryControlStyle(color: color, emphasis: emphasis))
    }
}

struct PrimaryControlStyle: ButtonStyle {
    let color: Color
    let emphasis: Bool
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if emphasis {
                configuration.label
                    .glassEffect(.regular.interactive().tint(color), in: RoundedRectangle(cornerRadius: 16))
                    .scaleEffect(configuration.isPressed ? 0.98 : 1)
                    .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            } else {
                configuration.label
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                    .scaleEffect(configuration.isPressed ? 0.98 : 1)
                    .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            }
        } else {
            let strokeColor = emphasis ? theme.palette.strokeStrong : theme.palette.strokeSubtle
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color.opacity(configuration.isPressed ? 0.6 : 0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(strokeColor, lineWidth: 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(theme.palette.surfaceGlassStrong.opacity(emphasis ? 0.5 : 0.3))
                                .blur(radius: 6)
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
        }
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            configuration.label
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                // 视觉保持 34pt，命中区扩到 HIG 最小 44pt
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        } else {
            configuration.label
                .frame(width: 34, height: 34)
                .foregroundColor(theme.palette.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.palette.surfaceElevated.opacity(configuration.isPressed ? 0.7 : 1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(theme.palette.strokeSubtle, lineWidth: 1)
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                // 视觉保持 34pt，命中区扩到 HIG 最小 44pt
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}

struct GlassCapsuleStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            configuration.label
                .glassEffect(.regular.interactive(), in: .capsule)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        } else {
            configuration.label
                .background(
                    Capsule()
                        .fill(theme.palette.surfaceElevated.opacity(configuration.isPressed ? 0.8 : 1))
                        .overlay(
                            Capsule()
                                .stroke(theme.palette.strokeSubtle, lineWidth: 1)
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

struct GlassCapsuleBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(theme.palette.surfaceGlass)
                .overlay(
                    Capsule()
                        .stroke(theme.palette.strokeSubtle, lineWidth: 1)
                )
        }
    }
}

struct GlassBarBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.palette.surfaceGlass)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.palette.strokeSubtle, lineWidth: 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.palette.surfaceGlassStrong.opacity(0.6))
                        .blur(radius: 8)
                )
        }
    }
}

struct GlassCardBackground: View {
    let cornerRadius: CGFloat
    let strength: Double
    @Environment(\.theme) private var theme

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            let fillColor = strength >= 0.2 ? theme.palette.surfaceGlassStrong : theme.palette.surfaceGlass
            let strokeColor = strength >= 0.2 ? theme.palette.strokeStrong : theme.palette.strokeSubtle
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(theme.palette.surfaceGlassStrong.opacity(0.5))
                        .blur(radius: 10)
                )
        }
    }
}

#Preview {
    @Previewable
    @StateObject var vm = MockEditorViewModel()

    HomeRecorderView(
        viewModel: vm,
        recorderStatus: .idle,
        onCopyRefined: { _ in },
        onCopyRaw: { _ in }
    )
    .frame(height: 600)
}
