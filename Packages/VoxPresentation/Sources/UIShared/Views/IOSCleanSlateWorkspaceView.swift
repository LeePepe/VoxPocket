import SwiftUI
import CoreModels
import Preferences

#if os(iOS)
@MainActor
public struct IOSCleanSlateWorkspaceView: View {
    @ObservedObject private var viewModel: VoxWorkspaceViewModel
    private let localModelLoadingStatus: LocalModelLoadingStatus?
    @State private var isShowingSettingsSheet = false
    @State private var interactiveDragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: VoxWorkspaceViewModel, localModelLoadingStatus: LocalModelLoadingStatus? = nil) {
        self.viewModel = viewModel
        self.localModelLoadingStatus = localModelLoadingStatus
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let pageWidth = max(1, geometry.size.width)

                HStack(spacing: 0) {
                    recorderStagePage
                        .frame(width: pageWidth, height: geometry.size.height)
                        .allowsHitTesting(viewModel.activePage == .recorder && interactiveDragOffset == 0)
                        .accessibilityHidden(viewModel.activePage != .recorder)

                    todoStagePage
                        .frame(width: pageWidth, height: geometry.size.height)
                        .allowsHitTesting(viewModel.activePage == .todo && interactiveDragOffset == 0)
                        .accessibilityHidden(viewModel.activePage != .todo)
                }
                .frame(width: pageWidth * 2, height: geometry.size.height, alignment: .leading)
                .offset(x: (viewModel.activePage == .recorder ? 0 : -pageWidth) + interactiveDragOffset)
                .frame(width: pageWidth, height: geometry.size.height, alignment: .leading)
                .clipped()
                .simultaneousGesture(horizontalSlideGesture(pageWidth: pageWidth))
            }
            .background { RecorderBackdrop(status: viewModel.recorderStatus, audioLevel: viewModel.audioLevel) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                IOSDualButtonSlideDock(
                    activePage: viewModel.activePage,
                    isRecording: viewModel.isRecordingActive,
                    isProcessing: viewModel.isProcessingCapture,
                    togglePage: {
                        withAnimation(reduceMotion ? nil : AppTheme.gestureSpring) {
                            interactiveDragOffset = 0
                            viewModel.toggleActivePage()
                        }
                    },
                    start: { await viewModel.startCaptureAndWait() },
                    stop: { await viewModel.completeCapture(deviceSource: .iPhone) },
                    cancel: { viewModel.cancelCapture() }
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
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                interactiveDragOffset = clampedHorizontalDrag(value.translation.width, pageWidth: pageWidth)
            }
            .onEnded { value in
                let threshold = max(56, pageWidth * 0.18)
                let predicted = value.predictedEndTranslation.width
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) || interactiveDragOffset != 0
                withAnimation(reduceMotion ? nil : AppTheme.gestureSpring) {
                    if isHorizontal {
                        if viewModel.activePage == .recorder && (value.translation.width < -threshold || predicted < -threshold * 1.4) {
                            viewModel.switchToPage(.todo)
                        } else if viewModel.activePage == .todo && (value.translation.width > threshold || predicted > threshold * 1.4) {
                            viewModel.switchToPage(.recorder)
                        }
                    }
                    interactiveDragOffset = 0
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
}

// MARK: - Ultra-Pure 2-Button Bottom Bar (Bottom-Leading Switch + Bottom-Trailing Persistent Record)

private struct IOSDualButtonSlideDock: View {
    let activePage: WorkspacePage
    let isRecording: Bool
    let isProcessing: Bool
    let togglePage: () -> Void
    let start: @MainActor () async -> Void
    let stop: @MainActor () async -> Void
    let cancel: @MainActor () async -> Void

    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                pageSwitchButton
                    .glassEffectID("switchPage", in: glass)
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
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
            .padding(.top, 4)
        }
    }

    private var pageSwitchButton: some View {
        Button(action: togglePage) {
            Image(systemName: activePage == .recorder ? "checklist" : "waveform")
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(RecorderGlassModifier())
        .accessibilityLabel(activePage == .recorder ? "切换到待办页" : "返回录音页")
        .accessibilityIdentifier("vox.nav.switch.button")
    }
}

// MARK: - Slide Right Page: Todo Page (In-Place Card Expansion + v04 Clean 3-Tier Hierarchy + Direct In-Place Manipulation)

