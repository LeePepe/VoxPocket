import SwiftUI
import CoreModels

#if os(iOS)
@MainActor
public struct IOSCleanSlateWorkspaceView: View {
    @ObservedObject private var viewModel: VoxWorkspaceViewModel
    @State private var selectedTab = 0
    @State private var selectedTodo: VoiceTodo?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeAnimation

    public init(viewModel: VoxWorkspaceViewModel) { self.viewModel = viewModel }

    public var body: some View {
        TabView(selection: $selectedTab) {
            notesTab.tag(0).tabItem { Label("速记", systemImage: "waveform.and.mic") }
            todosTab.tag(1).tabItem { Label("待办", systemImage: "checklist") }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("设置", systemImage: "gear") {} } }
        .safeAreaInset(edge: .bottom) { captureDock }
        .sheet(item: $selectedTodo) { todo in IOSCleanSlateTodoDetail(todo: todo, viewModel: viewModel) }
    }

    private var notesTab: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.filteredCaptures.isEmpty { ContentUnavailableView("暂无速记", systemImage: "waveform", description: Text("开始一次录音即可看到本地语音笔记。")) }
                    ForEach(viewModel.filteredCaptures) { capture in IOSCleanSlateCaptureCard(capture: capture, viewModel: viewModel) }
                }.padding()
            }.navigationTitle("语音速记")
        }
    }

    private var todosTab: some View {
        NavigationStack {
            List {
                if viewModel.filteredTodos.isEmpty { ContentUnavailableView(viewModel.searchQuery.isEmpty ? "暂无待办" : "没有匹配结果", systemImage: "checklist", description: Text(viewModel.searchQuery.isEmpty ? "从文字速记中转为 Todo。" : "尝试清空搜索词。")) }
                ForEach(viewModel.filteredTodos) { todo in
                    Button { selectedTodo = todo } label: { IOSCleanSlateTodoRow(todo: todo, viewModel: viewModel) }.buttonStyle(.plain)
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "搜索待办")
            .toolbar { ToolbarItem(placement: .principal) { IOSStatusFilters(viewModel: viewModel) } }
            .navigationTitle("待办")
        }
    }

    private var captureDock: some View {
        VStack(spacing: 12) {
            if case .recording = viewModel.captureState { recordingControls } else { modeSwitcher }
            Button { viewModel.captureState == .idle ? viewModel.startCapture(mode: viewModel.selectedCaptureMode) : viewModel.finishCapture() } label: {
                Image(systemName: viewModel.captureState == .idle ? "mic.fill" : "stop.fill").font(.title2).frame(width: 52, height: 52)
            }
            .foregroundStyle(.white).background(viewModel.captureState == .idle ? (viewModel.selectedCaptureMode == .todo ? .orange : .accentColor) : .red, in: Circle())
            .accessibilityLabel(viewModel.captureState == .idle ? "开始录音" : "停止录音")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(reduceTransparency ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
        .shadow(radius: 12)
        .animation(reduceMotion ? nil : .snappy, value: viewModel.captureState)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button(mode == .text ? "文字" : "Todo") { viewModel.selectedCaptureMode = mode }
                    .frame(minWidth: 64, minHeight: 44)
                    .background(viewModel.selectedCaptureMode == mode ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                    .matchedGeometryEffect(id: "mode", in: modeAnimation, isSource: viewModel.selectedCaptureMode == mode)
                    .accessibilityLabel(mode == .text ? "文字模式" : "Todo 模式")
            }
        }.buttonStyle(.plain).sensoryFeedback(.selection, trigger: viewModel.selectedCaptureMode)
    }

    private var recordingControls: some View {
        HStack { Button("取消", systemImage: "xmark") { viewModel.cancelCapture() }; Spacer(); Text("录音中").font(.caption); Spacer(); Button("完成", systemImage: "checkmark") { viewModel.finishCapture() } }
            .frame(minHeight: 44)
    }
}

private struct IOSCleanSlateCaptureCard: View {
    let capture: VoiceCapture
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(capture.mode == .todo ? "Todo 语音" : "语音速记").font(.headline); Spacer(); Text(Self.duration(capture.durationSeconds)).monospacedDigit().font(.caption) }
            Text(capture.refinedText.isEmpty ? capture.rawTranscript : capture.refinedText).textSelection(.enabled)
            HStack { Button("播放", systemImage: viewModel.playingCaptureID == capture.id ? "pause.fill" : "play.fill") { viewModel.playingCaptureID = viewModel.playingCaptureID == capture.id ? nil : capture.id }.frame(minWidth: 44, minHeight: 44); Button("转为 Todo", systemImage: "checklist") { viewModel.convertCaptureToTodo(capture.id) }; if case .failed = capture.state { Button("重试") { viewModel.retryCapture(capture.id) } } }
        }.padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private static func duration(_ value: TimeInterval) -> String { String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60) }
}

private struct IOSCleanSlateTodoRow: View { let todo: VoiceTodo; @ObservedObject var viewModel: VoxWorkspaceViewModel; var body: some View { HStack { Image(systemName: todo.executionState == .done ? "checkmark.circle.fill" : "circle").foregroundStyle(todo.executionState == .done ? .green : .secondary); VStack(alignment: .leading) { Text(todo.title); Text(todo.projectKey ?? "收件箱").font(.caption).foregroundStyle(.secondary) }; Spacer(); if todo.executionState == .running { ProgressView() } } .padding(.vertical, 4) } }

private struct IOSStatusFilters: View { @ObservedObject var viewModel: VoxWorkspaceViewModel; var body: some View { Menu { ForEach(TodoStatusFilter.allCases, id: \.self) { filter in Button(filter.title) { viewModel.selectedTodoFilter = filter } } } label: { Label(viewModel.selectedTodoFilter.title, systemImage: "line.3.horizontal.decrease.circle") } } }

private extension TodoStatusFilter { var title: String { switch self { case .all: "全部"; case .inbox: "待处理"; case .running: "执行中"; case .done: "已完成"; case .failed: "失败" } } }

private struct IOSCleanSlateTodoDetail: View { let todo: VoiceTodo; @ObservedObject var viewModel: VoxWorkspaceViewModel; @Environment(\.dismiss) private var dismiss; @State private var title: String; @State private var prompt: String; init(todo: VoiceTodo, viewModel: VoxWorkspaceViewModel) { self.todo = todo; self.viewModel = viewModel; _title = State(initialValue: todo.title); _prompt = State(initialValue: todo.taskPrompt) }; var body: some View { NavigationStack { Form { TextField("标题", text: $title); TextField("任务提示", text: $prompt, axis: .vertical); Text(todo.lastExecutionSummary ?? "尚未执行").foregroundStyle(.secondary) }.navigationTitle("编辑 Todo").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { viewModel.saveTodoEdits(id: todo.id, title: title, taskPrompt: prompt, projectKey: todo.projectKey); dismiss() } } } }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible) } }
#endif
