import SwiftUI
import CoreModels

#if os(macOS)
@MainActor
public struct MacOSCleanSlateWorkspaceView: View {
    @ObservedObject private var viewModel: VoxWorkspaceViewModel
    public init(viewModel: VoxWorkspaceViewModel) { self.viewModel = viewModel }
    public var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedSidebarSection) {
                Section("待办任务") { sidebar("收件箱 / 待处理", .todoInbox, "tray", viewModel.inboxCount); sidebar("AI 执行中", .todoRunning, "sparkles", viewModel.runningCount); sidebar("已完成", .todoDone, "checkmark.circle", viewModel.doneCount); sidebar("全部待办", .todoAll, "checklist", viewModel.totalTodoCount) }
                Section("语音速记") { sidebar("最近速记", .voiceNotes, "waveform", viewModel.filteredCaptures.count) }
                Section("项目筛选") { ForEach(viewModel.projectBindings) { binding in sidebar(binding.displayName, .project(binding.projectKey), "folder", viewModel.projectCounts[binding.projectKey] ?? 0) } }
            }.navigationTitle("VoxPocket")
        } content: {
            VStack(spacing: 0) {
                HStack { Text(viewModel.selectedSidebarSection.title).font(.title2.bold()); Spacer(); TextField("搜索", text: $viewModel.searchQuery).textFieldStyle(.roundedBorder).frame(maxWidth: 240); Menu("筛选") { Button("最新") { viewModel.sortOrder = .newestFirst }; Button("最早") { viewModel.sortOrder = .oldestFirst } } }
                    .padding()
                if viewModel.selectedSidebarSection == .voiceNotes {
                    List(selection: $viewModel.selectedCaptureID) {
                        if viewModel.filteredCaptures.isEmpty { ContentUnavailableView("暂无速记", systemImage: "waveform", description: Text("清除搜索后重试")) }
                        ForEach(viewModel.filteredCaptures) { capture in Text(capture.refinedText.isEmpty ? capture.rawTranscript : capture.refinedText).lineLimit(2).tag(capture.id) }
                    }
                } else {
                    List(selection: $viewModel.selectedTodoID) {
                        if viewModel.filteredTodos.isEmpty { ContentUnavailableView("暂无待办", systemImage: "checklist", description: Text("清除搜索后重试")) }
                        ForEach(viewModel.filteredTodos) { todo in HStack { VStack(alignment: .leading) { Text(todo.title); Text(todo.projectKey ?? "收件箱").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("交给 AI 执行", systemImage: "sparkles") { viewModel.runTodoWithAI(todo.id, projectID: viewModel.projectBindings.first(where: { $0.projectKey == todo.projectKey })?.id) }.frame(minWidth: 28, minHeight: 28).buttonStyle(.borderless) }.tag(todo.id) }
                    }
                }
            }.toolbar { ToolbarItem { Button("录文字 ⌥Space", systemImage: "mic") { viewModel.startCapture(mode: .text) } }; ToolbarItem { Button("记 Todo ⌥⇧Space", systemImage: "checklist") { viewModel.startCapture(mode: .todo) } } }
        } detail: {
            if viewModel.selectedSidebarSection == .voiceNotes {
                if let capture = viewModel.captures.first(where: { $0.id == viewModel.selectedCaptureID }) { MacOSCleanSlateCaptureInspector(capture: capture, viewModel: viewModel) } else { ContentUnavailableView("选择一个速记", systemImage: "waveform") }
            } else if let todo = viewModel.todos.first(where: { $0.id == viewModel.selectedTodoID }) { MacOSCleanSlateInspector(todo: todo, viewModel: viewModel) } else { ContentUnavailableView("选择一个待办", systemImage: "sidebar.right") }
        }
        .frame(minWidth: 960, minHeight: 620)
    }
    private func sidebar(_ title: String, _ section: WorkspaceSidebarSection, _ icon: String, _ count: Int) -> some View { Label { HStack { Text(title); Spacer(); Text("\(count)").monospacedDigit().contentTransition(.numericText()) } } icon: { Image(systemName: icon) }.tag(section) }
}

private struct MacOSCleanSlateInspector: View {
    let todo: VoiceTodo; @ObservedObject var viewModel: VoxWorkspaceViewModel
    @State private var title: String; @State private var prompt: String; @State private var projectKey: String
    init(todo: VoiceTodo, viewModel: VoxWorkspaceViewModel) { self.todo = todo; self.viewModel = viewModel; _title = State(initialValue: todo.title); _prompt = State(initialValue: todo.taskPrompt); _projectKey = State(initialValue: todo.projectKey ?? "") }
    var body: some View { Form { Section("任务") { TextField("标题", text: $title); TextField("任务提示", text: $prompt, axis: .vertical); Picker("项目", selection: $projectKey) { Text("收件箱").tag(""); ForEach(viewModel.projectBindings) { Text("\($0.displayName) · \($0.localDirectoryPath)").tag($0.projectKey) } } }; Section("AI") { Picker("执行器", selection: .constant(todo.assignedRunnerKind ?? .herdr)) { ForEach(AIRunnerKind.allCases, id: \.self) { Text($0.label).tag($0) } }; Button("交给 AI 开始执行 (Run with AI)") { viewModel.runTodoWithAI(todo.id, projectID: viewModel.projectBindings.first(where: { $0.projectKey == projectKey })?.id) }.buttonStyle(.borderedProminent) }; Section("执行摘要") { Text(todo.lastExecutionSummary ?? "尚未执行").foregroundStyle(.secondary) } }.formStyle(.grouped).padding() }
}

private struct MacOSCleanSlateCaptureInspector: View {
    let capture: VoiceCapture
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    var body: some View {
        Form {
            Section("精炼文本") { Text(capture.refinedText.isEmpty ? capture.rawTranscript : capture.refinedText).textSelection(.enabled) }
            Section { Button("转为 Todo", systemImage: "checklist") { viewModel.convertCaptureToTodo(capture.id) }; if case .failed = capture.state { Button("重试") { viewModel.retryCapture(capture.id) } } }
        }.formStyle(.grouped).padding()
    }
}

private extension WorkspaceSidebarSection { var title: String { switch self { case .todoInbox: "收件箱 / 待处理"; case .todoRunning: "AI 执行中"; case .todoDone: "已完成"; case .todoAll: "全部待办"; case .voiceNotes: "最近速记"; case .project(let key): key } } }
private extension AIRunnerKind { var label: String { switch self { case .herdr: "Herdr"; case .claudeCode: "Claude Code"; case .codex: "Codex"; case .customShell: "Custom Shell" } } }
#endif
