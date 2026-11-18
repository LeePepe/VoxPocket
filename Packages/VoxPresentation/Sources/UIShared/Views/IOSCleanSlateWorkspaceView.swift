import SwiftUI
import CoreModels
import Preferences
import UseCases

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
            .background {
                RecorderBackdrop(
                    status: viewModel.activePage == .todo ? .idle : viewModel.recorderStatus,
                    audioLevel: viewModel.activePage == .todo ? 0 : viewModel.audioLevel
                )
            }
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
            .iosWorkspaceNavigationBarHidden()
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
                let targetID = viewModel.todos.first(where: { $0.title.contains("液态玻璃") || $0.title.contains("整理下周设计评审") })?.id ?? viewModel.todos.first?.id
                viewModel.expandedTodoID = targetID
            }
            if env["VOX_DEMO_OPEN_TAG_PICKER"] == "1" {
                viewModel.switchToPage(.todo)
                let targetID = viewModel.todos.first(where: { $0.title.contains("液态玻璃") || $0.title.contains("整理下周设计评审") })?.id ?? viewModel.todos.first?.id
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
            countForFilter: countForFilter,
            onSelectFilter: selectFilter,
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

// MARK: - Ultra-Pure 2-Button Bottom Bar (Bottom-Leading Switch + Bottom-Trailing Persistent Record, Zero Upward Popup)

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
        GlassEffectContainer(spacing: 10) {
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

// MARK: - Slide Right Page: Todo Page (Top-Header One-Tap Liquid Glass Pill Rail + #Tag/P0 Quick Strip + In-Place Card Expansion)

private struct IOSTodoSlidePageView: View {
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    let countForFilter: (TodoStatusFilter) -> Int
    let onSelectFilter: (TodoStatusFilter) -> Void
    let onOpenSettings: () -> Void
    @Namespace private var filterGlass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
                .padding(.horizontal, AppTheme.Space.lg)
                .padding(.top, AppTheme.Space.md)
                .padding(.bottom, AppTheme.Space.xs)

            topHeaderLiquidGlassFilterRail
                .padding(.horizontal, AppTheme.Space.lg)
                .padding(.bottom, AppTheme.Space.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
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

            if viewModel.selectedTodoFilter == .done && viewModel.doneCount > 0 {
                Button("清除已完成", action: viewModel.clearCompletedTodos)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("vox.todo.clearCompleted.button")
            }

            Button(action: {
                withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                    if viewModel.hasActiveTodoFilters {
                        viewModel.resetAllTodoFilters()
                    } else {
                        viewModel.selectedTodoFilter = .inbox
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.hasActiveTodoFilters ? "arrow.counterclockwise" : "line.3.horizontal.decrease")
                        .font(.caption2.weight(.bold))
                    Text(viewModel.hasActiveTodoFilters ? "重置" : viewModel.selectedTodoFilter.title)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(viewModel.hasActiveTodoFilters ? Color.accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (viewModel.hasActiveTodoFilters ? Color.accentColor : Color.primary).opacity(0.12),
                    in: Capsule()
                )
            }
            .buttonStyle(AppPressableButtonStyle())
            .accessibilityLabel(viewModel.hasActiveTodoFilters ? "重置全部筛选" : "筛选待办：\(viewModel.selectedTodoFilter.title)")
            .accessibilityIdentifier("vox.ios.filter.trigger")

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

    private var topHeaderLiquidGlassFilterRail: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                ForEach(TodoStatusFilter.primaryFilters, id: \.self) { filter in
                    let isSelected = viewModel.selectedTodoFilter == filter
                    let count = countForFilter(filter)
                    let tint = statusFilterTint(for: filter)

                    Button(action: { onSelectFilter(filter) }) {
                        HStack(spacing: 4) {
                            if filter != .all {
                                Circle()
                                    .fill(isSelected ? Color.white : tint)
                                    .frame(width: 6, height: 6)
                            }
                            Text(filter.compactTitle)
                                .font(.caption.weight(isSelected ? .bold : .semibold))
                            Text(String(count))
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .contentTransition(.numericText())
                                .opacity(isSelected ? 0.94 : 0.72)
                        }
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(tint.opacity(reduceTransparency ? 0.92 : 0.85))
                                    .matchedGeometryEffect(id: "iosStatusFilterPill", in: filterGlass)
                            } else {
                                Capsule()
                                    .fill(AppTheme.surfaceCard.opacity(0.80))
                            }
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    isSelected ? tint.opacity(0.45) : Color.primary.opacity(0.08),
                                    lineWidth: 0.8
                                )
                        }
                    }
                    .buttonStyle(AppPressableButtonStyle())
                    .accessibilityIdentifier("vox.ios.filter." + filter.rawValue)
                }
            }
            .padding(4)
            .modifier(RecorderGlassModifier())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let isP0Selected = viewModel.selectedPriorityFilter == .p0
                    Button(action: {
                        withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                            viewModel.togglePriorityFilter(.p0)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.caption2.weight(.bold))
                            Text("P0")
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                        .foregroundStyle(isP0Selected ? .white : Color.red)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            isP0Selected ? Color.red : Color.red.opacity(0.14),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(AppPressableButtonStyle())
                    .accessibilityIdentifier("vox.ios.filter.priority.p0")

                    ForEach(viewModel.availableHistoricalTags.prefix(6), id: \.self) { tag in
                        let isTagSelected = viewModel.selectedTagFilter == tag
                        Button(action: {
                            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                viewModel.toggleTagFilter(tag)
                            }
                        }) {
                            Text(tag)
                                .font(.caption.weight(isTagSelected ? .bold : .medium).monospacedDigit())
                                .foregroundStyle(isTagSelected ? .white : .secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    isTagSelected ? Color.accentColor : AppTheme.surfaceCard.opacity(0.85),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Color.primary.opacity(isTagSelected ? 0 : 0.08), lineWidth: 0.7)
                                }
                        }
                        .buttonStyle(AppPressableButtonStyle())
                        .accessibilityIdentifier("vox.ios.filter.tag." + tag.replacingOccurrences(of: "#", with: ""))
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedTodoFilter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.ios.filter.bar")
    }

    private func statusFilterTint(for filter: TodoStatusFilter) -> Color {
        switch filter {
        case .all: Color.accentColor
        case .inbox: Color.blue
        case .running: Color.orange
        case .done: Color.green
        case .failed: Color.red
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
            LazyVStack(spacing: AppTheme.Space.sm) {
                ForEach(viewModel.filteredTodos) { todo in
                    IOSTodoExpandableCard(
                        todo: todo,
                        isExpanded: viewModel.expandedTodoID == todo.id,
                        aiOrder: viewModel.aiOrder(for: todo.id),
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
                        onUpdateDescription: { newDescription in
                            viewModel.updateTodoDescription(todoID: todo.id, description: newDescription)
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
                        onCopyTodo: { viewModel.copyTodoContent(todo) },
                        onDeleteTodo: { viewModel.deleteTodo(todo.id) },
                        onDeleteSubtask: { subtaskID in viewModel.deleteTodoSubtask(todoID: todo.id, subtaskID: subtaskID) },
                        onUpdateSubtaskTitle: { subtaskID, newTitle in
                            viewModel.updateTodoSubtaskTitle(todoID: todo.id, subtaskID: subtaskID, title: newTitle)
                        },
                        onAppendSubtask: { subtaskTitle in
                            viewModel.appendSubtask(to: todo.id, title: subtaskTitle)
                        },
                        onDispatchAI: {
                            viewModel.dispatchTodoToICloudAI(todo.id)
                        },
                        onShiftReminderMinutes: { deltaMinutes in
                            viewModel.shiftTodoReminderByMinutes(todoID: todo.id, deltaMinutes: deltaMinutes)
                        },
                        onAssignReminderSlot: { slotRaw in
                            viewModel.assignTodoHabitSlot(todoID: todo.id, slotRawValue: slotRaw)
                        },
                        onClearReminder: {
                            viewModel.clearTodoReminder(todoID: todo.id)
                        }
                    )
                }
            }
            .accessibilityIdentifier("vox.session.list")
        }
    }

    private var todoEmptyState: some View {
        VStack(spacing: AppTheme.Space.md) {
            if viewModel.hasActiveTodoFilters {
                ContentUnavailableView {
                    Label("没有匹配结果", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("尝试重置筛选条件或清空搜索词。")
                } actions: {
                    Button("重置筛选", action: viewModel.resetAllTodoFilters)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("vox.ios.filter.resetEmpty")
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
}

/// Smoothly scales the title text with constant `.font(.system(size: 16, weight: .semibold))`
/// and pure GPU affine `.scaleEffect(1.0 + clamped * 0.06, anchor: .leading)` (zero weight jump, zero node swap).
public struct AnimatableTitleFontModifier: ViewModifier {
    public var progress: Double

    public init(progress: Double) {
        self.progress = progress
    }

    public func body(content: Content) -> some View {
        let clamped = max(0.0, min(1.0, progress))
        let scale = 1.0 + clamped * 0.06
        content
            .font(.system(size: 16, weight: .semibold))
            .scaleEffect(scale, anchor: .leading)
    }
}

// MARK: - In-Place Expandable Todo Card (Ultra-Compact 52–68pt Collapsed <-> Unfolded Detail with Description)

private struct IOSTodoExpandableCard: View {
    let todo: VoiceTodo
    let isExpanded: Bool
    let aiOrder: ICloudAIExecutionOrder?
    let historicalTags: [String]
    let onToggleDone: () -> Void
    let onToggleExpand: () -> Void
    let onUpdateTitle: (String) -> Void
    let onUpdateDescription: (String) -> Void
    let onCycleStatus: () -> Void
    let onSelectStatus: (TodoExecutionState) -> Void
    let onCyclePriority: () -> Void
    let onSelectPriority: (TodoPriority) -> Void
    let onToggleTag: (String) -> Void
    let onAddTag: (String) -> Void
    let onToggleSubtask: (UUID) -> Void
    let onCopyTodo: () -> Void
    let onDeleteTodo: () -> Void
    let onDeleteSubtask: (UUID) -> Void
    let onUpdateSubtaskTitle: (UUID, String) -> Void
    let onAppendSubtask: (String) -> Void
    let onDispatchAI: () -> Void
    let onShiftReminderMinutes: (Int) -> Void
    let onAssignReminderSlot: (String) -> Void
    let onClearReminder: () -> Void

    @Namespace private var cardMorphNamespace
    @State private var draftTitle: String = ""
    @State private var draftDescription: String = ""
    @State private var isEditingTitle: Bool = false
    @State private var isTagPickerExpanded: Bool = (ProcessInfo.processInfo.environment["VOX_DEMO_OPEN_TAG_PICKER"] == "1")
    @State private var newTagText: String = ""
    @State private var newSubtaskText: String = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isDescriptionFocused: Bool
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
            // Persistent v02 2-line header (ONLY 4 elements when collapsed: title, status, priority, timestamp;
            // zero if-isExpanded views between Row 1 and Row 2!)
            VStack(alignment: .leading, spacing: 6) {
                unifiedTitleHeaderRow
                unifiedMetadataStatusPriorityTimestampRow
            }

            // Expand-only drawer: continuously revealed from 0pt height via TodoExpandRevealLayout + .clipped()
            // so expand-only views (description, v02 Unified Clipped Tag Shelf, v03 subtask mini-cards, and dedicated Linear row) never pop in or overlap!
            TodoExpandRevealLayout(progress: isExpanded ? 1.0 : 0.0) {
                VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                    Divider()
                        .padding(.top, 8)

                    if !todo.description.isEmpty || isDescriptionFocused || isExpanded {
                        editableDescriptionBlock
                    }

                    unifiedClippedTagShelf

                    tierThreeSpatialSubtaskList

                    dedicatedLinearAndReminderRow
                }
            }
            .clipped()
            .opacity(isExpanded ? 1.0 : 0.0)
            .allowsHitTesting(isExpanded)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous))
        .onTapGesture {
            if !isExpanded {
                onToggleExpand()
            }
        }
        .contextMenu {
            Button("复制待办内容", action: onCopyTodo)
            Button(isDone ? "标记为待处理" : "标记为已完成", action: onToggleDone)
            Divider()
            Button("删除待办", role: .destructive, action: onDeleteTodo)
        }
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous)
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
            draftDescription = todo.description
        }
        .onChange(of: todo.id) { _, _ in
            draftTitle = todo.title
            draftDescription = todo.description
            newTagText = ""
            newSubtaskText = ""
        }
        .onChange(of: todo.title) { _, updated in
            if !isTitleFocused {
                draftTitle = updated
            }
        }
        .onChange(of: todo.description) { _, updated in
            if !isDescriptionFocused {
                draftDescription = updated
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused {
                commitTitleIfValid()
                isEditingTitle = false
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                commitTitleIfValid()
                isEditingTitle = false
                isTitleFocused = false
            }
        }
        .onChange(of: isDescriptionFocused) { _, focused in
            if !focused {
                commitDescriptionIfChanged()
            }
        }
    }

    // Header Row 1: Left = Title (constant Text node + GPU scaleEffect, tap-when-expanded to edit);
    // Right = Creation time (`今天 17:31`) + Persistent rotating `chevron.down` (NO subtask progress on Row 1!)
    private var unifiedTitleHeaderRow: some View {
        HStack(alignment: .center, spacing: 6) {
            if isExpanded && isEditingTitle {
                TextField("待办短标题", text: $draftTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(1.0 + (isExpanded ? 0.06 : 0.0), anchor: .leading)
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        commitTitleIfValid()
                        isEditingTitle = false
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("待办标题")
                    .accessibilityIdentifier("vox.todo.title.editor")
            } else {
                Text(todo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(1.0 + (isExpanded ? 0.06 : 0.0), anchor: .leading)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isExpanded {
                            draftTitle = todo.title
                            isEditingTitle = true
                            isTitleFocused = true
                        } else {
                            onToggleExpand()
                        }
                    }
                    .accessibilityIdentifier("vox.todo.row." + todo.id.uuidString)
            }

            Spacer(minLength: 6)

            Text("今天 " + Self.timeFormatter.string(from: todo.createdAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
                .accessibilityIdentifier("vox.todo.timestamp")

            Button(action: onToggleExpand) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 24, height: 24)
                    .background(AppTheme.surfaceElevated, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(AppPressableButtonStyle())
            .accessibilityLabel(isExpanded ? "收起待办详情" : "展开待办详情")
            .accessibilityIdentifier("vox.todo.collapse.button")
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var editableDescriptionBlock: some View {
        TextField("补充背景说明或语音上下文…", text: $draftDescription, axis: .vertical)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1...4)
            .focused($isDescriptionFocused)
            .submitLabel(.done)
            .onSubmit {
                commitDescriptionIfChanged()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.surfacePrimary.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityLabel("待办详情说明")
            .accessibilityIdentifier("vox.todo.description.editor")
    }

    private var progressRingBadge: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 2.0)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)

            Text(String(completedSubtaskCount) + "/" + String(totalSubtaskCount))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(AppTheme.surfaceElevated, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已完成 \(completedSubtaskCount) / 共 \(totalSubtaskCount) 步")
        .accessibilityIdentifier("vox.todo.progress.badge")
    }

    // Header Row 2: Left to right = `[状态 (status)]` + `[Pri (P0/P1/P2)]` + `[🔔 提醒时间 (scheduledAt)]` + `[>=2 子流程进度 1/3]` + `Spacer()`
    private var unifiedMetadataStatusPriorityTimestampRow: some View {
        HStack(spacing: 6) {
            Button(action: isExpanded ? onCycleStatus : onToggleDone) {
                HStack(spacing: 4) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 11, weight: .bold))
                    Text(statusTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(statusColor.opacity(0.15), in: Capsule())
            }
            .buttonStyle(AppPressableButtonStyle())
            .contextMenu {
                Button("待处理") { onSelectStatus(.inbox) }
                Button("进行中") { onSelectStatus(.running) }
                Button("已完成") { onSelectStatus(.done) }
            }
            .accessibilityLabel("状态：" + statusTitle)
            .accessibilityIdentifier(isExpanded ? "vox.todo.status.pill" : ("vox.todo.status." + todo.id.uuidString))

            Button(action: onCyclePriority) {
                Text(todo.priority.rawValue)
                    .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(priorityColor(todo.priority))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(priorityColor(todo.priority).opacity(0.15), in: Capsule())
            }
            .buttonStyle(AppPressableButtonStyle())
            .allowsHitTesting(isExpanded)
            .contextMenu {
                ForEach(TodoPriority.allCases, id: \.self) { level in
                    Button(level.rawValue) { onSelectPriority(level) }
                }
            }
            .accessibilityLabel("优先级：" + todo.priority.rawValue)
            .accessibilityIdentifier("vox.todo.priority.pill")

            if todo.scheduledAt != nil || isExpanded {
                Button(action: { onShiftReminderMinutes(30) }) {
                    HStack(spacing: 3) {
                        Image(systemName: todo.scheduledAt == nil ? "bell" : "bell.fill")
                            .font(.caption2.weight(.bold))
                        Text(todo.scheduledAt.map(reminderPillText(for:)) ?? "设置提醒")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(todo.scheduledAt == nil ? Color.secondary : Color.accentColor)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        (todo.scheduledAt == nil ? Color.secondary : Color.accentColor).opacity(0.14),
                        in: Capsule()
                    )
                }
                .buttonStyle(AppPressableButtonStyle())
                .allowsHitTesting(isExpanded)
                .contextMenu {
                    Button("早上 09:00") { onAssignReminderSlot("morning") }
                    Button("上午 10:00") { onAssignReminderSlot("forenoon") }
                    Button("中午 12:30") { onAssignReminderSlot("noon") }
                    Button("下午 15:00") { onAssignReminderSlot("afternoon") }
                    Button("傍晚 18:30") { onAssignReminderSlot("evening") }
                    Button("晚上 20:30") { onAssignReminderSlot("night") }
                    if todo.scheduledAt != nil {
                        Divider()
                        Button("提前 15 分钟") { onShiftReminderMinutes(-15) }
                        Button("延后 15 分钟") { onShiftReminderMinutes(15) }
                        Button("延后 1 小时") { onShiftReminderMinutes(60) }
                        Button("取消提醒", role: .destructive) { onClearReminder() }
                    }
                }
                .accessibilityLabel("提醒时间：" + (todo.scheduledAt.map(reminderPillText(for:)) ?? "未设置"))
                .accessibilityIdentifier("vox.todo.reminder.pill")
            }

            if totalSubtaskCount >= 2 {
                progressRingBadge
                    .allowsHitTesting(false)
            }

            Spacer(minLength: 4)
        }
        .frame(height: 24)
    }

    // Dedicated row inside expanded drawer for `✨ AI do it` action + live iCloud/Mac execution status (ZERO duplicate reminder pill!)
    private var dedicatedLinearAndReminderRow: some View {
        HStack(spacing: 8) {
            Button(action: onDispatchAI) {
                HStack(spacing: 5) {
                    Image(systemName: aiActionSymbol)
                        .font(.caption.weight(.bold))
                    Text(aiActionTitle)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                }
                .foregroundStyle(aiActionTint)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(aiActionTint.opacity(0.14), in: Capsule())
            }
            .buttonStyle(AppPressableButtonStyle())
            .accessibilityLabel(aiActionTitle)
            .accessibilityIdentifier("vox.todo.action.aiDoIt")

            Spacer(minLength: 4)

            Button(action: onDeleteTodo) {
                Label("删除", systemImage: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.88))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color.red.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vox.todo.delete.button")
        }
        .padding(.top, 2)
    }

    private var aiActionTitle: String {
        if let aiOrder {
            return aiOrder.formattedButtonLabel
        }
        if let summary = todo.lastExecutionSummary, !summary.isEmpty {
            if todo.executionState == .running {
                return "⚡ Mac 已接单 · AI 执行中: \(summary)"
            } else if todo.executionState == .done {
                return "✅ AI 已完成 · \(summary)"
            }
        }
        return "✨ AI do it"
    }

    private var aiActionSymbol: String {
        guard let aiOrder else { return "sparkles" }
        switch aiOrder.state {
        case .queued: return "icloud.and.arrow.up.fill"
        case .claimedByMac, .running: return "bolt.horizontal.circle.fill"
        case .completed: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var aiActionTint: Color {
        guard let aiOrder else { return Color.accentColor }
        switch aiOrder.state {
        case .queued: return Color.cyan
        case .claimedByMac, .running: return Color.orange
        case .completed: return Color.green
        case .failed: return Color.red
        }
    }

    // Expanded Zero-Overlap Unified Clipped Tag Shelf (`v02` Tag Shelf — no `.move(edge: .top)` overlap!)
    private var unifiedClippedTagShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                IOSTodoWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(displayTags, id: \.self) { tag in
                        activeTagPillButton(tag)
                    }
                }

                Spacer(minLength: 4)

                Button(action: toggleTagPicker) {
                    HStack(spacing: 3) {
                        Image(systemName: isTagPickerExpanded ? "chevron.up" : "plus")
                            .font(.caption2.weight(.bold))
                        Text("标签")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .accessibilityLabel("添加或选择标签")
                .accessibilityIdentifier("vox.todo.tags.trigger")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            TodoExpandRevealLayout(progress: isTagPickerExpanded ? 1.0 : 0.0) {
                inlineTagTrayPanel
            }
            .clipped()
            .opacity(isTagPickerExpanded ? 1.0 : 0.0)
            .allowsHitTesting(isTagPickerExpanded)
        }
        .background(
            AppTheme.surfacePrimary.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 0.8)
        }
    }

    private func toggleTagPicker() {
        withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
            isTagPickerExpanded.toggle()
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
                .padding(.vertical, 4)
                .frame(minHeight: 26)
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

    private var inlineTagTrayPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            IOSTodoWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(historicalTags, id: \.self) { candidate in
                    historicalTagCandidateButton(candidate)
                }
            }

            HStack(spacing: 6) {
                Text("#")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)

                TextField("添加新标签…", text: $newTagText)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit {
                        submitNewTag()
                    }
                    .accessibilityIdentifier("vox.todo.tag.input")

                Button(action: submitNewTag) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("vox.todo.tag.add.button")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                AppTheme.surfacePrimary,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 0.8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vox.todo.tags.picker")
    }

    private func historicalTagCandidateButton(_ candidate: String) -> some View {
        let isSelected = todo.tags.contains(candidate)
        return Button(action: { onToggleTag(candidate) }) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark" : "plus")
                    .font(.caption2.weight(.bold))
                Text(candidate)
                    .font(.caption.weight(isSelected ? .semibold : .regular).monospacedDigit())
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : AppTheme.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.40) : Color.secondary.opacity(0.22),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vox.todo.tag.option." + candidate)
    }

    // Tier 3 (`v03` Locked Subtask List): Tactile Rounded Mini-Card Subtask Rows
    private var tierThreeSpatialSubtaskList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(todo.subtasks) { subtask in
                IOSInPlaceSubtaskBranchRow(
                    subtask: subtask,
                    onToggle: { onToggleSubtask(subtask.id) },
                    onDelete: { onDeleteSubtask(subtask.id) },
                    onCommitTitle: { updatedTitle in
                        onUpdateSubtaskTitle(subtask.id, updatedTitle)
                    }
                )
            }

            HStack(alignment: .center, spacing: AppTheme.Space.xs) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)

                TextField("添加子步骤…", text: $newSubtaskText)
                    .font(.footnote)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                AppTheme.surfacePrimary.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
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

    private func reminderPillText(for date: Date) -> String {
        let cal = Calendar.current
        let timeStr = Self.timeFormatter.string(from: date)
        if cal.isDateInToday(date) {
            return "今天 " + timeStr
        } else if cal.isDateInTomorrow(date) {
            return "明天 " + timeStr
        } else {
            return timeStr
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

    private func commitDescriptionIfChanged() {
        let trimmed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != todo.description {
            onUpdateDescription(trimmed)
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

// MARK: - `v03` Tactile Rounded Mini-Card Subtask Row with Direct In-Place Text Editing

private struct IOSInPlaceSubtaskBranchRow: View {
    let subtask: VoiceTodoSubtask
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onCommitTitle: (String) -> Void

    @State private var draftSubtaskTitle: String = ""
    @FocusState private var isSubtaskFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((subtask.isCompleted ? "已完成：" : "未完成：") + subtask.title)
            .accessibilityIdentifier("vox.todo.subtask." + subtask.id.uuidString)

            TextField("子步骤内容", text: $draftSubtaskTitle, axis: .vertical)
                .font(.footnote.weight(.medium))
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

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除子步骤")
            .accessibilityIdentifier("vox.todo.subtask.delete." + subtask.id.uuidString)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
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
    @StateObject private var providerSettings: LLMProviderSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: VoxWorkspaceViewModel, localModelLoadingStatus: LocalModelLoadingStatus?) {
        self.viewModel = viewModel
        self.localModelLoadingStatus = localModelLoadingStatus
        _providerSettings = StateObject(
            wrappedValue: LLMProviderSettingsViewModel(availability: viewModel.modelSettingsAvailability)
        )
    }

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
                    Picker("识别模式", selection: Binding(
                        get: { providerSettings.speechModel },
                        set: { model in Task { await providerSettings.updateSpeechModel(model) } }
                    )) {
                        Text("流式云端转写（默认）").tag(SpeechModelSelection.realtime)
                        Text("本地 SFSpeechRecognizer 流式识别").tag(SpeechModelSelection.appleSpeech)
                        Text("整段云端转写").tag(SpeechModelSelection.batch)
                    }
                    .accessibilityIdentifier("vox.ios.settings.speechModel")

                    Label(providerSettings.speechStatus, systemImage: "waveform")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("vox.ios.settings.speechStatus")

                    if providerSettings.speechModel == .realtime {
                        Picker("流式远端模型", selection: Binding(
                            get: { providerSettings.realtimeStreamModel },
                            set: { kind in Task { await providerSettings.updateRealtimeStreamModel(kind) } }
                        )) {
                            ForEach(RealtimeStreamModelKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .accessibilityIdentifier("vox.ios.settings.realtimeStreamModel")
                        TextField("GPT 流式部署名", text: $providerSettings.gptRealtimeDeploymentDraft,
                                  prompt: Text(providerSettings.availability.gptRealtimeDeployment.isEmpty
                                               ? "GPT 流式部署名（留空用默认配置）"
                                               : providerSettings.availability.gptRealtimeDeployment))
                            .font(.footnote)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("vox.ios.settings.gptRealtimeDeployment")
                        TextField("MAI-Transcribe-2 部署名", text: $providerSettings.maiRealtimeDeploymentDraft,
                                  prompt: Text(providerSettings.availability.maiRealtimeDeployment.isEmpty
                                               ? "MAI-Transcribe-2 部署名（留空用默认配置）"
                                               : providerSettings.availability.maiRealtimeDeployment))
                            .font(.footnote)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("vox.ios.settings.maiRealtimeDeployment")
                        Button("保存部署配置") {
                            Task { await providerSettings.saveStreamDeployments() }
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("vox.ios.settings.saveRealtimeDeployment")
                        if let message = providerSettings.deploymentMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("vox.ios.settings.deploymentMessage")
                        }
                    }
                } header: {
                    Text("1 · 语音识别")
                }

                Section {
                    HStack {
                        Text("意图与语调分析")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("iOS 已默认跳过（仅 macOS 启用）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("vox.ios.settings.stage2Skipped")
                    }
                } header: {
                    Text("2 · 前置内容分析")
                }

                Section {
                    Picker("精炼与拆解模型", selection: Binding(
                        get: { providerSettings.selectedProvider },
                        set: { provider in Task { await providerSettings.updateProvider(provider) } }
                    )) {
                        ForEach(LLMProviderSelection.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .accessibilityIdentifier("vox.ios.settings.llmProvider")
                } header: {
                    Text("3 · 文本精炼与 Stage 4 待办拆解")
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
            .iosWorkspaceInlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await providerSettings.load()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private extension View {
    @ViewBuilder
    func iosWorkspaceNavigationBarHidden() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self.toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    @ViewBuilder
    func iosWorkspaceInlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
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

    var compactTitle: String {
        switch self {
        case .all: "全部"
        case .inbox: "待处理"
        case .running: "AI"
        case .done: "已完成"
        case .failed: "失败"
        }
    }
}

// MARK: - Cross-Platform Preview Support (macOS & iOS Canvas)

@MainActor
public enum IOSCleanSlatePreviewFactory {
    public static func makePreviewViewModel(
        activePage: WorkspacePage = .todo,
        expandFirstTodo: Bool = true
    ) -> VoxWorkspaceViewModel {
        let now = Date()
        let firstID = UUID()
        let secondID = UUID()
        let initialTodos: [VoiceTodo] = [
            VoiceTodo(
                id: firstID,
                title: "液态玻璃交互走查",
                description: "整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单",
                taskPrompt: "整理下周设计评审要展示的液态玻璃交互走查清单",
                rawTranscript: "整理下周设计评审要展示的液态玻璃交互走查清单",
                projectKey: "VP",
                executionState: .inbox,
                priority: .p0,
                tags: ["#VoxPocket", "#iOS", "#Glass"],
                subtasks: [
                    VoiceTodoSubtask(title: "录制录音页默认空态与实时转写声波走查", isCompleted: true),
                    VoiceTodoSubtask(title: "验证左下切换与右下录音双按钮侧滑手势", isCompleted: false)
                ],
                createdAt: now,
                updatedAt: now
            ),
            VoiceTodo(
                id: secondID,
                title: "早间播客大纲润色",
                description: "把早间散步录下的播客大纲润色后发给搭档确认，重点核对听众来信切入段",
                taskPrompt: "把早间散步录下的播客大纲润色后发给搭档确认",
                rawTranscript: "把早间散步录下的播客大纲润色后发给搭档确认",
                projectKey: "VP",
                executionState: .done,
                priority: .p1,
                tags: ["#Podcast", "#AI"],
                subtasks: [
                    VoiceTodoSubtask(title: "补充听众深夜来信的开场引子", isCompleted: true)
                ],
                lastCompletedAt: now.addingTimeInterval(-900),
                createdAt: now.addingTimeInterval(-1800),
                updatedAt: now.addingTimeInterval(-900)
            )
        ]
        let useCase = PreviewCaptureAndTodoUseCase(initialTodos: initialTodos)
        let vm = VoxWorkspaceViewModel(useCase: useCase, defaultCaptureMode: .todo)
        vm.switchToPage(activePage)
        if expandFirstTodo {
            vm.expandedTodoID = firstID
        }
        return vm
    }
}

private actor PreviewCaptureAndTodoUseCase: VoiceCaptureAndTodoUseCase {
    private var captures: [VoiceCapture] = []
    private var todos: [VoiceTodo]
    private var reportContinuation: AsyncStream<AIExecutionStatusReport>.Continuation?
    nonisolated let aiOrderStatusReports: AsyncStream<AIExecutionStatusReport>

    init(initialTodos: [VoiceTodo] = []) {
        self.todos = initialTodos
        var continuationBox: AsyncStream<AIExecutionStatusReport>.Continuation?
        self.aiOrderStatusReports = AsyncStream { continuation in
            continuationBox = continuation
        }
        self.reportContinuation = continuationBox
    }

    func dispatchTodoToICloudAI(todoID: UUID) async throws -> ICloudAIExecutionOrder {
        guard let index = todos.firstIndex(where: { $0.id == todoID }) else {
            throw NSError(domain: "PreviewCaptureAndTodoUseCase", code: 404)
        }
        let todo = todos[index]
        let order = ICloudAIExecutionOrder(from: todo).sanitizedForCloudSync()
        todos[index] = todo.withExecutionState(.running, summary: order.progressStage, startedAt: Date())
        let continuation = reportContinuation
        let stepCount = max(1, todo.subtasks.count)
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            continuation?.yield(
                AIExecutionStatusReport(
                    orderID: order.orderID,
                    todoID: todoID,
                    state: .claimedByMac,
                    progressStage: "已认领订单 · 准备启动 AI",
                    progressFraction: 0.25,
                    assignedRunnerName: "Preview AI Agent"
                )
            )
            try? await Task.sleep(for: .milliseconds(450))
            continuation?.yield(
                AIExecutionStatusReport(
                    orderID: order.orderID,
                    todoID: todoID,
                    state: .running,
                    progressStage: "正在分析与执行 \(stepCount) 项子任务…",
                    progressFraction: 0.68,
                    assignedRunnerName: "Preview AI Agent"
                )
            )
            try? await Task.sleep(for: .milliseconds(550))
            continuation?.yield(
                AIExecutionStatusReport(
                    orderID: order.orderID,
                    todoID: todoID,
                    state: .completed,
                    progressStage: "执行完成",
                    progressFraction: 1.0,
                    outputSummary: "完成 \(stepCount) 项步骤",
                    assignedRunnerName: "Preview AI Agent"
                )
            )
        }
        return order
    }

    func recordCompletedCapture(
        mode: CaptureMode,
        rawTranscript: String,
        refinedText: String,
        localAudioFileName: String?,
        durationSeconds: TimeInterval,
        deviceSource: DeviceSource
    ) async throws -> (capture: VoiceCapture, todo: VoiceTodo?) {
        let capture = VoiceCapture(
            mode: mode,
            rawTranscript: rawTranscript,
            refinedText: refinedText,
            localAudioFileName: localAudioFileName,
            durationSeconds: durationSeconds,
            deviceSource: deviceSource,
            state: .completed
        )
        captures.append(capture)
        let todo = mode == .todo
            ? VoiceTodo(title: rawTranscript, taskPrompt: refinedText, rawTranscript: rawTranscript, projectKey: "VP", sourceCaptureID: capture.id)
            : nil
        if let todo {
            todos.append(todo)
        }
        return (capture, todo)
    }

    func recordFailedCapture(
        mode: CaptureMode,
        stage: FailureStage,
        reason: String,
        rawTranscript: String,
        localAudioFileName: String?,
        durationSeconds: TimeInterval,
        deviceSource: DeviceSource
    ) async throws -> VoiceCapture {
        VoiceCapture(mode: mode, rawTranscript: rawTranscript, state: .failed(stage: stage, reason: reason))
    }

    func retryCapture(id: UUID, targetMode: CaptureMode?) async throws -> (capture: VoiceCapture, todo: VoiceTodo?) {
        let fallback = captures.first ?? VoiceCapture(mode: .todo, rawTranscript: "Preview", refinedText: "Preview", state: .completed)
        return (fallback, todos.first)
    }

    func convertCaptureToTodo(captureID: UUID) async throws -> VoiceTodo {
        if let existing = todos.first { return existing }
        let created = VoiceTodo(title: "Preview Todo", taskPrompt: "Preview Todo", rawTranscript: "Preview Todo")
        todos.append(created)
        return created
    }

    func updateTodo(_ todo: VoiceTodo) async throws -> VoiceTodo {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = todo
        } else {
            todos.append(todo)
        }
        return todo
    }

    func runTodoWithAI(todoID: UUID, project: ProjectBinding, template: AIRunnerTemplate) async throws -> VoiceTodo {
        guard let index = todos.firstIndex(where: { $0.id == todoID }) else {
            throw NSError(domain: "PreviewCaptureAndTodoUseCase", code: 404)
        }
        let updated = todos[index].withExecutionState(.running, startedAt: Date(), completedAt: nil)
        todos[index] = updated
        return updated
    }

    func markTodoDone(todoID: UUID) async throws -> VoiceTodo {
        guard let index = todos.firstIndex(where: { $0.id == todoID }) else {
            throw NSError(domain: "PreviewCaptureAndTodoUseCase", code: 404)
        }
        let updated = todos[index].withExecutionState(.done, completedAt: Date())
        todos[index] = updated
        return updated
    }

    func deleteCapture(id: UUID) async throws {
        captures.removeAll { $0.id == id }
    }

    func deleteTodo(id: UUID) async throws {
        todos.removeAll { $0.id == id }
    }

    func fetchCaptures() async throws -> [VoiceCapture] {
        captures
    }

    func fetchTodos() async throws -> [VoiceTodo] {
        todos
    }
}

#Preview("iOS Clean Slate · Todo Unfold") {
    IOSCleanSlateWorkspaceView(
        viewModel: IOSCleanSlatePreviewFactory.makePreviewViewModel(
            activePage: .todo,
            expandFirstTodo: true
        )
    )
    .frame(width: 390, height: 844)
}

#Preview("iOS Clean Slate · Recorder") {
    IOSCleanSlateWorkspaceView(
        viewModel: IOSCleanSlatePreviewFactory.makePreviewViewModel(
            activePage: .recorder,
            expandFirstTodo: false
        )
    )
    .frame(width: 390, height: 844)
}
