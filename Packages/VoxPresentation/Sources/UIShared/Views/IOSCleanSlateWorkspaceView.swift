import SwiftUI
import CoreModels
import Preferences

#if os(iOS)
@MainActor
public struct IOSCleanSlateWorkspaceView: View {
    @ObservedObject private var viewModel: VoxWorkspaceViewModel
    private let localModelLoadingStatus: LocalModelLoadingStatus?
    @State private var isShowingSettingsSheet = false
    @GestureState private var dragTranslation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(viewModel: VoxWorkspaceViewModel, localModelLoadingStatus: LocalModelLoadingStatus? = nil) {
        self.viewModel = viewModel
        self.localModelLoadingStatus = localModelLoadingStatus
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let pageWidth = max(1, geometry.size.width)
                let drag = clampedHorizontalDrag(dragTranslation, pageWidth: pageWidth)

                ZStack {
                    if viewModel.activePage == .recorder || drag != 0 {
                        recorderStagePage
                            .frame(width: pageWidth, height: geometry.size.height)
                            .offset(x: (viewModel.activePage == .recorder ? 0 : -pageWidth) + drag)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .leading),
                                removal: .move(edge: .leading)
                            ))
                    }

                    if viewModel.activePage == .todo || drag != 0 {
                        todoStagePage
                            .frame(width: pageWidth, height: geometry.size.height)
                            .offset(x: (viewModel.activePage == .todo ? 0 : pageWidth) + drag)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .trailing)
                            ))
                    }
                }
                .animation(reduceMotion ? nil : AppTheme.gestureSpring, value: viewModel.activePage)
                .frame(width: pageWidth, height: geometry.size.height)
                .clipped()
                .simultaneousGesture(horizontalSlideGesture(pageWidth: pageWidth))
            }
            .background { RecorderBackdrop(status: viewModel.recorderStatus, audioLevel: viewModel.audioLevel) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                IOSDualButtonSlideDock(
                    activePage: viewModel.activePage,
                    pendingTodoCount: viewModel.inboxCount + viewModel.runningCount,
                    isRecording: viewModel.isRecordingActive,
                    isProcessing: viewModel.isProcessingCapture,
                    audioLevel: viewModel.audioLevel,
                    appendingTodoTitle: viewModel.appendingTargetTodoTitle,
                    feedback: feedback,
                    error: captureError,
                    togglePage: {
                        withAnimation(reduceMotion ? nil : AppTheme.gestureSpring) {
                            viewModel.toggleActivePage()
                        }
                    },
                    start: { await viewModel.startCaptureAndWait() },
                    stop: { await viewModel.completeCapture(deviceSource: .iPhone) },
                    cancel: { viewModel.cancelCapture() },
                    retry: retry
                )
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $isShowingSettingsSheet) {
            IOSWorkspaceSettingsSheet(viewModel: viewModel, localModelLoadingStatus: localModelLoadingStatus)
        }
        .preferredColorScheme(demoAppearance)
        .sensoryFeedback(.success, trigger: viewModel.lastCopiedBannerText)
        .sensoryFeedback(.selection, trigger: viewModel.activePage)
        .task {
            let env = ProcessInfo.processInfo.environment
            if env["VOX_DEMO_SEED"] == "1" { await viewModel.seedDemoDataIfEmptyForPreview() }
            if env["VOX_DEMO_REFINED"] == "1" { await viewModel.prepareDemoRefinedState() }
            if env["VOX_DEMO_PAGE"] == "todo" {
                viewModel.switchToPage(.todo)
            }
            if env["VOX_DEMO_EXPAND_FIRST_TODO"] == "1" {
                viewModel.switchToPage(.todo)
                let targetID = viewModel.todos.first(where: { $0.title.contains("整理下周设计评审") })?.id ?? viewModel.todos.first?.id
                viewModel.expandedTodoID = targetID
            }
            if env["VOX_DEMO_OPEN_TAG_PICKER"] == "1" {
                viewModel.switchToPage(.todo)
                let targetID = viewModel.todos.first(where: { $0.title.contains("整理下周设计评审") })?.id ?? viewModel.todos.first?.id
                viewModel.expandedTodoID = targetID
            }
            if env["VOX_DEMO_RECORDING"] == "1" && env["VOX_DEMO_AUTOSTART"] != "0" {
                await viewModel.startCaptureAndWait()
            }
            if env["VOX_OPEN_SETTINGS"] == "1" {
                isShowingSettingsSheet = true
            }
        }
    }

    private var recorderStagePage: some View {
        RecorderSentenceStage(sentence: stageSentence) {
            guard !viewModel.isRecordingActive, !viewModel.isProcessingCapture else { return }
            viewModel.copyLatestCompletedText()
        }
    }

    private var todoStagePage: some View {
        IOSTodoSlidePageView(
            viewModel: viewModel,
            onOpenSettings: { isShowingSettingsSheet = true }
        )
    }

    private func clampedHorizontalDrag(_ rawDrag: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        switch viewModel.activePage {
        case .recorder:
            return min(rawDrag * 0.18, max(-pageWidth, rawDrag))
        case .todo:
            return max(rawDrag * 0.18, min(pageWidth, rawDrag))
        }
    }

    private func horizontalSlideGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
                let threshold = max(56, pageWidth * 0.18)
                let predicted = value.predictedEndTranslation.width
                withAnimation(reduceMotion ? nil : AppTheme.gestureSpring) {
                    if viewModel.activePage == .recorder && (value.translation.width < -threshold || predicted < -threshold * 1.4) {
                        viewModel.switchToPage(.todo)
                    } else if viewModel.activePage == .todo && (value.translation.width > threshold || predicted > threshold * 1.4) {
                        viewModel.switchToPage(.recorder)
                    }
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
        if viewModel.isRecordingActive {
            if let appendTitle = viewModel.appendingTargetTodoTitle {
                return "正在继续补充至：\(appendTitle) · \(Self.formatDuration(TimeInterval(viewModel.recordingElapsedSeconds)))"
            }
            return "正在聆听 · \(Self.formatDuration(TimeInterval(viewModel.recordingElapsedSeconds))) · 松手立即润色"
        }
        if viewModel.isProcessingCapture { return "正在提炼语句结构与核心要点…" }
        if let banner = viewModel.lastCopiedBannerText { return banner }
        if viewModel.activePage == .todo, let expanded = viewModel.expandedTodo {
            return "按住右侧录音键，直接补充至「\(expanded.title)」"
        }
        return viewModel.activePage == .todo ? "按住右侧说话新建待办 · 左下返回录音页" : "按住说话 · 点按也可启停"
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

// MARK: - Ultra-Pure 2-Button Bottom Bar (Bottom-Leading Switch + Bottom-Trailing Persistent Record)

private struct IOSDualButtonSlideDock: View {
    let activePage: WorkspacePage
    let pendingTodoCount: Int
    let isRecording: Bool
    let isProcessing: Bool
    let audioLevel: Float
    let appendingTodoTitle: String?
    let feedback: String
    let error: String?
    let togglePage: () -> Void
    let start: @MainActor () async -> Void
    let stop: @MainActor () async -> Void
    let cancel: @MainActor () async -> Void
    let retry: () -> Void

    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
    }

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                if let appendingTodoTitle {
                    HStack(spacing: 6) {
                        Image(systemName: isRecording ? "waveform.badge.mic" : "plus.bubble.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isRecording ? Color.red : Color.accentColor)
                        Text(isRecording ? "🎙️ 正在继续补充至：\(appendingTodoTitle)" : "🎙️ 按右侧麦克风继续补充至：\(appendingTodoTitle)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .modifier(RecorderGlassModifier())
                    .glassEffectID("appendHint", in: glass)
                    .accessibilityIdentifier("vox.todo.append.banner")
                }

                HStack(spacing: 14) {
                    pageSwitchButton
                        .glassEffectID("switchPage", in: glass)

                    Spacer(minLength: 0)

                    waveform

                    Spacer(minLength: 0)

                    RecorderButton(
                        isRecording: isRecording,
                        isProcessing: isProcessing,
                        start: start,
                        stop: stop,
                        cancel: cancel
                    )
                    .glassEffectID("record", in: glass)
                }

                feedbackRegion
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: 148)
        }
        .background {
            ZStack {
                if reduceTransparency {
                    shape.fill(.thickMaterial)
                } else {
                    shape.fill(AppTheme.surfacePrimary.opacity(0.82))
                }
            }
            .clipShape(shape)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var pageSwitchButton: some View {
        Button(action: togglePage) {
            HStack(spacing: 6) {
                Image(systemName: activePage == .recorder ? "checklist" : "waveform")
                    .font(.body.weight(.semibold))
                if activePage == .recorder && pendingTodoCount > 0 {
                    Text("\(pendingTodoCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, activePage == .recorder && pendingTodoCount > 0 ? 14 : 0)
            .frame(minWidth: 52, minHeight: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(RecorderGlassModifier())
        .accessibilityLabel(activePage == .recorder ? "切换到待办页" : "返回录音页")
        .accessibilityIdentifier("vox.nav.switch.button")
    }

    private var waveform: some View {
        let barIndices = Array(0..<7)
        return HStack(spacing: 4) {
            ForEach(barIndices, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .indigo], startPoint: .bottom, endPoint: .top))
                    .frame(width: 4, height: barHeight(index))
            }
        }
        .frame(height: 28)
        .opacity(isRecording ? 1 : 0.4)
        .animation(reduceMotion ? nil : AppTheme.gestureSpring, value: audioLevel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRecording ? "正在录音" : "准备录音")
        .accessibilityIdentifier("vox.recording.indicator")
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let level = audioLevel.isFinite ? min(1, max(0, audioLevel)) : 0
        let amplitude = isRecording ? (reduceMotion ? 0.5 : CGFloat(level)) : 0.12
        return max(6, amplitude * [0.45, 0.7, 1, 0.6, 0.85, 0.55, 0.75][index] * 28)
    }

    private var feedbackRegion: some View {
        VStack(spacing: 4) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(.primary)
                Button("重试", systemImage: "arrow.clockwise", action: retry)
                    .frame(minHeight: 44).accessibilityIdentifier("vox.capture.retry")
            } else {
                HStack(spacing: 8) {
                    if isProcessing { ProgressView().controlSize(.small) }
                    Text(feedback)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 22)
        .accessibilityIdentifier("r3-feedback")
    }
}

// MARK: - Slide Right Page: Todo Page (v02 Top Hero Focus Stage + v04 Internal Hierarchy + Direct In-Place Manipulation)

private struct IOSTodoSlidePageView: View {
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    let onOpenSettings: () -> Void
    @Namespace private var filterAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
                .padding(.horizontal, AppTheme.Space.lg)
                .padding(.top, AppTheme.Space.md)
                .padding(.bottom, AppTheme.Space.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
                    statusFilterStrip
                    todoPrimaryStage
                }
                .padding(.horizontal, AppTheme.Space.lg)
                .padding(.top, AppTheme.Space.xs)
                .padding(.bottom, AppTheme.Space.section)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("待办清单")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("点击任务置顶聚焦 · 标题与属性展示处直接点按修改")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppTheme.Space.sm)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(RecorderGlassModifier())
            .accessibilityLabel("设置")
            .accessibilityIdentifier("vox.ios.settingsButton")
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
                            if let expanded = viewModel.expandedTodo,
                               filter != .all,
                               expanded.executionState.rawValue != filter.rawValue {
                                viewModel.expandedTodoID = nil
                            }
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

    @ViewBuilder
    private var todoPrimaryStage: some View {
        if viewModel.filteredTodos.isEmpty {
            todoEmptyState
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Space.section)
                .accessibilityIdentifier("vox.session.list")
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
                if let focusedTodo = viewModel.expandedTodo,
                   viewModel.filteredTodos.contains(where: { $0.id == focusedTodo.id }) {
                    IOSTopFocusTodoCard(
                        todo: focusedTodo,
                        historicalTags: viewModel.availableHistoricalTags,
                        voiceAppendedSubtasks: viewModel.voiceAppendedSubtasks(for: focusedTodo.id),
                        onCollapse: {
                            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                viewModel.toggleExpandedTodo(focusedTodo.id)
                            }
                        },
                        onUpdateTitle: { newTitle in
                            viewModel.updateTodoTitle(todoID: focusedTodo.id, title: newTitle)
                        },
                        onCycleStatus: {
                            viewModel.cycleTodoStatus(todoID: focusedTodo.id)
                        },
                        onSelectStatus: { state in
                            viewModel.updateTodoStatus(todoID: focusedTodo.id, state: state)
                        },
                        onCyclePriority: {
                            viewModel.cycleTodoPriority(todoID: focusedTodo.id)
                        },
                        onSelectPriority: { priority in
                            viewModel.updateTodoPriority(todoID: focusedTodo.id, priority: priority)
                        },
                        onToggleTag: { tag in
                            viewModel.toggleTodoTag(todoID: focusedTodo.id, tag: tag)
                        },
                        onAddTag: { newTag in
                            viewModel.addTodoTag(todoID: focusedTodo.id, tag: newTag)
                        },
                        onToggleSubtask: { subtaskID in
                            viewModel.toggleTodoSubtask(todoID: focusedTodo.id, subtaskID: subtaskID)
                        },
                        onUpdateSubtaskTitle: { subtaskID, newTitle in
                            viewModel.updateTodoSubtaskTitle(todoID: focusedTodo.id, subtaskID: subtaskID, title: newTitle)
                        },
                        onAppendSubtask: { subtaskTitle in
                            viewModel.appendSubtask(to: focusedTodo.id, title: subtaskTitle)
                        },
                        onSyncLinear: {
                            viewModel.syncTodoToLinear(focusedTodo.id)
                        },
                        onCopyTodo: {
                            viewModel.copyTodoContent(focusedTodo)
                        }
                    )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                let trayTodos = viewModel.companionTodos
                if !trayTodos.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                        if viewModel.expandedTodo != nil {
                            HStack(spacing: AppTheme.Space.xs) {
                                Text("其余待办")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(trayTodos.count)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text("点按任意条目切换至顶部聚焦")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, AppTheme.Space.xs)
                        }

                        LazyVStack(spacing: AppTheme.Space.md) {
                            ForEach(trayTodos) { todo in
                                IOSCompanionTodoRowCard(
                                    todo: todo,
                                    onToggleDone: { viewModel.toggleTodoDone(todo.id) },
                                    onSelectFocus: {
                                        withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                            viewModel.toggleExpandedTodo(todo.id)
                                        }
                                    }
                                )
                                .accessibilityIdentifier("vox.session.list.item")
                            }
                        }
                    }
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
                    Text("按住右下角麦克风说话，一句话直接生成待办。")
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

// MARK: - v02 Top Focus Stage Card with v04 Internal Hierarchy & Direct In-Place Manipulation

private struct IOSTopFocusTodoCard: View {
    let todo: VoiceTodo
    let historicalTags: [String]
    let voiceAppendedSubtasks: [VoiceTodoSubtask]
    let onCollapse: () -> Void
    let onUpdateTitle: (String) -> Void
    let onCycleStatus: () -> Void
    let onSelectStatus: (TodoExecutionState) -> Void
    let onCyclePriority: () -> Void
    let onSelectPriority: (TodoPriority) -> Void
    let onToggleTag: (String) -> Void
    let onAddTag: (String) -> Void
    let onToggleSubtask: (UUID) -> Void
    let onUpdateSubtaskTitle: (UUID, String) -> Void
    let onAppendSubtask: (String) -> Void
    let onSyncLinear: () -> Void
    let onCopyTodo: () -> Void

    @State private var draftTitle: String = ""
    @State private var isTagPickerExpanded: Bool = (ProcessInfo.processInfo.environment["VOX_DEMO_OPEN_TAG_PICKER"] == "1")
    @State private var newTagText: String = ""
    @State private var newSubtaskText: String = ""
    @FocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var completedSubtaskCount: Int {
        todo.subtasks.filter(\.isCompleted).count
    }

    private var totalSubtaskCount: Int {
        todo.subtasks.count
    }

    private var progressFraction: Double {
        guard totalSubtaskCount > 0 else { return todo.executionState == .done ? 1.0 : 0.0 }
        return Double(completedSubtaskCount) / Double(totalSubtaskCount)
    }

    private var displayTags: [String] {
        if !todo.tags.isEmpty {
            return Array(todo.tags.prefix(3))
        }
        if let projectKey = todo.projectKey, !projectKey.isEmpty {
            return ["#\(projectKey)"]
        }
        return ["#VoxPocket"]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.md) {
            focalTitleAndProgressHeader

            inPlaceMetadataStrip

            if isTagPickerExpanded {
                historicalTagPickerPanel
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            v04SubtaskTreeAndVoiceProvenance

            quietExportFooter
        }
        .padding(AppTheme.Space.lg)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.36), lineWidth: 1.4)
        }
        .onAppear {
            draftTitle = todo.title
        }
        .onChange(of: todo.id) { _, _ in
            draftTitle = todo.title
            newTagText = ""
            newSubtaskText = ""
        }
        .onChange(of: todo.title) { _, updated in
            if !isTitleFocused {
                draftTitle = updated
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused {
                commitTitleIfValid()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.todo.expanded.detail")
    }

    // Layer 1: Primary Focal Header (In-Place Editable Title + Progress Ring & Collapse Button)
    private var focalTitleAndProgressHeader: some View {
        HStack(alignment: .top, spacing: AppTheme.Space.md) {
            TextField("待办标题", text: $draftTitle, axis: .vertical)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit {
                    commitTitleIfValid()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("待办标题（点按直接修改）")
                .accessibilityIdentifier("vox.todo.title.editor")

            HStack(spacing: AppTheme.Space.xs) {
                progressRingBadge

                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.surfaceElevated, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(AppPressableButtonStyle())
                .accessibilityLabel("收起聚焦待办")
                .accessibilityIdentifier("vox.todo.collapse.button")
            }
        }
    }

    private var progressRingBadge: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)

            Text("\(completedSubtaskCount)/\(totalSubtaskCount)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceElevated, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已完成 \(completedSubtaskCount) / 共 \(totalSubtaskCount) 步")
        .accessibilityIdentifier("vox.todo.progress.badge")
    }

    // Layer 2: 5-Element In-Place Manipulation Metadata Strip (Status · Priority · Tags · Time)
    private var inPlaceMetadataStrip: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
            HStack(spacing: AppTheme.Space.xs) {
                Button(action: onCycleStatus) {
                    HStack(spacing: 4) {
                        Image(systemName: statusSymbol)
                            .font(.caption.weight(.bold))
                        Text(statusTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 34)
                    .background(statusColor.opacity(0.14), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .contextMenu {
                    Button("待处理") { onSelectStatus(.inbox) }
                    Button("进行中") { onSelectStatus(.running) }
                    Button("已完成") { onSelectStatus(.done) }
                }
                .accessibilityLabel("状态：\(statusTitle)，点按切换")
                .accessibilityIdentifier("vox.todo.status.pill")

                Button(action: onCyclePriority) {
                    HStack(spacing: 4) {
                        Text(todo.priority.rawValue)
                            .font(.caption.weight(.bold).monospacedDigit())
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(priorityColor(todo.priority))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 34)
                    .background(priorityColor(todo.priority).opacity(0.14), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .contextMenu {
                    ForEach(TodoPriority.allCases, id: \.self) { level in
                        Button(level.rawValue) { onSelectPriority(level) }
                    }
                }
                .accessibilityLabel("优先级：\(todo.priority.rawValue)，点按切换")
                .accessibilityIdentifier("vox.todo.priority.pill")

                Button {
                    withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                        isTagPickerExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isTagPickerExpanded ? "chevron.up.circle.fill" : "tag.fill")
                            .font(.caption2)
                        Text("+ 标签")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 34)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .accessibilityLabel("选择历史标签或添加新标签")
                .accessibilityIdentifier("vox.todo.tags.trigger")

                Spacer(minLength: AppTheme.Space.xs)

                Text("今天 \(Self.timeFormatter.string(from: todo.updatedAt))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Space.xs) {
                    ForEach(displayTags, id: \.self) { tag in
                        Button {
                            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                isTagPickerExpanded = true
                            }
                            onToggleTag(tag)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 32)
                            .background(AppTheme.surfaceElevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("标签 \(tag)，点按移除或展开候选")
                        .accessibilityIdentifier("vox.todo.tag.active.\(tag)")
                    }
                }
            }
        }
    }

    // Historical Tag Picker + Direct Add New Tag Panel
    private var historicalTagPickerPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            HStack {
                Text("曾用标签（点按即选 / 取消，最多 3 个）")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(todo.tags.count)/3")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Space.xs) {
                    ForEach(historicalTags, id: \.self) { candidate in
                        let isSelected = todo.tags.contains(candidate)
                        Button {
                            onToggleTag(candidate)
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                }
                                Text(candidate)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                            }
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minHeight: 34)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.16) : AppTheme.surfacePrimary,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("vox.todo.tag.option.\(candidate)")
                    }
                }
            }

            HStack(spacing: AppTheme.Space.sm) {
                TextField("添加新标签（如 Design）", text: $newTagText)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.surfacePrimary, in: Capsule())
                    .submitLabel(.done)
                    .onSubmit {
                        submitNewTag()
                    }
                    .accessibilityIdentifier("vox.todo.tag.input")

                Button(action: submitNewTag) {
                    Text("添加")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 34)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("vox.todo.tag.add.button")
            }
        }
        .padding(AppTheme.Space.md)
        .background(
            AppTheme.surfaceElevated,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.todo.tags.picker")
    }

    // Layer 3: v04 Vertical Accent Spine Subtask Tree + Voice Append Provenance Rail
    private var v04SubtaskTreeAndVoiceProvenance: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.md) {
            HStack {
                Label("执行步骤树", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("点按文字原地修改 · 右下麦克风语音直补")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                ForEach(todo.subtasks) { subtask in
                    IOSInPlaceSubtaskBranchRow(
                        subtask: subtask,
                        onToggle: { onToggleSubtask(subtask.id) },
                        onCommitTitle: { updatedTitle in
                            onUpdateSubtaskTitle(subtask.id, updatedTitle)
                        }
                    )
                }

                HStack(alignment: .center, spacing: AppTheme.Space.sm) {
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: 2, height: 34)
                        Capsule()
                            .fill(Color.accentColor.opacity(0.35))
                            .frame(width: 10, height: 2)
                    }
                    .padding(.leading, 8)
                    .accessibilityHidden(true)

                    Image(systemName: "plus.circle.dashed")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)

                    TextField("添加新子步骤，回车保存…", text: $newSubtaskText)
                        .font(.subheadline)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                        .onSubmit {
                            submitNewSubtask()
                        }
                        .accessibilityIdentifier("vox.todo.subtask.add.input")

                    if !newSubtaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: submitNewSubtask) {
                            Text("添加")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("vox.todo.subtask.add.button")
                    }
                }
                .frame(minHeight: 40)
            }

            if !voiceAppendedSubtasks.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                    ForEach(voiceAppendedSubtasks) { item in
                        HStack(spacing: AppTheme.Space.xs) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text("\(Self.timeFormatter.string(from: item.createdAt)) · 语音追记 → 新增子任务：\(item.title)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppTheme.Space.sm)
                        .padding(.vertical, 6)
                        .background(
                            AppTheme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                        )
                        .accessibilityIdentifier("vox.todo.voice.provenance")
                    }
                }
            }
        }
    }

    // Layer 4: Quiet Footer Strip
    private var quietExportFooter: some View {
        HStack(spacing: AppTheme.Space.sm) {
            Button(action: onSyncLinear) {
                Label(todo.externalSync?.externalID ?? "Linear", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .background(AppTheme.surfaceElevated, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vox.todo.action.linear")

            Button(action: onCopyTodo) {
                Label("复制", systemImage: "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .background(AppTheme.surfaceElevated, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vox.todo.action.copy")

            Spacer(minLength: AppTheme.Space.xs)

            Text("按住右下麦克风继续追补")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func commitTitleIfValid() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draftTitle = todo.title
        } else if trimmed != todo.title {
            onUpdateTitle(trimmed)
        }
    }

    private func submitNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddTag(trimmed)
        newTagText = ""
    }

    private func submitNewSubtask() {
        let trimmed = newSubtaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAppendSubtask(trimmed)
        newSubtaskText = ""
    }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .p0: .red
        case .p1: .orange
        case .p2: .blue
        }
    }

    private var statusTitle: String {
        switch todo.executionState {
        case .inbox: "待处理"
        case .running: "进行中"
        case .done: "已完成"
        case .failed: "需重试"
        }
    }

    private var statusSymbol: String {
        switch todo.executionState {
        case .inbox: "circle"
        case .running: "timelapse"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch todo.executionState {
        case .inbox: .blue
        case .running: .orange
        case .done: .green
        case .failed: .red
        }
    }
}

// MARK: - v04 Vertical Spine Subtask Row with Direct In-Place Text Editing

private struct IOSInPlaceSubtaskBranchRow: View {
    let subtask: VoiceTodoSubtask
    let onToggle: () -> Void
    let onCommitTitle: (String) -> Void

    @State private var draftSubtaskTitle: String = ""
    @FocusState private var isSubtaskFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.xs) {
            HStack(spacing: 0) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 2, height: 44)
                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 10, height: 2)
            }
            .padding(.leading, 8)
            .accessibilityHidden(true)

            Button(action: onToggle) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "已完成：\(subtask.title)" : "未完成：\(subtask.title)")
            .accessibilityIdentifier("vox.todo.subtask.\(subtask.id.uuidString)")

            TextField("子步骤内容", text: $draftSubtaskTitle, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                .strikethrough(subtask.isCompleted, color: .secondary)
                .focused($isSubtaskFocused)
                .submitLabel(.done)
                .onSubmit {
                    commitSubtaskIfValid()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .accessibilityLabel("子步骤内容：\(subtask.title)")
                .accessibilityIdentifier("vox.todo.subtask.editor.\(subtask.id.uuidString)")
        }
        .onAppear {
            draftSubtaskTitle = subtask.title
        }
        .onChange(of: subtask.title) { _, updated in
            if !isSubtaskFocused {
                draftSubtaskTitle = updated
            }
        }
        .onChange(of: isSubtaskFocused) { _, focused in
            if !focused {
                commitSubtaskIfValid()
            }
        }
    }

    private func commitSubtaskIfValid() {
        let trimmed = draftSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draftSubtaskTitle = subtask.title
        } else if trimmed != subtask.title {
            onCommitTitle(trimmed)
        }
    }
}

