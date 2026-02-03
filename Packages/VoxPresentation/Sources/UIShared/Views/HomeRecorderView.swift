import SwiftUI
import CoreModels

struct HomeRecorderView<VM: EditorViewState>: View {
    @ObservedObject var viewModel: VM
    let recorderStatus: RecorderStatus
    let onToggleSidebar: (() -> Void)?
    let onShowRawSheet: () -> Void

    @State private var reveal = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 上方面板（精炼文本）显示内容
    private var refinedPaneText: String {
        if viewModel.isRecording {
            return viewModel.liveTranscription.isEmpty
                ? "正在聆听..."
                : viewModel.liveTranscription
        } else if viewModel.isRefining {
            return viewModel.streamingRefinedText.isEmpty
                ? "正在优化..."
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
        // TODO: Verify iOS compact hides raw pane; regular width shows.
        let hasContent = !viewModel.rawTranscription.isEmpty || viewModel.isRecording
#if os(iOS)
        let isCompact = horizontalSizeClass == .compact
        return hasContent && !isCompact
#else
        return hasContent
#endif
    }

    var body: some View {
        VStack(spacing: 16) {
            TopBar(
                title: "VoxPocket",
                onToggleSidebar: onToggleSidebar,
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                onUndo: { viewModel.undo() },
                onRedo: { viewModel.redo() },
                onShowRaw: onShowRawSheet
            )

            VStack(spacing: 16) {
                RefinedTextPane(
                    text: refinedPaneText,
                    status: recorderStatus
                )

                if shouldShowRawPane {
                    RawInlinePane(
                        text: rawPaneText
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                onCopy: {},
                onNewSession: {}
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .opacity(reveal ? 1 : 0)
        .offset(y: reveal ? 0 : 12)
        .animation(.easeOut(duration: 0.4), value: reveal)
        .onAppear {
            reveal = true
        }
    }
}

// MARK: - Sub-components

struct TopBar: View {
    let title: String
    let onToggleSidebar: (() -> Void)?
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onShowRaw: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let onToggleSidebar {
                Button(action: onToggleSidebar) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.92))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(GlassIconButtonStyle())
            }

            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.95))

            Spacer()

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(GlassIconButtonStyle())
            .disabled(!canUndo)
            .opacity(canUndo ? 1 : 0.4)

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(GlassIconButtonStyle())
            .disabled(!canRedo)
            .opacity(canRedo ? 1 : 0.4)

            Button(action: onShowRaw) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Raw")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(GlassCapsuleStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GlassBarBackground())
    }
}

struct RefinedTextPane: View {
    let text: String
    let status: RecorderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.97))
                .lineSpacing(7)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(status.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.6))
        }
        .padding(22)
        .background(GlassCardBackground(cornerRadius: 26, strength: 0.22))
    }
}

struct RawInlinePane: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Raw Transcript")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.75))
                Spacer()
                Image(systemName: "doc.on.doc")
                    .foregroundColor(Color.white.opacity(0.45))
            }
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.white.opacity(0.75))
        }
        .padding(18)
        .background(GlassCardBackground(cornerRadius: 22, strength: 0.14))
    }
}

struct StatusBar: View {
    let status: RecorderStatus

    var body: some View {
        HStack(spacing: 12) {
            if status == .listening {
                Image(systemName: "mic.fill")
                    .foregroundColor(.white.opacity(0.85))
                Text("Listening")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("Mic Live")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                    )
            } else {
                Image(systemName: status == .error ? "exclamationmark.triangle" : "sparkles")
                    .foregroundColor(.white.opacity(0.8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(status == .error ? "Refine failed" : "Refine status")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(status == .error ? "Tap to retry" : "Ready for next segment")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
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

    private var primaryTitle: String {
        (status == .listening || status == .transcribing || status == .refining) ? "Stop" : "Restart"
    }

    private var primaryIcon: String {
        (status == .listening || status == .transcribing || status == .refining) ? "stop.fill" : "arrow.counterclockwise"
    }

    private var primaryColor: Color {
        switch status {
        case .listening, .transcribing:
            return Color(red: 0.42, green: 0.76, blue: 0.82)
        case .refining:
            return Color(red: 0.56, green: 0.54, blue: 0.88)
        case .done:
            return Color(red: 0.54, green: 0.8, blue: 0.62)
        case .error:
            return Color(red: 0.8, green: 0.4, blue: 0.42)
        case .idle:
            return Color(red: 0.5, green: 0.62, blue: 0.8)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStopOrRestart) {
                ControlButtonLabel(title: primaryTitle, systemImage: primaryIcon)
            }
            .buttonStyle(PrimaryControlStyle(color: primaryColor, emphasis: true))

            Button(action: onCopy) {
                ControlButtonLabel(title: "Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(PrimaryControlStyle(color: Color.white.opacity(0.18), emphasis: false))

            Button(action: onNewSession) {
                ControlButtonLabel(title: "New Session", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryControlStyle(color: Color.white.opacity(0.18), emphasis: false))
        }
    }
}

struct ControlButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(Color.white.opacity(0.95))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct PrimaryControlStyle: ButtonStyle {
    let color: Color
    let emphasis: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.6 : 0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(emphasis ? 0.22 : 0.12), lineWidth: 1)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(emphasis ? 0.08 : 0.04))
                            .blur(radius: 6)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 34, height: 34)
            .foregroundColor(Color.white.opacity(0.92))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct GlassCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GlassBarBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .blur(radius: 8)
            )
    }
}

struct GlassCardBackground: View {
    let cornerRadius: CGFloat
    let strength: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(strength))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .blur(radius: 10)
            )
    }
}

#Preview {
    @Previewable
    @StateObject var vm = MockEditorViewModel()

    ZStack {
        BackgroundAtmosphere(status: .idle)
        HomeRecorderView(
            viewModel: vm,
            recorderStatus: .idle,
            onToggleSidebar: {},
            onShowRawSheet: {}
        )
    }
    .frame(height: 600)
}
