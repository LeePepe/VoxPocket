import SwiftUI
import CoreModels

public struct HomeRecorderView<VM: EditorViewState>: View {
    @ObservedObject var viewModel: VM
    let recorderStatus: RecorderStatus
    let onCopyRefined: (String) -> Void
    let onCopyRaw: (String) -> Void
    let onOpenTodoList: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var foldExpanded = false
    @State private var gestureController = RecorderGestureController()
    @Namespace private var glassNamespace

    public init(viewModel: VM, recorderStatus: RecorderStatus, onCopyRefined: @escaping (String) -> Void,
                onCopyRaw: @escaping (String) -> Void, onOpenTodoList: @escaping () -> Void = {},
                onOpenSettings: @escaping () -> Void = {}) {
        self.viewModel = viewModel; self.recorderStatus = recorderStatus
        self.onCopyRefined = onCopyRefined; self.onCopyRaw = onCopyRaw
        self.onOpenTodoList = onOpenTodoList; self.onOpenSettings = onOpenSettings
    }

    private var sentence: String {
        if viewModel.isRecording { return viewModel.liveTranscription.isEmpty ? "正在聆听你的灵感，松手立即润色…" : viewModel.liveTranscription }
        if viewModel.isRefining { return viewModel.streamingRefinedText.isEmpty ? "正在提炼语句结构与核心要点…" : viewModel.streamingRefinedText }
        return viewModel.text.isEmpty ? "按住底部玻璃说话，松手即刻生成润色笔记。" : viewModel.text
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            BackgroundAtmosphere(status: recorderStatus, audioLevel: Double(viewModel.audioLevel)).ignoresSafeArea()
            ScrollView { Text(sentence)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .tracking(-0.4).lineSpacing(7).multilineTextAlignment(.center)
                .frame(maxWidth: 360).frame(maxWidth: .infinity, minHeight: 420)
                .contentShape(Rectangle())
                .onTapGesture { if !viewModel.isRecording && !viewModel.isRefining && !viewModel.text.isEmpty { onCopyRefined(viewModel.text) } }
                .accessibilityIdentifier("vox.transcript.final")
                .accessibilityLabel(sentence)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, 22).padding(.bottom, 148)
            dock
        }
        .voxTheme()
        .onChange(of: viewModel.autoCopiedText) { _, value in
            if let value, !value.isEmpty { onCopyRefined(value); viewModel.autoCopiedText = nil }
        }
    }

    private var dock: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                foldMenu
                Spacer(minLength: 4)
                WaveformBars(level: viewModel.audioLevel, active: viewModel.isRecording)
                Spacer(minLength: 4)
                recordButton
            }
            .padding(.horizontal, 20).frame(minHeight: 124)
            .background(reduceTransparency ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.clear), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            .modifier(GlassDockModifier(reduceTransparency: reduceTransparency))
        }
    }

    private var foldMenu: some View {
        HStack(spacing: 8) {
            Button { withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) { foldExpanded.toggle() } } label: {
                Image(systemName: foldExpanded ? "xmark" : "square.stack.3d.up")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(foldExpanded ? "收起菜单" : "展开菜单")
            .accessibilityIdentifier("vox.fold.menu.button")
            if foldExpanded {
                Button("待办", systemImage: "checklist", action: onOpenTodoList)
                    .accessibilityIdentifier("vox.fold.todoList.button")
                    .glassEffectID("vox.fold.todoList.button", in: glassNamespace)
                Button("设置", systemImage: "gearshape", action: onOpenSettings)
                    .accessibilityIdentifier("vox.fold.settings.button")
                    .glassEffectID("vox.fold.settings.button", in: glassNamespace)
            }
        }
        .buttonStyle(.borderless)
        .modifier(GlassControlModifier(reduceTransparency: reduceTransparency))
    }

    private var recordButton: some View {
        Button { toggleFromActivation() } label: {
            Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.borderless)
        .modifier(GlassPrimaryModifier(reduceTransparency: reduceTransparency))
        .accessibilityIdentifier(viewModel.isRecording ? "vox.stop.button" : "vox.record.button")
        .accessibilityLabel(viewModel.isRecording ? "停止录音" : "开始录音")
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in beginPress() }.onEnded { _ in endPress() })
    }

    private func toggleFromActivation() {
        guard !viewModel.isRefining else { return }
        Task { await viewModel.toggleRecording() }
    }
    private func beginPress() {
        guard !viewModel.isRefining else { return }
        if gestureController.begin(isRecording: viewModel.isRecording) == .start {
            Task { await viewModel.startRecording() }
        }
    }
    private func endPress() {
        if gestureController.end() == .stop { Task { await viewModel.stopRecording() } }
    }
}

struct RefinedTextPane: View { let text: String; var body: some View { Text(text).font(.system(size: 25, weight: .semibold, design: .rounded)).lineSpacing(7).tracking(-0.4).accessibilityIdentifier("vox.transcript.final") } }
struct RawInlinePane: View { let text: String; let onCopy: () -> Void; var body: some View { VStack { HStack { Text("原始转写"); Spacer(); Button(action: onCopy) { Image(systemName: "doc.on.doc") } }; Text(text) } } }

struct BottomControls: View {
    let status: RecorderStatus; let onStopOrRestart: () -> Void; let onCopy: () -> Void; let onNewSession: () -> Void
    var body: some View { HStack { Button("新建", action: onNewSession); Spacer(); Button(action: onCopy) { Image(systemName: "doc.on.doc") }; Button(status == .listening ? "停止" : "继续", action: onStopOrRestart).accessibilityIdentifier(status == .listening ? "vox.stop.button" : "vox.record.button") } }
}

private struct WaveformBars: View {
    let level: Float; let active: Bool
    var body: some View { HStack(spacing: 3) { ForEach(0..<7, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(Color.cyan).frame(width: 4, height: max(6, CGFloat(max(0.12, level)) * CGFloat([0.45,0.7,1,0.6,0.85,0.55,0.75][i]) * 28)) } }.frame(height: 32).opacity(active ? 1 : 0.45) }
}
private struct GlassDockModifier: ViewModifier { let reduceTransparency: Bool; func body(content: Content) -> some View { if reduceTransparency { content.background(.thickMaterial) } else if #available(iOS 26.0, macOS 26.0, *) { content.glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)) } else { content.background(.ultraThinMaterial) } } }
private struct GlassControlModifier: ViewModifier { let reduceTransparency: Bool; func body(content: Content) -> some View { if reduceTransparency { content.background(.thickMaterial, in: .capsule) } else if #available(iOS 26.0, macOS 26.0, *) { content.glassEffect(.regular.interactive(), in: .capsule) } else { content.background(.ultraThinMaterial, in: .capsule) } } }
private struct GlassPrimaryModifier: ViewModifier { let reduceTransparency: Bool; func body(content: Content) -> some View { if reduceTransparency { content.background(.thickMaterial, in: .circle) } else if #available(iOS 26.0, macOS 26.0, *) { content.glassEffect(.regular.interactive(), in: .circle) } else { content.background(.ultraThinMaterial, in: .circle) } } }

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