// MARK: - Companion Secondary Tray Row Card (5 Core Elements)

private struct IOSCompanionTodoRowCard: View {
    let todo: VoiceTodo
    let onToggleDone: () -> Void
    let onSelectFocus: () -> Void

    private var isDone: Bool { todo.executionState == .done }

    private var displayTags: [String] {
        if !todo.tags.isEmpty {
            return Array(todo.tags.prefix(3))
        }
        if let projectKey = todo.projectKey, !projectKey.isEmpty {
            return ["#\(projectKey)"]
        }
        return ["#VoxPocket"]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Space.sm) {
            Button(action: onToggleDone) {
                Image(systemName: statusSymbol)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppPressableButtonStyle())
            .accessibilityLabel(isDone ? "已完成" : "待处理")
            .accessibilityIdentifier("vox.todo.status.\(todo.id.uuidString)")

            Button(action: onSelectFocus) {
                VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Space.xs) {
                        priorityBadge(todo.priority)

                        Text(todo.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isDone ? .secondary : .primary)
                            .strikethrough(isDone, color: .secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: AppTheme.Space.xs) {
                        ForEach(displayTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AppTheme.Space.sm)
                                .padding(.vertical, 3)
                                .background(AppTheme.surfaceElevated, in: Capsule())
                        }

                        if !todo.subtasks.isEmpty {
                            let doneCount = todo.subtasks.filter(\.isCompleted).count
                            Text("\(doneCount)/\(todo.subtasks.count)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: AppTheme.Space.xs)

                        Text("今天 \(Self.timeFormatter.string(from: todo.updatedAt))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppTheme.Space.md)
                .padding(.trailing, AppTheme.Space.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vox.todo.row.\(todo.id.uuidString)")
        }
        .padding(.leading, AppTheme.Space.xs)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }

    private func priorityBadge(_ priority: TodoPriority) -> some View {
        Text(priority.rawValue)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(priorityColor(priority))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.14), in: Capsule())
    }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .p0: .red
        case .p1: .orange
        case .p2: .blue
        }
    }

    private var statusSymbol: String {
        switch todo.executionState {
        case .inbox: "circle"
        case .running: "timelapse"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch todo.executionState {
        case .inbox: .secondary
        case .running: .orange
        case .done: .green
        case .failed: .red
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
                                    Text(mode == .todo ? "自动提炼标题并加入待办清单" : "润色为干净文字并复制，方便直接粘贴")
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
                    Text("在默认录音页启动快速录音时，将默认按此去向处理。")
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
#endif
