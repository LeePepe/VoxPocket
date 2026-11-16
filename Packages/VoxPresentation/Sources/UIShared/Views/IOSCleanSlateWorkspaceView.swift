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
            if env["VOX_DEMO_EXPAND_FIRST_TODO"] == "1", let firstID = viewModel.todos.first?.id {
                viewModel.switchToPage(.todo)
                viewModel.expandedTodoID = firstID
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
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
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

// MARK: - Slide Right Page: Todo Page with 5 Core Elements & In-Place Expandable Subtasks

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
                Text("点按任务展开子步骤 · 展开时按右下麦克风继续追补")
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
            LazyVStack(spacing: AppTheme.Space.md) {
                ForEach(viewModel.filteredTodos) { todo in
                    IOSExpandableTodoCard(
                        todo: todo,
                        isExpanded: viewModel.expandedTodoID == todo.id,
                        onToggleDone: { viewModel.toggleTodoDone(todo.id) },
                        onToggleExpand: {
                            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                viewModel.toggleExpandedTodo(todo.id)
                            }
                        },
                        onToggleSubtask: { subtaskID in
                            viewModel.toggleTodoSubtask(todoID: todo.id, subtaskID: subtaskID)
                        },
                        onSelectPriority: { priority in
                            viewModel.updateTodoPriority(todoID: todo.id, priority: priority)
                        },
                        onSyncLinear: {
                            viewModel.syncTodoToLinear(todo.id)
                        },
                        onCopyTodo: {
                            viewModel.copyTodoContent(todo)
                        }
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

// MARK: - 5-Element Todo Card with In-Place Spring Expansion

private struct IOSExpandableTodoCard: View {
    let todo: VoiceTodo
    let isExpanded: Bool
    let onToggleDone: () -> Void
    let onToggleExpand: () -> Void
    let onToggleSubtask: (UUID) -> Void
    let onSelectPriority: (TodoPriority) -> Void
    let onSyncLinear: () -> Void
    let onCopyTodo: () -> Void

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
        VStack(alignment: .leading, spacing: 0) {
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

                Button(action: onToggleExpand) {
                    VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Space.xs) {
                            priorityBadge(todo.priority)

                            Text(todo.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(isDone ? .secondary : .primary)
                                .strikethrough(isDone, color: .secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
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

            if isExpanded {
                expandedDetailSection
                    .padding(.horizontal, AppTheme.Space.lg)
                    .padding(.bottom, AppTheme.Space.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .overlay {
            if isExpanded {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 1.2)
            }
        }
    }

    private var expandedDetailSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.md) {
            Divider()

            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                HStack {
                    Text("子步骤清单")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("按住右下麦克风可直接追加")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }

                if todo.subtasks.isEmpty {
                    Text("暂无拆解子步骤，按住右下角录音键可直接语音补充。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, AppTheme.Space.xs)
                } else {
                    ForEach(todo.subtasks) { subtask in
                        Button {
                            onToggleSubtask(subtask.id)
                        } label: {
                            HStack(spacing: AppTheme.Space.sm) {
                                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                                Text(subtask.title)
                                    .font(.subheadline)
                                    .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                                    .strikethrough(subtask.isCompleted, color: .secondary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("vox.todo.subtask.\(subtask.id.uuidString)")
                    }
                }
            }

            HStack(spacing: AppTheme.Space.sm) {
                ForEach(TodoPriority.allCases, id: \.self) { level in
                    let selected = todo.priority == level
                    Button {
                        onSelectPriority(level)
                    } label: {
                        Text(level.rawValue)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(minHeight: 32)
                            .background(
                                selected ? priorityColor(level).opacity(0.18) : AppTheme.surfaceElevated,
                                in: Capsule()
                            )
                            .foregroundStyle(selected ? priorityColor(level) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("vox.todo.priority.\(level.rawValue)")
                }

                Spacer(minLength: AppTheme.Space.xs)

                Button(action: onSyncLinear) {
                    Label(todo.externalSync?.externalID ?? "Linear", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 32)
                        .background(AppTheme.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vox.todo.action.linear")

                Button(action: onCopyTodo) {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 32)
                        .background(AppTheme.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vox.todo.action.copy")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.todo.expanded.detail")
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
