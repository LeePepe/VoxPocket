import SwiftUI
import CoreModels
import Preferences

#if os(iOS)
@MainActor
public struct IOSCleanSlateWorkspaceView: View {
    @ObservedObject private var viewModel: VoxWorkspaceViewModel
    private let localModelLoadingStatus: LocalModelLoadingStatus?
    @State private var isShowingNotesSheet = false
    @State private var isShowingSettingsSheet = false

    public init(viewModel: VoxWorkspaceViewModel, localModelLoadingStatus: LocalModelLoadingStatus? = nil) {
        self.viewModel = viewModel
        self.localModelLoadingStatus = localModelLoadingStatus
    }

    public var body: some View {
        NavigationStack {
            RecorderSentenceStage(sentence: stageSentence) {
                guard !viewModel.isRecordingActive, !viewModel.isProcessingCapture else { return }
                viewModel.copyLatestCompletedText()
            }
            .background { RecorderBackdrop(status: viewModel.recorderStatus, audioLevel: viewModel.audioLevel) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RecorderDock(isRecording: viewModel.isRecordingActive, isProcessing: viewModel.isProcessingCapture,
                             audioLevel: viewModel.audioLevel, feedback: feedback, error: captureError,
                             start: { await viewModel.startCaptureAndWait() },
                             stop: { await viewModel.completeCapture(deviceSource: .iPhone) },
                             cancel: { viewModel.cancelCapture() }, retry: retry,
                             openTodos: { isShowingNotesSheet = true }, openSettings: { isShowingSettingsSheet = true })
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $isShowingNotesSheet) { IOSWorkspaceManagementSheet(viewModel: viewModel) }
        .sheet(isPresented: $isShowingSettingsSheet) {
            IOSWorkspaceSettingsSheet(viewModel: viewModel, localModelLoadingStatus: localModelLoadingStatus)
        }
        .preferredColorScheme(demoAppearance)
        .sensoryFeedback(.success, trigger: viewModel.lastCopiedBannerText)
        .task {
            let env = ProcessInfo.processInfo.environment
            if env["VOX_DEMO_SEED"] == "1" { await viewModel.seedDemoDataIfEmptyForPreview() }
            if env["VOX_DEMO_REFINED"] == "1" { await viewModel.prepareDemoRefinedState() }
            if env["VOX_DEMO_RECORDING"] == "1" && env["VOX_DEMO_AUTOSTART"] != "0" {
                await viewModel.startCaptureAndWait()
            }
        }
    }

    private var demoAppearance: ColorScheme? {
        let env = ProcessInfo.processInfo.environment
        guard env["VOXPOCKET_UI_TEST_HOST"] == "1" || env["VOX_DEMO_SEED"] == "1" || env["VOX_DEMO_RECORDING"] == "1" || env["VOX_DEMO_REFINED"] == "1" else { return nil }
        switch env["VOX_DEMO_APPEARANCE"] {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var stageSentence: String {
        if viewModel.isRecordingActive { return viewModel.liveTranscription.isEmpty ? "正在聆听你的灵感，松手立即润色…" : viewModel.liveTranscription }
        if viewModel.isProcessingCapture { return viewModel.streamingRefinedText.isEmpty ? "正在提炼语句结构与核心要点…" : viewModel.streamingRefinedText }
        return viewModel.latestCompletedText.isEmpty ? "按住底部玻璃说话，松手即刻生成润色笔记。" : viewModel.latestCompletedText
    }

    private var feedback: String {
        if viewModel.isRecordingActive { return "正在聆听 · \(Self.formatDuration(TimeInterval(viewModel.recordingElapsedSeconds))) · 松手立即润色" }
        if viewModel.isProcessingCapture { return "正在提炼语句结构与核心要点…" }
        return viewModel.lastCopiedBannerText ?? "按住说话 · 点按也可启停"
    }

    private var captureError: String? {
        if case .failed(_, let reason) = viewModel.captureState { return reason }
        return nil
    }

    private func retry() {
        if let failed = viewModel.captures.first(where: { if case .failed = $0.state { return true }; return false }) {
            viewModel.retryCapture(failed.id)
        } else { viewModel.startCaptureInPreferredMode() }
    }

    static func formatDuration(_ value: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60)
    }
}

private struct IOSWorkspaceManagementSheet: View {
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    @State private var selectedTodo: VoiceTodo?
    @Namespace private var filterAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusFilterStrip
                    todoPrimaryStage
                    Text("语音速记").font(.title2.bold())
                    ForEach(viewModel.filteredCaptures) { capture in
                        IOSCleanSlateCaptureCard(capture: capture, viewModel: viewModel)
                    }
                }
                .padding(22)
            }
            .background(AppTheme.surfacePrimary)
            .searchable(text: $viewModel.searchQuery, prompt: "搜索待办与语音速记")
            .navigationTitle("待办与语音速记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $selectedTodo) { todo in IOSCleanSlateTodoDetail(todo: todo, viewModel: viewModel) }
        }
    }

    private var statusFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Space.sm) {
                ForEach(TodoStatusFilter.primaryFilters, id: \.self) { filter in
                    let isSelected = viewModel.selectedTodoFilter == filter
                    let count = countForFilter(filter)
                    Button {
                        withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                            viewModel.selectedTodoFilter = filter
                        }
                    } label: {
                        HStack(spacing: AppTheme.Space.xs) {
                            Text(filter.title)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            Text("\(count)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .contentTransition(.numericText())
                                .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                        .padding(.horizontal, AppTheme.Space.md)
                        .padding(.vertical, AppTheme.Space.sm)
                        .frame(minHeight: 44)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.16))
                                    .matchedGeometryEffect(id: "todoFilterPill", in: filterAnimation)
                            } else {
                                Capsule()
                                    .fill(AppTheme.surfaceCard)
                            }
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    }
                    .buttonStyle(AppPressableButtonStyle())
                    .accessibilityIdentifier("vox.ios.filter.\(filter.rawValue)")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedTodoFilter)
    }

    // MARK: - Group 2: Todo Primary Stage (Borderless Luminance Cards)

    @ViewBuilder
    private var todoPrimaryStage: some View {
        if viewModel.filteredTodos.isEmpty {
            todoEmptyState
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Space.section)
                .accessibilityIdentifier("vox.session.list")
        } else {
            LazyVStack(spacing: AppTheme.Space.md) {
                ForEach(viewModel.filteredTodos) { todo in
                    IOSCleanSlateTodoCard(
                        todo: todo,
                        onToggleDone: { viewModel.toggleTodoDone(todo.id) },
                        onOpenDetail: { selectedTodo = todo }
                    )
                    .accessibilityIdentifier("vox.session.list.item")
                }
            }
            .accessibilityIdentifier("vox.session.list")
        }
    }

    private var todoEmptyState: some View {
        VStack(spacing: AppTheme.Space.md) {
            if !viewModel.searchQuery.isEmpty {
                ContentUnavailableView {
                    Label("没有匹配结果", systemImage: "magnifyingglass")
                } description: {
                    Text("尝试清空搜索词。")
                } actions: {
                    Button("清除搜索后重试") {
                        viewModel.clearSearchPreservingFilters()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView {
                    Label("暂无待办", systemImage: "checklist")
                } description: {
                    Text("按操作按钮或点按下方麦克风，一句话直接生成待办。")
                }
            }
        }
    }

    private func countForFilter(_ filter: TodoStatusFilter) -> Int {
        switch filter {
        case .all: viewModel.totalTodoCount
        case .inbox: viewModel.inboxCount
        case .running: viewModel.runningCount
        case .done: viewModel.doneCount
        case .failed: viewModel.failedCount
        }
    }

}

// MARK: - Borderless Luminance Todo Card

private struct IOSCleanSlateTodoCard: View {
    let todo: VoiceTodo
    let onToggleDone: () -> Void
    let onOpenDetail: () -> Void

    private var isDone: Bool { todo.executionState == .done }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Space.md) {
            Button(action: onToggleDone) {
                Image(systemName: statusSymbol)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppPressableButtonStyle())
            .accessibilityLabel(isDone ? "已完成" : "待处理")

            Button(action: onOpenDetail) {
                VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                    Text(todo.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .multilineTextAlignment(.leading)

                    if !todo.rawTranscript.isEmpty && todo.rawTranscript != todo.title {
                        Text(todo.rawTranscript)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: AppTheme.Space.sm) {
                        Label(todo.projectKey ?? "收件箱", systemImage: todo.projectKey == nil ? "tray" : "folder")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppTheme.Space.sm)
                            .padding(.vertical, 3)
                            .background(AppTheme.surfaceElevated, in: Capsule())

                        if todo.executionState == .running {
                            HStack(spacing: AppTheme.Space.xs) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("AI 执行中")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.blue)
                            }
                        } else if let summary = todo.lastExecutionSummary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppTheme.Space.lg)
                .padding(.trailing, AppTheme.Space.lg)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, AppTheme.Space.xs)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }

    private var statusSymbol: String {
        switch todo.executionState {
        case .inbox: "circle"
        case .running: "bolt.horizontal.circle.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch todo.executionState {
        case .inbox: .secondary
        case .running: .blue
        case .done: .green
        case .failed: .orange
        }
    }
}