private struct IOSTodoSlidePageView: View {
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    let onOpenSettings: () -> Void
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
            Text("待办清单")
                .font(.title2.bold())
                .foregroundStyle(.primary)

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
                    filterPillButton(for: filter)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedTodoFilter)
    }

    private func filterPillButton(for filter: TodoStatusFilter) -> some View {
        let isSelected = viewModel.selectedTodoFilter == filter
        let count = countForFilter(filter)
        return Button(action: { selectFilter(filter) }) {
            HStack(spacing: AppTheme.Space.xs) {
                Text(filter.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                Text(String(count))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, AppTheme.Space.md)
            .padding(.vertical, AppTheme.Space.sm)
            .frame(minHeight: 44)
            .background {
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : AppTheme.surfaceCard)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(AppPressableButtonStyle())
        .accessibilityIdentifier("vox.ios.filter." + filter.rawValue)
    }

    private func selectFilter(_ filter: TodoStatusFilter) {
        withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
            viewModel.selectedTodoFilter = filter
            if let expanded = viewModel.expandedTodo,
               filter != .all,
               expanded.executionState.rawValue != filter.rawValue {
                viewModel.expandedTodoID = nil
            }
        }
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
                    IOSTodoExpandableCard(
                        todo: todo,
                        isExpanded: viewModel.expandedTodoID == todo.id,
                        historicalTags: viewModel.availableHistoricalTags,
                        onToggleDone: { viewModel.toggleTodoDone(todo.id) },
                        onToggleExpand: {
                            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                viewModel.toggleExpandedTodo(todo.id)
                            }
                        },
                        onUpdateTitle: { newTitle in
                            viewModel.updateTodoTitle(todoID: todo.id, title: newTitle)
                        },
                        onCycleStatus: {
                            viewModel.cycleTodoStatus(todoID: todo.id)
                        },
                        onSelectStatus: { state in
                            viewModel.updateTodoStatus(todoID: todo.id, state: state)
                        },
                        onCyclePriority: {
                            viewModel.cycleTodoPriority(todoID: todo.id)
                        },
                        onSelectPriority: { priority in
                            viewModel.updateTodoPriority(todoID: todo.id, priority: priority)
                        },
                        onToggleTag: { tag in
                            viewModel.toggleTodoTag(todoID: todo.id, tag: tag)
                        },
                        onAddTag: { newTag in
                            viewModel.addTodoTag(todoID: todo.id, tag: newTag)
                        },
                        onToggleSubtask: { subtaskID in
                            viewModel.toggleTodoSubtask(todoID: todo.id, subtaskID: subtaskID)
                        },
                        onUpdateSubtaskTitle: { subtaskID, newTitle in
                            viewModel.updateTodoSubtaskTitle(todoID: todo.id, subtaskID: subtaskID, title: newTitle)
                        },
                        onAppendSubtask: { subtaskTitle in
                            viewModel.appendSubtask(to: todo.id, title: subtaskTitle)
                        },
                        onSyncLinear: {
                            viewModel.syncTodoToLinear(todo.id)
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
                    Button("清除搜索后重试", action: viewModel.clearSearchPreservingFilters)
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

// MARK: - In-Place Expandable Todo Card (Collapsed Row <-> Unfolded v04 3-Tier Detail)

private struct IOSTodoExpandableCard: View {
    let todo: VoiceTodo
    let isExpanded: Bool
    let historicalTags: [String]
    let onToggleDone: () -> Void
    let onToggleExpand: () -> Void
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

    @Namespace private var cardNamespace
    @State private var draftTitle: String = ""
    @State private var isTagPickerExpanded: Bool = (ProcessInfo.processInfo.environment["VOX_DEMO_OPEN_TAG_PICKER"] == "1")
    @State private var newTagText: String = ""
    @State private var newSubtaskText: String = ""
    @FocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDone: Bool { todo.executionState == .done }

    private var completedSubtaskCount: Int {
        todo.subtasks.filter(\.isCompleted).count
    }

    private var totalSubtaskCount: Int {
        todo.subtasks.count
    }

    private var progressFraction: Double {
        guard totalSubtaskCount > 0 else { return isDone ? 1.0 : 0.0 }
        return Double(completedSubtaskCount) / Double(totalSubtaskCount)
    }

    private var displayTags: [String] {
        if !todo.tags.isEmpty {
            return Array(todo.tags.prefix(3))
        }
        if let projectKey = todo.projectKey, !projectKey.isEmpty {
            return ["#" + projectKey]
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
            if isExpanded {
                expandedThreeTierContent
                    .padding(AppTheme.Space.lg)
                    .transition(.opacity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("vox.todo.expanded.detail")
            } else {
                collapsedRowContent
            }
        }
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .clipped()
        .overlay {
            if isExpanded {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 1.2)
            }
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
    }

    // Collapsed State Row
    private var collapsedRowContent: some View {
        HStack(alignment: .top, spacing: AppTheme.Space.sm) {
            Button(action: onToggleDone) {
                Image(systemName: statusSymbol)
                    .font(.title3)
                    .foregroundStyle(collapsedStatusColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppPressableButtonStyle())
            .matchedGeometryEffect(id: "todo-status-\(todo.id)", in: cardNamespace)
            .accessibilityLabel(isDone ? "已完成" : "待处理")
            .accessibilityIdentifier("vox.todo.status." + todo.id.uuidString)

            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Space.xs) {
                    priorityBadge(todo.priority)
                        .matchedGeometryEffect(id: "todo-priority-\(todo.id)", in: cardNamespace)

                    Text(todo.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .matchedGeometryEffect(id: "todo-title-\(todo.id)", in: cardNamespace)
                }

                HStack(spacing: AppTheme.Space.xs) {
                    ForEach(displayTags, id: \.self) { tag in
                        collapsedTagChip(tag)
                            .matchedGeometryEffect(id: "todo-tag-\(todo.id)-\(tag)", in: cardNamespace)
                    }

                    if !todo.subtasks.isEmpty {
                        Text(String(completedSubtaskCount) + "/" + String(totalSubtaskCount))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: AppTheme.Space.xs)

                    Text("今天 " + Self.timeFormatter.string(from: todo.updatedAt))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppTheme.Space.md)
            .padding(.trailing, AppTheme.Space.md)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleExpand)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("vox.todo.row." + todo.id.uuidString)
        }
        .padding(.leading, AppTheme.Space.xs)
    }

    // Expanded v04 3-Tier Content
    private var expandedThreeTierContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.md) {
            tierOneFocalHeader

            tierTwoCompactMetadataAndTagStrip

            Divider()

            tierThreeCleanSubtaskList
        }
    }

    // Tier 1: Primary Focal Header (In-Place Editable Title + Progress & Collapse Chevron)
    private var tierOneFocalHeader: some View {
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
                .matchedGeometryEffect(id: "todo-title-\(todo.id)", in: cardNamespace)
                .accessibilityLabel("待办标题")
                .accessibilityIdentifier("vox.todo.title.editor")

            HStack(spacing: AppTheme.Space.xs) {
                progressRingBadge

                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(AppTheme.surfaceElevated, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppPressableButtonStyle())
                .accessibilityLabel("收起待办详情")
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

            Text(String(completedSubtaskCount) + "/" + String(totalSubtaskCount))
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

    // Tier 2: Two-Row Metadata & Tag Layout (Row 2A: Round Status/Priority + Linear; Row 2B: Dedicated Squared-Off Tag Row)
    private var tierTwoCompactMetadataAndTagStrip: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            HStack(spacing: AppTheme.Space.sm) {
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
                    .frame(minHeight: 32)
                    .background(statusColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .matchedGeometryEffect(id: "todo-status-\(todo.id)", in: cardNamespace)
                .contextMenu {
                    Button("待处理") { onSelectStatus(.inbox) }
                    Button("进行中") { onSelectStatus(.running) }
                    Button("已完成") { onSelectStatus(.done) }
                }
                .accessibilityLabel("状态：" + statusTitle)
                .accessibilityIdentifier("vox.todo.status.pill")

                Button(action: onCyclePriority) {
                    Text(todo.priority.rawValue)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(priorityColor(todo.priority))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 32)
                        .background(priorityColor(todo.priority).opacity(0.15), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .matchedGeometryEffect(id: "todo-priority-\(todo.id)", in: cardNamespace)
                .contextMenu {
                    ForEach(TodoPriority.allCases, id: \.self) { level in
                        Button(level.rawValue) { onSelectPriority(level) }
                    }
                }
                .accessibilityLabel("优先级：" + todo.priority.rawValue)
                .accessibilityIdentifier("vox.todo.priority.pill")

                Spacer(minLength: AppTheme.Space.xs)

                Button(action: onSyncLinear) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.circle")
                            .font(.caption.weight(.bold))
                        Text(todo.externalSync?.externalID ?? "Linear")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .accessibilityLabel("同步到 Linear")
                .accessibilityIdentifier("vox.todo.action.linear")
            }

            IOSTodoWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(displayTags, id: \.self) { tag in
                    activeTagPillButton(tag)
                        .matchedGeometryEffect(id: "todo-tag-\(todo.id)-\(tag)", in: cardNamespace)
                }

                Button(action: toggleTagPicker) {
                    Image(systemName: isTagPickerExpanded ? "chevron.up" : "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(
                            AppTheme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.8)
                        }
                }
                .buttonStyle(AppPressableButtonStyle())
                .accessibilityLabel("添加或选择标签")
                .accessibilityIdentifier("vox.todo.tags.trigger")
                .popover(isPresented: $isTagPickerExpanded, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                    historicalTagPickerPanel
                        .frame(minWidth: 260, maxWidth: 310)
                        .padding(AppTheme.Space.md)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    private func toggleTagPicker() {
        withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
            isTagPickerExpanded.toggle()
        }
    }

    private func collapsedTagChip(_ tag: String) -> some View {
        Text(tag)
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                AppTheme.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.8)
            }
    }

    private func activeTagPillButton(_ tag: String) -> some View {
        Button(action: {
            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                isTagPickerExpanded = true
            }
            onToggleTag(tag)
        }) {
            Text(tag)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minHeight: 28)
                .background(
                    AppTheme.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("标签 " + tag)
        .accessibilityIdentifier("vox.todo.tag.active." + tag)
    }

    // Historical Tag Picker + Direct Add New Tag Panel
    private var historicalTagPickerPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            IOSTodoWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(historicalTags, id: \.self) { candidate in
                    historicalTagCandidateButton(candidate)
                }
            }

            HStack(spacing: AppTheme.Space.sm) {
                TextField("新标签", text: $newTagText)
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
        .padding(AppTheme.Space.sm)
        .background(
            AppTheme.surfaceElevated,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.todo.tags.picker")
    }

    private func historicalTagCandidateButton(_ candidate: String) -> some View {
        let isSelected = todo.tags.contains(candidate)
        return Button(action: { onToggleTag(candidate) }) {
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
        .accessibilityIdentifier("vox.todo.tag.option." + candidate)
    }

    // Tier 3: Subtask List with Clean Left Vertical Line
    private var tierThreeCleanSubtaskList: some View {
        HStack(alignment: .top, spacing: AppTheme.Space.sm) {
            Capsule()
                .fill(Color.accentColor.opacity(0.28))
                .padding(.vertical, 6)
                .frame(width: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(todo.subtasks) { subtask in
                    IOSInPlaceSubtaskBranchRow(
                        subtask: subtask,
                        onToggle: { onToggleSubtask(subtask.id) },
                        onCommitTitle: { updatedTitle in
                            onUpdateSubtaskTitle(subtask.id, updatedTitle)
                        }
                    )
                }

                HStack(alignment: .center, spacing: AppTheme.Space.xs) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 40)

                    TextField("添加子步骤…", text: $newSubtaskText)
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
        }
    }

    private func priorityBadge(_ priority: TodoPriority) -> some View {
        Text(priority.rawValue)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(priorityColor(priority))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.15), in: Capsule())
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

    private var collapsedStatusColor: Color {
        switch todo.executionState {
        case .inbox: .secondary
        case .running: .orange
        case .done: .green
        case .failed: .red
        }
    }
}

// MARK: - Subtask Row with Direct In-Place Text Editing

private struct IOSInPlaceSubtaskBranchRow: View {
    let subtask: VoiceTodoSubtask
    let onToggle: () -> Void
    let onCommitTitle: (String) -> Void

    @State private var draftSubtaskTitle: String = ""
    @FocusState private var isSubtaskFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.xs) {
            Button(action: onToggle) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((subtask.isCompleted ? "已完成：" : "未完成：") + subtask.title)
            .accessibilityIdentifier("vox.todo.subtask." + subtask.id.uuidString)

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
                .accessibilityLabel("子步骤内容：" + subtask.title)
                .accessibilityIdentifier("vox.todo.subtask.editor." + subtask.id.uuidString)
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

private struct IOSTodoWrappingFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            totalWidth = max(totalWidth, currentX + size.width)
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: proposal.width ?? totalWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
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
                        Button(action: { viewModel.updatePreferredCaptureMode(mode) }) {
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
                        .accessibilityIdentifier("vox.ios.settings.destination." + mode.rawValue)
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
