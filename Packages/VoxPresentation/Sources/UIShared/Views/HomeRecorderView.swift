import SwiftUI
import CoreModels

public struct HomeRecorderView<VM: EditorViewState>: View {
    @ObservedObject var viewModel: VM
    let recorderStatus: RecorderStatus
    let onCopyRefined: (String) -> Void
    let onCopyRaw: (String) -> Void
    let onOpenTodoList: () -> Void
    let onOpenSettings: () -> Void
    @State private var copied = false

    public init(viewModel: VM, recorderStatus: RecorderStatus, onCopyRefined: @escaping (String) -> Void,
                onCopyRaw: @escaping (String) -> Void, onOpenTodoList: @escaping () -> Void = {},
                onOpenSettings: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.recorderStatus = recorderStatus
        self.onCopyRefined = onCopyRefined
        self.onCopyRaw = onCopyRaw
        self.onOpenTodoList = onOpenTodoList
        self.onOpenSettings = onOpenSettings
    }

    private var sentence: String {
        if viewModel.isRecording { return viewModel.liveTranscription.isEmpty ? "正在聆听你的灵感，松手立即润色…" : viewModel.liveTranscription }
        if viewModel.isRefining { return viewModel.streamingRefinedText.isEmpty ? "正在提炼语句结构与核心要点…" : viewModel.streamingRefinedText }
        return viewModel.text.isEmpty ? "按住底部玻璃说话，松手即刻生成润色笔记。" : viewModel.text
    }

    public var body: some View {
        RecorderSentenceStage(sentence: sentence) {
            guard !viewModel.isRecording, !viewModel.isRefining, !viewModel.text.isEmpty else { return }
            onCopyRefined(viewModel.text)
            copied = true
        }
        .background { RecorderBackdrop(status: recorderStatus, audioLevel: viewModel.audioLevel) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RecorderDock(isRecording: viewModel.isRecording, isProcessing: viewModel.isRefining || recorderStatus == .transcribing,
                         audioLevel: viewModel.audioLevel, feedback: feedback, error: viewModel.errorMessage,
                         start: { copied = false; await viewModel.startRecording() },
                         stop: { await viewModel.stopRecording() },
                         cancel: { await viewModel.stopRecording() }, retry: retry,
                         openTodos: onOpenTodoList, openSettings: onOpenSettings)
        }
        .voxTheme()
        .onChange(of: viewModel.autoCopiedText) { _, value in
            if let value, !value.isEmpty {
                onCopyRefined(value)
                copied = true
                viewModel.autoCopiedText = nil
            }
        }
    }

    private var feedback: String {
        if viewModel.isRecording { return "正在聆听 · 松手立即润色" }
        if viewModel.isRefining || recorderStatus == .transcribing { return "正在提炼语句结构与核心要点…" }
        return copied ? "已复制到剪贴板 · 可直接粘贴" : "按住说话 · 点按也可启停"
    }

    private func retry() {
        viewModel.clearError()
        Task {
            if viewModel.rawTranscription.isEmpty { await viewModel.startRecording() }
            else { await viewModel.refine() }
        }
    }
}

struct RefinedTextPane: View { let text: String; var body: some View { Text(text).font(.system(size: 25, weight: .semibold, design: .rounded)).lineSpacing(7).tracking(-0.4).accessibilityIdentifier("vox.transcript.final") } }
struct RawInlinePane: View { let text: String; let onCopy: () -> Void; var body: some View { VStack { HStack { Text("原始转写"); Spacer(); Button(action: onCopy) { Image(systemName: "doc.on.doc") } }; Text(text) } } }

struct BottomControls: View {
    let status: RecorderStatus; let onStopOrRestart: () -> Void; let onCopy: () -> Void; let onNewSession: () -> Void
    var body: some View { HStack { Button("新建", action: onNewSession); Spacer(); Button(action: onCopy) { Image(systemName: "doc.on.doc") }; Button(status == .listening ? "停止" : "继续", action: onStopOrRestart).accessibilityIdentifier(status == .listening ? "vox.stop.button" : "vox.record.button") } }
}

struct GlassCardBackground: View {
    let cornerRadius: CGFloat
    let strength: Double
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear).glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.ultraThinMaterial)
        }
    }
}