// MARK: - Settings Sheet (Zero-Guessing Destination Switcher + Action Button Guide)

private struct IOSWorkspaceSettingsSheet: View {
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    let localModelLoadingStatus: LocalModelLoadingStatus?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach([CaptureMode.todo, CaptureMode.text], id: \.self) { mode in
                        Button {
                            viewModel.updatePreferredCaptureMode(mode)
                        } label: {
                            HStack(spacing: AppTheme.Space.md) {
                                Image(systemName: mode == .todo ? "checklist" : "doc.on.clipboard")
                                    .font(.title3)
                                    .foregroundStyle(mode == .todo ? Color.orange : Color.accentColor)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                                    Text(mode == .todo ? "直接存入待办" : "自动复制到剪贴板")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(mode == .todo ? "自动提炼标题并加入首页待办清单" : "润色为干净文字并复制，方便直接粘贴")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedCaptureMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, AppTheme.Space.xs)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("vox.ios.settings.destination.\(mode.rawValue)")
                    }
                } header: {
                    Text("录音完成后去向")
                } footer: {
                    Text("通过 iPhone 操作按钮或底部麦克风启动快速录音时，将默认按此去向处理。")
                }

                Section {
                    VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                        Label("不进 App · 后台一键启停录音", systemImage: "button.vertical.left.press")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("① 操作按钮：在系统「设置 → 操作按钮 → 快捷指令」中选择「开始或停止录音」，按一下直接在后台录音并弹出灵动岛，再按一下即可停止并按去向保存。\n② 桌面/锁屏/控制中心小组件：添加「VoxPocket 快速录音」小组件，点按即可在后台启停录音，无需打开主界面。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.Space.xs)
                } header: {
                    Text("快捷触发")
                }

                if let status = localModelLoadingStatus, status.state != .idle {
                    Section("本地模型") {
                        Text(status.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct IOSCleanSlateCaptureCard: View {
    let capture: VoiceCapture
    @ObservedObject var viewModel: VoxWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            HStack {
                Text(capture.mode == .todo ? "存入待办" : "语音速记")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(capture.mode == .todo ? Color.orange : Color.accentColor)
                Spacer()
                Text(IOSCleanSlateWorkspaceView.formatDuration(capture.durationSeconds))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(capture.refinedText.isEmpty ? capture.rawTranscript : capture.refinedText)
                .font(.body)
                .textSelection(.enabled)
            HStack(spacing: AppTheme.Space.md) {
                Button("复制文字", systemImage: "doc.on.doc") {
                    viewModel.copyCaptureText(capture)
                }
                .font(.footnote.weight(.medium))
                .frame(minHeight: 44)

                Button("转为 Todo", systemImage: "checklist") {
                    viewModel.convertCaptureToTodo(capture.id)
                }
                .font(.footnote.weight(.medium))
                .frame(minHeight: 44)

                if case .failed = capture.state {
                    Button("重试", systemImage: "arrow.clockwise") {
                        viewModel.retryCapture(capture.id)
                    }
                    .font(.footnote.weight(.medium))
                    .frame(minHeight: 44)
                }
            }
        }
        .padding(AppTheme.Space.lg)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }
}

private extension TodoStatusFilter {
    static var primaryFilters: [TodoStatusFilter] {
        [.all, .inbox, .running, .done]
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .inbox: "待处理"
        case .running: "AI 执行中"
        case .done: "已完成"
        case .failed: "失败"
        }
    }
}

private struct IOSCleanSlateTodoDetail: View {
    let todo: VoiceTodo
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var prompt: String

    init(todo: VoiceTodo, viewModel: VoxWorkspaceViewModel) {
        self.todo = todo
        self.viewModel = viewModel
        _title = State(initialValue: todo.title)
        _prompt = State(initialValue: todo.taskPrompt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("标题", text: $title)
                    TextField("任务提示", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("执行摘要") {
                    Text(todo.lastExecutionSummary ?? "尚未执行")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑 Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        viewModel.saveTodoEdits(
                            id: todo.id,
                            title: title,
                            taskPrompt: prompt,
                            projectKey: todo.projectKey
                        )
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
