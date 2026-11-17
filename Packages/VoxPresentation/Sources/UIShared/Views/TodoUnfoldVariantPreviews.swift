import SwiftUI
import CoreModels

/// Continuous height-interpolating layout that smoothly reveals expand-only drawers
/// from `0pt` height to their full natural height without any pop-in jump or `.move(edge: .top)` overlap.
public struct TodoExpandRevealLayout: Layout, Animatable {
    public var progress: Double

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public init(progress: Double) {
        self.progress = progress
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let natural = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let clamped = max(0.0, min(1.0, progress))
        return CGSize(width: proposal.width ?? natural.width, height: natural.height * clamped)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let natural = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: natural.height)
        )
    }
}

/// Horizontal width-interpolating layout for `v03`'s inline morphing tag pill editor.
public struct TodoHorizontalRevealLayout: Layout, Animatable {
    public var progress: Double

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public init(progress: Double) {
        self.progress = progress
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let natural = subview.sizeThatFits(.unspecified)
        let clamped = max(0.0, min(1.0, progress))
        return CGSize(width: natural.width * clamped, height: natural.height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let natural = subview.sizeThatFits(.unspecified)
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(natural)
        )
    }
}

/// Four converged 100% real SwiftUI Todo card in-place unfold variants (`v01..v04`):
/// - Locked `v02` 2-line 4-element collapsed header (`title`, fixed-label `status`, `priority`, `timestamp`;
///   NO `#Tag` and NO `1/3` fraction when collapsed; only `status` tappable when collapsed; tapping anywhere else expands)
/// - Locked `v03` tactile rounded mini-card subtask list (`todo list`)
/// - `TodoExpandRevealLayout(progress:)` + `.clipped()` for zero-jump expand-only views
/// - 4 distinct zero-overlap `#Tag` interaction patterns across `v01..v04`.
public enum TodoUnfoldVariantKind: String, CaseIterable, Identifiable, Sendable {
    case v01
    case v02
    case v03
    case v04

    public var id: String { rawValue }

    public var badgeCode: String { rawValue.uppercased() }

    public var title: String {
        switch self {
        case .v01: "Upward Vertical Glass Stack · 竖向玻璃浮层栈 (锁定 v02 Tag)"
        case .v02: "Native Liquid Glass Popover · 竖向玻璃弹出菜单 (锁定 v02 Tag)"
        case .v03: "Persistent Vertical Icon Column · 常驻竖向胶囊柱 (锁定 v02 Tag)"
        case .v04: "Slide-Up Vertical Glass Drawer · 上滑竖向玻璃抽屉 (锁定 v02 Tag)"
        }
    }

    public var summary: String {
        switch self {
        case .v01:
            "Header 第 1 行 [标题 + 创建时间 + 常驻翻转箭头]，第 2 行 [状态 + Pri + 🔔提醒时间 + >=2子流程进度]；锁定 v02 同框标签架；左下点击展开竖向玻璃浮层栈；✨ AI do it 实时派单。"
        case .v02:
            "Header 第 1 行 [标题 + 创建时间 + 常驻翻转箭头]，第 2 行 [状态 + Pri + 🔔提醒时间 + >=2子流程进度]；锁定 v02 同框标签架；左下点击弹出竖向玻璃 Popover；✨ AI do it 实时派单。"
        case .v03:
            "Header 第 1 行 [标题 + 创建时间 + 常驻翻转箭头]，第 2 行 [状态 + Pri + 🔔提醒时间 + >=2子流程进度]；锁定 v02 同框标签架；左下常驻紧凑竖向 4 胶囊柱；✨ AI do it 实时派单。"
        case .v04:
            "Header 第 1 行 [标题 + 创建时间 + 常驻翻转箭头]，第 2 行 [状态 + Pri + 🔔提醒时间 + >=2子流程进度]；锁定 v02 同框标签架；左下点击上滑竖向玻璃抽屉；✨ AI do it 实时派单。"
        }
    }

    public func spring(speedMultiplier: Double) -> Animation {
        let scale = max(0.1, 1.0 / max(0.1, speedMultiplier))
        switch self {
        case .v01:
            return .spring(response: 0.30 * scale, dampingFraction: 0.90)
        case .v02:
            return .spring(response: 0.28 * scale, dampingFraction: 0.94)
        case .v03:
            return .spring(response: 0.32 * scale, dampingFraction: 0.88)
        case .v04:
            return .spring(response: 0.30 * scale, dampingFraction: 0.92)
        }
    }
}

@MainActor
public final class TodoUnfoldVariantPreviewStore: ObservableObject {
    public let variant: TodoUnfoldVariantKind
    @Published public var todos: [VoiceTodo]
    @Published public var expandedTodoID: UUID?
    @Published public var isTagTrayOpen: Bool = false
    @Published public var isFilterPanelOpen: Bool = true
    @Published public var selectedFilter: String = "全部"
    @Published public var speedMultiplier: Double = 1.0
    @Published public var cascadeStageTwoVisible: Bool = false
    @Published public var recorderStatus: RecorderStatus = .idle
    @Published public var audioLevel: Float = 0.0
    @Published public var aiOrdersByTodoID: [UUID: ICloudAIExecutionOrder] = [:]
    private var aiSimulationTasks: [UUID: Task<Void, Never>] = [:]

    public let historicalTags: [String] = ["#VoxPocket", "#iOS", "#Glass", "#AI", "#Podcast", "#SwiftUI"]

    public init(
        variant: TodoUnfoldVariantKind,
        initiallyExpanded: Bool = true,
        initiallyTagTrayOpen: Bool = false,
        speedMultiplier: Double = 1.0
    ) {
        self.variant = variant
        self.speedMultiplier = speedMultiplier
        let fixedTimestamp = Calendar.current.date(bySettingHour: 17, minute: 31, second: 0, of: Date()) ?? Date()
        let morningReminder = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: fixedTimestamp.addingTimeInterval(86_400)) ?? fixedTimestamp
        let firstID = UUID(uuidString: "11111111-2222-3333-4444-555555555501") ?? UUID()
        let secondID = UUID(uuidString: "11111111-2222-3333-4444-555555555502") ?? UUID()
        let thirdID = UUID(uuidString: "11111111-2222-3333-4444-555555555503") ?? UUID()
        let fourthID = UUID(uuidString: "11111111-2222-3333-4444-555555555504") ?? UUID()
        let fifthID = UUID(uuidString: "11111111-2222-3333-4444-555555555505") ?? UUID()
        let sixthID = UUID(uuidString: "11111111-2222-3333-4444-555555555506") ?? UUID()

        self.todos = [
            VoiceTodo(
                id: firstID,
                title: "液态玻璃交互走查",
                description: "整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单",
                taskPrompt: "整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单",
                rawTranscript: "提醒我明天早上整理下周设计评审要展示的液态玻璃交互走查清单",
                projectKey: "VP",
                executionState: .inbox,
                priority: .p0,
                tags: ["#VoxPocket", "#iOS", "#Glass"],
                subtasks: [
                    VoiceTodoSubtask(
                        id: UUID(uuidString: "aaaa1111-2222-3333-4444-555555555501") ?? UUID(),
                        title: "录制录音页默认空态与实时转写声波走查",
                        isCompleted: true
                    ),
                    VoiceTodoSubtask(
                        id: UUID(uuidString: "aaaa1111-2222-3333-4444-555555555502") ?? UUID(),
                        title: "验证左下切换与右下录音双按钮侧滑手势",
                        isCompleted: false
                    ),
                    VoiceTodoSubtask(
                        id: UUID(uuidString: "aaaa1111-2222-3333-4444-555555555503") ?? UUID(),
                        title: "核对状态胶囊、优先级与创建时间原地展开零跳变",
                        isCompleted: false
                    )
                ],
                scheduledAt: morningReminder,
                timeSlot: "morning",
                externalSync: ExternalTodoSyncMetadata(provider: "linear", externalID: "TIA-508"),
                createdAt: fixedTimestamp,
                updatedAt: fixedTimestamp
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
                    VoiceTodoSubtask(
                        id: UUID(uuidString: "bbbb1111-2222-3333-4444-555555555501") ?? UUID(),
                        title: "补充听众深夜来信的开场引子",
                        isCompleted: true
                    )
                ],
                lastCompletedAt: fixedTimestamp.addingTimeInterval(-900),
                createdAt: fixedTimestamp.addingTimeInterval(-1800),
                updatedAt: fixedTimestamp.addingTimeInterval(-1800)
            ),
            VoiceTodo(
                id: thirdID,
                title: "Watch 离线录音联调",
                description: "验证 Apple Watch 锁屏录音后通过 WCSession 后台回传 iPhone 自动入库回执",
                taskPrompt: "验证 Apple Watch 离线语音同步至待办收件箱",
                rawTranscript: "验证 Apple Watch 离线语音同步至待办收件箱",
                projectKey: "VP",
                executionState: .running,
                priority: .p1,
                tags: ["#VoxPocket", "#SwiftUI"],
                subtasks: [
                    VoiceTodoSubtask(
                        id: UUID(uuidString: "cccc1111-2222-3333-4444-555555555501") ?? UUID(),
                        title: "检查 WatchInbox 音频沙盒接收与自动转写",
                        isCompleted: true
                    ),
                    VoiceTodoSubtask(
                        id: UUID(uuidString: "cccc1111-2222-3333-4444-555555555502") ?? UUID(),
                        title: "核对提醒时间自适应槽位推荐",
                        isCompleted: false
                    )
                ],
                createdAt: fixedTimestamp.addingTimeInterval(-3600),
                updatedAt: fixedTimestamp.addingTimeInterval(-3600)
            ),
            VoiceTodo(
                id: fourthID,
                title: "端侧短标题提示词压测",
                description: "压测 FoundationModels JSON 指令将 40 字口语长句稳定提炼为 <=14 字动作短语",
                taskPrompt: "压测 FoundationModels JSON 指令将长句提炼为短标题",
                rawTranscript: "压测 FoundationModels JSON 指令将长句提炼为短标题",
                projectKey: "VP",
                executionState: .inbox,
                priority: .p0,
                tags: ["#AI", "#VoxPocket"],
                subtasks: [
                    VoiceTodoSubtask(title: "校验中英文混排短标题字数上限", isCompleted: true),
                    VoiceTodoSubtask(title: "验证离线兜底提取器保留完整 Description", isCompleted: false)
                ],
                createdAt: fixedTimestamp.addingTimeInterval(-5400),
                updatedAt: fixedTimestamp.addingTimeInterval(-5400)
            ),
            VoiceTodo(
                id: fifthID,
                title: "自适应提醒槽位回归",
                description: "检查早间 09:00 与晚间 20:30 习惯锚点在手动改期后的指数平滑收敛表现",
                taskPrompt: "检查自适应提醒槽位收敛表现",
                rawTranscript: "检查自适应提醒槽位收敛表现",
                projectKey: "VP",
                executionState: .inbox,
                priority: .p2,
                tags: ["#iOS", "#AI"],
                subtasks: [
                    VoiceTodoSubtask(title: "模拟连续 3 次提前 30 分钟完成待办", isCompleted: false)
                ],
                createdAt: fixedTimestamp.addingTimeInterval(-7200),
                updatedAt: fixedTimestamp.addingTimeInterval(-7200)
            ),
            VoiceTodo(
                id: sixthID,
                title: "归档本周架构周报",
                description: "汇总 Clean-Slate 六包分层依赖门禁与云端同步脱敏测试证据并同步至 Linear",
                taskPrompt: "汇总 Clean-Slate 六包分层依赖门禁与云端同步脱敏测试证据",
                rawTranscript: "汇总 Clean-Slate 六包分层依赖门禁与云端同步脱敏测试证据",
                projectKey: "VP",
                executionState: .done,
                priority: .p2,
                tags: ["#VoxPocket"],
                subtasks: [
                    VoiceTodoSubtask(title: "确认 sanitizedForCloudSync 清空 description", isCompleted: true)
                ],
                lastCompletedAt: fixedTimestamp.addingTimeInterval(-8400),
                createdAt: fixedTimestamp.addingTimeInterval(-9000),
                updatedAt: fixedTimestamp.addingTimeInterval(-9000)
            )
        ]

        if initiallyExpanded {
            self.expandedTodoID = firstID
            self.cascadeStageTwoVisible = true
        }
        self.isTagTrayOpen = initiallyTagTrayOpen
    }

    public var primaryTodoID: UUID {
        todos[0].id
    }

    public func toggleExpand(_ id: UUID) {
        let anim = variant.spring(speedMultiplier: speedMultiplier)
        if expandedTodoID == id {
            withAnimation(anim) {
                cascadeStageTwoVisible = false
                isTagTrayOpen = false
                expandedTodoID = nil
            }
        } else {
            withAnimation(anim) {
                expandedTodoID = id
                if variant != .v04 {
                    cascadeStageTwoVisible = true
                } else {
                    cascadeStageTwoVisible = false
                }
            }
            if variant == .v04 {
                let delayMs = Int(65.0 / max(0.15, speedMultiplier))
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    guard self.expandedTodoID == id else { return }
                    withAnimation(self.variant.spring(speedMultiplier: self.speedMultiplier)) {
                        self.cascadeStageTwoVisible = true
                    }
                }
            }
        }
    }

    public func setExpanded(_ expanded: Bool, tagTrayOpen: Bool = false, animated: Bool = true) {
        let targetID: UUID? = expanded ? primaryTodoID : nil
        let applyBlock = {
            self.expandedTodoID = targetID
            self.isTagTrayOpen = tagTrayOpen
            self.cascadeStageTwoVisible = expanded
        }
        if animated {
            withAnimation(variant.spring(speedMultiplier: speedMultiplier), applyBlock)
        } else {
            applyBlock()
        }
    }

    public func toggleTagTray() {
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            isTagTrayOpen.toggle()
        }
    }

    public func toggleTag(todoID: UUID, tag: String) {
        guard let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            todos[idx] = todos[idx].withToggledTag(tag)
        }
    }

    public func addTag(todoID: UUID, tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        let normalized = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            todos[idx] = todos[idx].withAddedTag(normalized)
        }
    }

    public func cycleStatus(todoID: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        let next: TodoExecutionState
        switch todos[idx].executionState {
        case .inbox, .failed: next = .running
        case .running: next = .done
        case .done: next = .inbox
        }
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            todos[idx] = todos[idx].withExecutionState(next)
        }
    }

    public func cyclePriority(todoID: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        let next: TodoPriority
        switch todos[idx].priority {
        case .p0: next = .p1
        case .p1: next = .p2
        case .p2: next = .p0
        }
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            todos[idx] = todos[idx].withPriority(next)
        }
    }

    public func toggleSubtask(todoID: UUID, subtaskID: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            todos[idx] = todos[idx].withToggledSubtask(subtaskID)
        }
    }

    public func updateTitle(todoID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        todos[idx] = todos[idx].withTitle(trimmed)
    }

    public func updateDescription(todoID: UUID, description: String) {
        guard let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        todos[idx] = todos[idx].withDescription(description)
    }

    public func updateSubtaskTitle(todoID: UUID, subtaskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        todos[idx] = todos[idx].withUpdatedSubtaskTitle(subtaskID, title: trimmed)
    }

    public func appendSubtask(todoID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            todos[idx] = todos[idx].withAppendedSubtask(trimmed)
        }
    }

    public func toggleFilterPanel() {
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            isFilterPanelOpen.toggle()
        }
    }

    public func selectFilterOption(_ title: String) {
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            selectedFilter = title
            if variant != .v03 {
                isFilterPanelOpen = false
            }
        }
    }

    public func dispatchTodoToICloudAI(todoID: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == todoID }) else { return }
        let todo = todos[idx]
        aiSimulationTasks[todoID]?.cancel()
        let queued = ICloudAIExecutionOrder(from: todo)
        withAnimation(variant.spring(speedMultiplier: speedMultiplier)) {
            aiOrdersByTodoID[todoID] = queued
            todos[idx] = todos[idx].withExecutionState(.running, summary: queued.progressStage)
        }
        aiSimulationTasks[todoID] = Task { @MainActor [weak self] in
            guard let self else { return }
            let scale = max(0.2, 1.0 / max(0.2, self.speedMultiplier))
            try? await Task.sleep(for: .milliseconds(Int(350 * scale)))
            guard !Task.isCancelled else { return }
            let claimed = queued.withState(
                .claimedByMac,
                progressStage: "已认领 · 准备启动 Mac AI",
                progressFraction: 0.25,
                assignedRunnerName: "Mac AI Agent"
            )
            withAnimation(self.variant.spring(speedMultiplier: self.speedMultiplier)) {
                self.aiOrdersByTodoID[todoID] = claimed
            }

            try? await Task.sleep(for: .milliseconds(Int(450 * scale)))
            guard !Task.isCancelled else { return }
            let stepCount = max(1, todo.subtasks.count)
            let running = claimed.withState(
                .running,
                progressStage: "正在执行 \(stepCount) 项子步骤…",
                progressFraction: 0.68,
                assignedRunnerName: "Mac AI Agent"
            )
            withAnimation(self.variant.spring(speedMultiplier: self.speedMultiplier)) {
                self.aiOrdersByTodoID[todoID] = running
            }

            try? await Task.sleep(for: .milliseconds(Int(550 * scale)))
            guard !Task.isCancelled else { return }
            let summary = "完成 \(stepCount) 项步骤"
            let completed = running.withState(
                .completed,
                progressStage: "执行完成",
                progressFraction: 1.0,
                outputSummary: summary,
                assignedRunnerName: "Mac AI Agent"
            )
            withAnimation(self.variant.spring(speedMultiplier: self.speedMultiplier)) {
                self.aiOrdersByTodoID[todoID] = completed
                if let currentIdx = self.todos.firstIndex(where: { $0.id == todoID }) {
                    self.todos[currentIdx] = self.todos[currentIdx].withExecutionState(.done, summary: summary)
                }
            }
        }
    }
}

/// Complete 390×844 iPhone viewport rendering a single SwiftUI unfold variant (`v01..v04`).
@MainActor
public struct TodoUnfoldVariantPhoneViewport: View {
    @ObservedObject private var store: TodoUnfoldVariantPreviewStore
    private let interpolationProgress: Double?
    @Namespace private var glass

    public init(
        store: TodoUnfoldVariantPreviewStore,
        interpolationProgress: Double? = nil
    ) {
        self.store = store
        self.interpolationProgress = interpolationProgress
    }

    private var listCardSpacing: CGFloat {
        switch store.variant {
        case .v01: return 8
        case .v02: return 9
        case .v03: return 10
        case .v04: return 8
        }
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            RecorderBackdrop(status: .idle, audioLevel: 0.0)

            VStack(alignment: .leading, spacing: 0) {
                phoneStatusBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                headerBar
                    .padding(.horizontal, AppTheme.Space.lg)
                    .padding(.top, AppTheme.Space.xs)
                    .padding(.bottom, AppTheme.Space.sm)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(spacing: listCardSpacing) {
                            ForEach(Array(store.todos.enumerated()), id: \.element.id) { index, todo in
                                let isExpanded = store.expandedTodoID == todo.id
                                let expandFraction: Double = {
                                    if let p = interpolationProgress, index == 0 {
                                        return min(1.0, max(0.0, p))
                                    }
                                    return isExpanded ? 1.0 : 0.0
                                }()
                                let siblingDimmed = store.variant == .v03 && store.expandedTodoID != nil && !isExpanded

                                TodoUnfoldVariantCardView(
                                    variant: store.variant,
                                    todo: todo,
                                    aiOrder: store.aiOrdersByTodoID[todo.id],
                                    isExpanded: expandFraction > 0.01,
                                    expandFraction: expandFraction,
                                    isTagTrayOpen: index == 0 && store.isTagTrayOpen,
                                    cascadeStageTwoVisible: store.cascadeStageTwoVisible || (interpolationProgress ?? 0) > 0.30,
                                    historicalTags: store.historicalTags,
                                    speedMultiplier: store.speedMultiplier,
                                    onToggleExpand: { store.toggleExpand(todo.id) },
                                    onToggleTagTray: { store.toggleTagTray() },
                                    onCycleStatus: { store.cycleStatus(todoID: todo.id) },
                                    onCyclePriority: { store.cyclePriority(todoID: todo.id) },
                                    onToggleTag: { tag in store.toggleTag(todoID: todo.id, tag: tag) },
                                    onAddTag: { tag in store.addTag(todoID: todo.id, tag: tag) },
                                    onToggleSubtask: { subID in store.toggleSubtask(todoID: todo.id, subtaskID: subID) },
                                    onUpdateTitle: { title in store.updateTitle(todoID: todo.id, title: title) },
                                    onUpdateDescription: { desc in store.updateDescription(todoID: todo.id, description: desc) },
                                    onUpdateSubtaskTitle: { subID, title in store.updateSubtaskTitle(todoID: todo.id, subtaskID: subID, title: title) },
                                    onAppendSubtask: { title in store.appendSubtask(todoID: todo.id, title: title) },
                                    onDispatchAI: { store.dispatchTodoToICloudAI(todoID: todo.id) }
                                )
                                .opacity(siblingDimmed ? 0.82 : 1.0)
                                .scaleEffect(siblingDimmed ? 0.99 : 1.0)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Space.lg)
                    .padding(.top, AppTheme.Space.xs)
                    .padding(.bottom, 136)
                }
            }

            bottomDualGlassBar
        }
        .frame(width: 390, height: 844)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.2)
        }
    }

    private var phoneStatusBar: some View {
        HStack {
            Text("9:41")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Spacer()
            Capsule()
                .fill(Color.black.opacity(0.82))
                .frame(width: 92, height: 24)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.md) {
            Text("待办清单")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Spacer(minLength: AppTheme.Space.sm)

            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(AppTheme.surfaceCard, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                }
        }
    }

    private var filterOptionsWithCounts: [(title: String, count: Int)] {
        [
            ("全部", store.todos.count),
            ("待处理", store.todos.filter { $0.executionState == .inbox }.count),
            ("AI 执行中", store.todos.filter { $0.executionState == .running }.count),
            ("已完成", store.todos.filter { $0.executionState == .done }.count)
        ]
    }

    private var activeFilterCount: Int {
        filterOptionsWithCounts.first(where: { $0.title == store.selectedFilter })?.count ?? store.todos.count
    }

    @ViewBuilder
    private var bottomLeadingVerticalFilterControl: some View {
        switch store.variant {
        case .v01:
            // v01: Upward Vertical Liquid Glass Floating Stack
            VStack(alignment: .leading, spacing: 6) {
                TodoExpandRevealLayout(progress: store.isFilterPanelOpen ? 1.0 : 0.0) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filterOptionsWithCounts, id: \.title) { item in
                            verticalFilterRow(title: item.title, count: item.count, isSelected: store.selectedFilter == item.title)
                        }
                    }
                    .padding(6)
                    .frame(width: 156, alignment: .leading)
                    .modifier(RecorderGlassModifier())
                    .padding(.bottom, 2)
                }
                .clipped()
                .opacity(store.isFilterPanelOpen ? 1.0 : 0.0)
                .allowsHitTesting(store.isFilterPanelOpen)

                compactFilterTriggerCapsule
            }

        case .v02:
            // v02: Native-Style Liquid Glass Popover Menu above bottom-left capsule
            VStack(alignment: .leading, spacing: 4) {
                if store.isFilterPanelOpen {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("状态筛选")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)

                        Divider()

                        ForEach(filterOptionsWithCounts, id: \.title) { item in
                            verticalFilterRow(title: item.title, count: item.count, isSelected: store.selectedFilter == item.title)
                        }
                    }
                    .padding(6)
                    .frame(width: 164, alignment: .leading)
                    .modifier(RecorderGlassModifier())
                    .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
                }

                compactFilterTriggerCapsule
            }

        case .v03:
            // v03: Persistent Compact Vertical Icon/Label Capsule Column
            VStack(alignment: .leading, spacing: 4) {
                ForEach(filterOptionsWithCounts, id: \.title) { item in
                    let isSelected = store.selectedFilter == item.title
                    Button(action: { store.selectFilterOption(item.title) }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(item.title)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            Spacer(minLength: 4)
                            Text("\(item.count)")
                                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(width: 122, alignment: .leading)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.18))
                            }
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .modifier(RecorderGlassModifier())

        case .v04:
            // v04: Slide-Up Vertical Glass Drawer Card
            VStack(alignment: .leading, spacing: 6) {
                TodoExpandRevealLayout(progress: store.isFilterPanelOpen ? 1.0 : 0.0) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label("筛选清单", systemImage: "line.3.horizontal.decrease.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Button(action: { store.toggleFilterPanel() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)

                        ForEach(filterOptionsWithCounts, id: \.title) { item in
                            verticalFilterRow(title: item.title, count: item.count, isSelected: store.selectedFilter == item.title)
                        }
                    }
                    .padding(7)
                    .frame(width: 172, alignment: .leading)
                    .modifier(RecorderGlassModifier())
                }
                .clipped()
                .opacity(store.isFilterPanelOpen ? 1.0 : 0.0)
                .allowsHitTesting(store.isFilterPanelOpen)

                compactFilterTriggerCapsule
            }
        }
    }

    private var compactFilterTriggerCapsule: some View {
        Button(action: { store.toggleFilterPanel() }) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text(store.selectedFilter)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(activeFilterCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(store.isFilterPanelOpen ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
            .modifier(RecorderGlassModifier())
        }
        .buttonStyle(.plain)
    }

    private func verticalFilterRow(title: String, count: Int, isSelected: Bool) -> some View {
        Button(action: { store.selectFilterOption(title) }) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                Spacer(minLength: 6)
                Text(String(count))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private var bottomDualGlassBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                bottomLeadingVerticalFilterControl
                    .glassEffectID("previewFilterBar", in: glass)

                HStack {
                    Image(systemName: "waveform")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .modifier(RecorderGlassModifier())
                        .glassEffectID("previewSwitch", in: glass)

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 54, height: 54)
                            .shadow(color: Color.accentColor.opacity(0.28), radius: 10, y: 4)

                        Image(systemName: "mic.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .glassEffectID("previewRecord", in: glass)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
            .padding(.top, 4)
        }
    }
}

// MARK: - Individual Variant Card (`v01..v04` Ultra-Compact 52–68pt Collapsed <-> Rich Unfolded)

@MainActor
public struct TodoUnfoldVariantCardView: View {
    public let variant: TodoUnfoldVariantKind
    public let todo: VoiceTodo
    public let aiOrder: ICloudAIExecutionOrder?
    public let isExpanded: Bool
    public let expandFraction: Double
    public let isTagTrayOpen: Bool
    public let cascadeStageTwoVisible: Bool
    public let historicalTags: [String]
    public let speedMultiplier: Double
    public let onToggleExpand: () -> Void
    public let onToggleTagTray: () -> Void
    public let onCycleStatus: () -> Void
    public let onCyclePriority: () -> Void
    public let onToggleTag: (String) -> Void
    public let onAddTag: (String) -> Void
    public let onToggleSubtask: (UUID) -> Void
    public let onUpdateTitle: (String) -> Void
    public let onUpdateDescription: (String) -> Void
    public let onUpdateSubtaskTitle: (UUID, String) -> Void
    public let onAppendSubtask: (String) -> Void
    public let onDispatchAI: () -> Void

    @Namespace private var morphNamespace
    @State private var draftTitle: String = ""
    @State private var draftDescription: String = ""
    @State private var isEditingTitle: Bool = false
    @State private var newTagText: String = ""
    @State private var newSubtaskText: String = ""

    public init(
        variant: TodoUnfoldVariantKind,
        todo: VoiceTodo,
        aiOrder: ICloudAIExecutionOrder? = nil,
        isExpanded: Bool,
        expandFraction: Double,
        isTagTrayOpen: Bool,
        cascadeStageTwoVisible: Bool,
        historicalTags: [String],
        speedMultiplier: Double,
        onToggleExpand: @escaping () -> Void,
        onToggleTagTray: @escaping () -> Void,
        onCycleStatus: @escaping () -> Void,
        onCyclePriority: @escaping () -> Void,
        onToggleTag: @escaping (String) -> Void,
        onAddTag: @escaping (String) -> Void,
        onToggleSubtask: @escaping (UUID) -> Void,
        onUpdateTitle: @escaping (String) -> Void,
        onUpdateDescription: @escaping (String) -> Void = { _ in },
        onUpdateSubtaskTitle: @escaping (UUID, String) -> Void,
        onAppendSubtask: @escaping (String) -> Void,
        onDispatchAI: @escaping () -> Void = {}
    ) {
        self.variant = variant
        self.todo = todo
        self.aiOrder = aiOrder
        self.isExpanded = isExpanded
        self.expandFraction = expandFraction
        self.isTagTrayOpen = isTagTrayOpen
        self.cascadeStageTwoVisible = cascadeStageTwoVisible
        self.historicalTags = historicalTags
        self.speedMultiplier = speedMultiplier
        self.onToggleExpand = onToggleExpand
        self.onToggleTagTray = onToggleTagTray
        self.onCycleStatus = onCycleStatus
        self.onCyclePriority = onCyclePriority
        self.onToggleTag = onToggleTag
        self.onAddTag = onAddTag
        self.onToggleSubtask = onToggleSubtask
        self.onUpdateTitle = onUpdateTitle
        self.onUpdateDescription = onUpdateDescription
        self.onUpdateSubtaskTitle = onUpdateSubtaskTitle
        self.onAppendSubtask = onAppendSubtask
        self.onDispatchAI = onDispatchAI
    }

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

    private var unselectedHistoricalTags: [String] {
        historicalTags.filter { !todo.tags.contains($0) }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Persistent 2-line v02 header (ONLY 4 elements when collapsed: title, status, priority, timestamp;
            // ZERO if-isExpanded views inserted between Row 1 and Row 2!)
            VStack(alignment: .leading, spacing: 6) {
                v02HeaderRow1TitleAndTime
                v02HeaderRow2StatusAndPriority
            }

            // Expand-only drawer: continuously revealed from 0pt height via TodoExpandRevealLayout + .clipped()
            // so expand-only views (description, 4 zero-overlap tag designs, v03 subtask mini-cards, and dedicated Linear row) never pop in or overlap!
            TodoExpandRevealLayout(progress: expandFraction) {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.top, 8)

                    if !todo.description.isEmpty || isExpanded {
                        expandedDescriptionEditorBlock
                    }

                    zeroOverlapTagSectionForVariant

                    v03SpatialHeroSubtaskCards

                    dedicatedLinearAndReminderRow
                }
            }
            .clipped()
            .opacity(min(1.0, max(0.0, expandFraction * 1.15)))
            .allowsHitTesting(isExpanded)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous))
        .onTapGesture {
            if !isExpanded {
                onToggleExpand()
            }
        }
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous)
                .strokeBorder(
                    isExpanded
                        ? Color.accentColor.opacity(0.38)
                        : Color.primary.opacity(0.06),
                    lineWidth: isExpanded ? 1.2 : 0.8
                )
        }
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.12 : 0.03),
            radius: isExpanded ? 12 : 4,
            y: isExpanded ? 5 : 1
        )
        .onAppear {
            draftTitle = todo.title
            draftDescription = todo.description
        }
        .onChange(of: todo.title) { _, updated in
            draftTitle = updated
        }
        .onChange(of: todo.description) { _, updated in
            draftDescription = updated
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                isEditingTitle = false
            }
        }
    }

    // MARK: - Persistent 2-Row Header (Row 1: Left Title with Constant Font + GPU scaleEffect, Right Creation Time + Persistent Rotating Chevron | Row 2: Status + Priority + Reminder Time + Conditional Subtask Progress (>=2))

    private var v02HeaderRow1TitleAndTime: some View {
        HStack(alignment: .center, spacing: 6) {
            if isExpanded && isEditingTitle {
                TextField("待办短标题", text: $draftTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(1.0 + expandFraction * 0.06, anchor: .leading)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .onSubmit {
                        onUpdateTitle(draftTitle)
                        isEditingTitle = false
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(todo.title)
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(1.0 + expandFraction * 0.06, anchor: .leading)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isExpanded {
                            draftTitle = todo.title
                            isEditingTitle = true
                        } else {
                            onToggleExpand()
                        }
                    }
            }

            Spacer(minLength: 6)

            timestampLabel
                .allowsHitTesting(false)

            Button(action: onToggleExpand) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expandFraction * 180.0))
                    .frame(width: 24, height: 24)
                    .background(AppTheme.surfaceElevated, in: Circle())
            }
            .buttonStyle(AppPressableButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var v02HeaderRow2StatusAndPriority: some View {
        HStack(spacing: 6) {
            // 1. Status capsule: ALWAYS displays icon + text label at fixed 24pt height
            fixedStatusCapsule

            // 2. Priority capsule: fixed 24pt height; when collapsed, hit-testing is disabled so tapping priority expands the card
            fixedPriorityCapsule
                .allowsHitTesting(isExpanded)

            // 3. Reminder time (scheduledAt): placed right after Pri on Row 2
            if todo.scheduledAt != nil {
                reminderMicroBadge
                    .allowsHitTesting(false)
            }

            // 4. Conditional Subtask Progress: ONLY shown when todo.subtasks.count >= 2, placed AFTER reminder time on Row 2!
            if totalSubtaskCount >= 2 {
                compactProgressBadge
                    .allowsHitTesting(false)
            }

            Spacer(minLength: 4)
        }
        .frame(height: 24)
    }

    private var dedicatedLinearAndReminderRow: some View {
        HStack(spacing: 8) {
            aiDoItActionCapsule

            Spacer(minLength: 4)

            reminderMicroBadge
        }
        .padding(.top, 2)
    }

    // MARK: - Shared Fixed-Size Header Micro-Components (Zero Shape / Text Jump)

    private var fixedStatusCapsule: some View {
        Button(action: onCycleStatus) {
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
    }

    private var fixedPriorityCapsule: some View {
        Button(action: onCyclePriority) {
            Text(todo.priority.rawValue)
                .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                .foregroundStyle(priorityColor)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(priorityColor.opacity(0.15), in: Capsule())
        }
        .buttonStyle(AppPressableButtonStyle())
    }

    private var compactProgressBadge: some View {
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

            Text("\(completedSubtaskCount)/\(totalSubtaskCount)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(AppTheme.surfaceElevated, in: Capsule())
    }

    private var timestampLabel: some View {
        Text("今天 " + Self.timeFormatter.string(from: todo.updatedAt))
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var reminderMicroBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "bell.fill")
                .font(.system(size: 10, weight: .bold))
            Text("明早 09:00")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(Color.accentColor.opacity(0.13), in: Capsule())
    }

    private var expandedDescriptionEditorBlock: some View {
        TextField("补充背景说明或语音上下文…", text: $draftDescription, axis: .vertical)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .onSubmit {
                onUpdateDescription(draftDescription)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.surfacePrimary.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
            }
    }

    private var aiDoItActionCapsule: some View {
        let label = aiOrder?.formattedButtonLabel ?? "✨ AI do it"
        let tint: Color = {
            guard let aiOrder else { return Color.accentColor }
            switch aiOrder.state {
            case .queued: return Color.cyan
            case .claimedByMac, .running: return Color.orange
            case .completed: return Color.green
            case .failed: return Color.red
            }
        }()
        let symbol: String = {
            guard let aiOrder else { return "sparkles" }
            switch aiOrder.state {
            case .queued: return "icloud.and.arrow.up.fill"
            case .claimedByMac, .running: return "bolt.horizontal.circle.fill"
            case .completed: return "checkmark.seal.fill"
            case .failed: return "exclamationmark.triangle.fill"
            }
        }()
        return Button(action: onDispatchAI) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(AppPressableButtonStyle())
    }

    // MARK: - Locked `v02` Unified Clipped Tag Shelf Across All Cards (`v01..v04`)

    @ViewBuilder
    private var zeroOverlapTagSectionForVariant: some View {
        v02UnifiedClippedTagShelf
    }

    /// `v01` — Single-row Inline Horizontal Tag Rail: active tags + unselected quick chips + inline `#新标签` input on one horizontal track.
    private var v01InlineHorizontalTagRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(todo.tags, id: \.self) { tag in
                    selectedTagChip(tag)
                }

                ForEach(unselectedHistoricalTags.prefix(isTagTrayOpen ? 4 : 2), id: \.self) { candidate in
                    unselectedCandidateTagChip(candidate)
                }

                inlineCompactNewTagField(width: 96)
            }
            .padding(.vertical, 1)
        }
    }

    /// `v02` — Unified Clipped Tag Shelf: one bordered container whose bottom shelf unrolls from 0pt via `TodoExpandRevealLayout` + `.clipped()`.
    private var v02UnifiedClippedTagShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(todo.tags, id: \.self) { tag in
                            selectedTagChip(tag)
                        }
                    }
                }

                Spacer(minLength: 4)

                Button(action: onToggleTagTray) {
                    HStack(spacing: 3) {
                        Image(systemName: isTagTrayOpen ? "chevron.up" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("标签")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            TodoExpandRevealLayout(progress: isTagTrayOpen ? 1.0 : 0.0) {
                VStack(alignment: .leading, spacing: 7) {
                    Divider()

                    TodoUnfoldWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(historicalTags, id: \.self) { candidate in
                            let selected = todo.tags.contains(candidate)
                            Button(action: { onToggleTag(candidate) }) {
                                HStack(spacing: 3) {
                                    Image(systemName: selected ? "checkmark" : "plus")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(candidate)
                                        .font(.system(size: 11, weight: selected ? .semibold : .regular).monospacedDigit())
                                }
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    selected ? Color.accentColor.opacity(0.14) : AppTheme.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("#")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("添加新标签…", text: $newTagText)
                            .font(.caption)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                onAddTag(newTagText)
                                newTagText = ""
                            }
                        Button(action: {
                            onAddTag(newTagText)
                            newTagText = ""
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        AppTheme.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .clipped()
            .opacity(isTagTrayOpen ? 1.0 : 0.0)
            .allowsHitTesting(isTagTrayOpen)
        }
        .background(
            AppTheme.surfacePrimary.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
    }

    /// `v03` — Inline Morphing Pill Editor: tapping `+` expands horizontally on the same single row via `TodoHorizontalRevealLayout` + `.clipped()`.
    private var v03InlineMorphingPillEditor: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(todo.tags, id: \.self) { tag in
                    selectedTagChip(tag)
                }

                HStack(spacing: 5) {
                    Button(action: onToggleTagTray) {
                        Image(systemName: isTagTrayOpen ? "xmark" : "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(AppPressableButtonStyle())

                    TodoHorizontalRevealLayout(progress: isTagTrayOpen ? 1.0 : 0.0) {
                        HStack(spacing: 5) {
                            ForEach(unselectedHistoricalTags.prefix(3), id: \.self) { candidate in
                                unselectedCandidateTagChip(candidate)
                            }
                            inlineCompactNewTagField(width: 88)
                        }
                        .padding(.trailing, 4)
                    }
                    .clipped()
                    .opacity(isTagTrayOpen ? 1.0 : 0.0)
                    .allowsHitTesting(isTagTrayOpen)
                }
                .padding(2)
                .background(
                    AppTheme.surfacePrimary.opacity(isTagTrayOpen ? 0.72 : 0.0),
                    in: Capsule()
                )
                .overlay {
                    if isTagTrayOpen {
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.8)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// `v04` — Flat Toggle Tag Matrix: all active + historical candidate tags + inline `#新标签` laid out flat in a single-surface wrapping grid.
    private var v04FlatToggleTagMatrix: some View {
        TodoUnfoldWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(historicalTags, id: \.self) { candidate in
                let selected = todo.tags.contains(candidate)
                if selected {
                    selectedTagChip(candidate)
                } else {
                    unselectedCandidateTagChip(candidate)
                }
            }
            inlineCompactNewTagField(width: 92)
        }
        .padding(8)
        .background(
            AppTheme.surfacePrimary.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        }
    }

    private func selectedTagChip(_ tag: String) -> some View {
        Button(action: { onToggleTag(tag) }) {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text(tag)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                Color.accentColor.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private func unselectedCandidateTagChip(_ tag: String) -> some View {
        Button(action: { onToggleTag(tag) }) {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(tag)
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                AppTheme.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private func inlineCompactNewTagField(width: CGFloat) -> some View {
        HStack(spacing: 3) {
            Text("#")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
            TextField("新标签", text: $newTagText)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
                .frame(width: width)
                .onSubmit {
                    onAddTag(newTagText)
                    newTagText = ""
                }
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 0.7)
        }
    }

    // MARK: - Locked `v03` Spatial Hero Subtask Mini-Cards Across All Variants (`v01..v04`)

    private var v03SpatialHeroSubtaskCards: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(todo.subtasks) { subtask in
                Button(action: { onToggleSubtask(subtask.id) }) {
                    HStack(spacing: 8) {
                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(subtask.isCompleted ? .green : .secondary)

                        Text(subtask.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                            .strikethrough(subtask.isCompleted, color: .secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        AppTheme.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
                    }
                }
                .buttonStyle(.plain)
            }

            addSubtaskInputRow
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    AppTheme.surfacePrimary.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }

    private var addSubtaskInputRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            TextField("添加子步骤…", text: $newSubtaskText)
                .font(.caption)
                .textFieldStyle(.plain)
                .onSubmit {
                    onAppendSubtask(newSubtaskText)
                    newSubtaskText = ""
                }
        }
        .padding(.vertical, 3)
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

    private var priorityColor: Color {
        switch todo.priority {
        case .p0: .red
        case .p1: .orange
        case .p2: .blue
        }
    }
}

struct TodoUnfoldWrappingFlowLayout: Layout {
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

// MARK: - 4-Up Interactive Comparison Board (`v01..v04` Side-by-Side)

public enum PreviewAtmosphereStageOption: String, CaseIterable, Identifiable, Sendable {
    case idle
    case listening
    case transcribing
    case refining
    case error

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .listening: "录音"
        case .transcribing: "转译"
        case .refining: "润色"
        case .error: "错误"
        }
    }

    public var recorderStatus: RecorderStatus {
        switch self {
        case .idle: .idle
        case .listening: .listening
        case .transcribing: .transcribing
        case .refining: .refining
        case .error: .error
        }
    }

    public var simulatedAudioLevel: Float {
        switch self {
        case .listening: 0.68
        default: 0.0
        }
    }
}

public enum PreviewHostTopTab: String, CaseIterable, Identifiable, Sendable {
    case todoAndVerticalFilter = "todo"
    case recorderFiveStageAtmosphere = "recorder"
    case dynamicIslandFourVariants = "dynamic-island"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .todoAndVerticalFilter:
            "Tab 1 · Todo 列表与竖向 Filter"
        case .recorderFiveStageAtmosphere:
            "Tab 2 · 录音页 5 阶段色彩流转"
        case .dynamicIslandFourVariants:
            "Tab 3 · 灵动岛 4 套方案 (DI-v01..v04)"
        }
    }

    public var symbolName: String {
        switch self {
        case .todoAndVerticalFilter: "checklist"
        case .recorderFiveStageAtmosphere: "waveform.circle.fill"
        case .dynamicIslandFourVariants: "capsule.inset.filled"
        }
    }
}

public enum DynamicIslandPreviewVariantKind: String, CaseIterable, Identifiable, Sendable {
    case diV01 = "di-v01"
    case diV02 = "di-v02"
    case diV03 = "di-v03"
    case diV04 = "di-v04"

    public var id: String { rawValue }
    public var badgeCode: String { rawValue.uppercased() }

    public var title: String {
        switch self {
        case .diV01: "极简左勾选 + 双顺延胶囊岛 (高 112pt)"
        case .diV02: "左右分栏 · 双列子步骤快勾岛 (高 148pt)"
        case .diV03: "四阶段声波流光 + AI 提炼舞台岛 (高 156pt)"
        case .diV04: "水平 4 节点作息习惯时间轴轨道岛 (高 138pt)"
        }
    }

    public var summary: String {
        switch self {
        case .diV01:
            "极简上下两层 (112pt)：上层左侧直接点按 [○/✓] 圆环触发完成 + P0 + 标题 + ⏳14:59；下层仅平铺 [⏰ +15m] 与 [🌙 明早 08:35 (习惯)] 双顺延胶囊，无子任务列表、无多余完成按钮。"
        case .diV02:
            "HStack 左右分栏 (148pt)：左栏 (118pt) 放环形进度圈 1/3 + 短标题 + [+15m] 芯片；右栏 (224pt) 上下并列 2 张圆角子任务微卡，原位点满 3/3 自动完成，零多余完成按钮。"
        case .diV03:
            "四阶段声波流光舞台 (156pt)：顶栏可点按切换『录音/转译/润色/入库』阶段胶囊，中央 20 根高低起伏 AtmosphereGlass 彩色声波柱 + #VoxPocket #iOS 标签气泡，底栏 [🎙️ 语音追补] 与 [✨ AI do it]。"
        case .diV04:
            "水平作息时间轴轨道 (138pt)：顶栏 [○/✓] 勾选环 + 标题 + 当前锚点，中间横跨 4 节点作息轨道『🌅 08:35 ━━●━━ ☀️ 12:30 ━━ 🌆 18:30 ━━ 🌙 21:00』，点节点直接切换提醒时段。"
        }
    }

    public var expandedHeight: CGFloat {
        switch self {
        case .diV01: 112
        case .diV02: 148
        case .diV03: 156
        case .diV04: 138
        }
    }
}

public enum DynamicIslandSurfaceBezelMode: String, CaseIterable, Identifiable, Sendable {
    case minimal
    case compact
    case expanded
    case lockScreenBanner

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .minimal: "Minimal"
        case .compact: "Compact"
        case .expanded: "Expanded"
        case .lockScreenBanner: "Lock"
        }
    }

    public var targetSize: CGSize {
        switch self {
        case .minimal: CGSize(width: 37, height: 37)
        case .compact: CGSize(width: 216, height: 37)
        case .expanded: CGSize(width: 370, height: 156)
        case .lockScreenBanner: CGSize(width: 366, height: 116)
        }
    }

    public var cornerRadius: CGFloat {
        switch self {
        case .minimal, .compact: 18.5
        case .expanded: 38.0
        case .lockScreenBanner: 28.0
        }
    }
}

@MainActor
public final class TodoUnfoldFourUpBoardController: ObservableObject {
    @Published public var activeTab: PreviewHostTopTab = .todoAndVerticalFilter
    @Published public var speedMultiplier: Double = 1.0 {
        didSet {
            for store in stores.values {
                store.speedMultiplier = speedMultiplier
            }
        }
    }
    /// Recorder page 5-stage atmosphere switcher (Tab 2). Todo page (Tab 1) stays constantly at `.idle`.
    @Published public var stageOption: PreviewAtmosphereStageOption = .listening {
        didSet {
            recorderStagesByBezel[0] = stageOption
        }
    }
    @Published public var recorderStagesByBezel: [Int: PreviewAtmosphereStageOption] = [
        0: .listening,
        1: .transcribing,
        2: .refining,
        3: .error
    ]
    @Published public var islandModeByVariant: [DynamicIslandPreviewVariantKind: DynamicIslandSurfaceBezelMode] = [
        .diV01: .expanded,
        .diV02: .expanded,
        .diV03: .expanded,
        .diV04: .expanded
    ]
    @Published public var islandPhaseByVariant: [DynamicIslandPreviewVariantKind: PreviewAtmosphereStageOption] = [
        .diV01: .listening,
        .diV02: .transcribing,
        .diV03: .refining,
        .diV04: .idle
    ]
    @Published public var islandCompletedSubtasksByVariant: [DynamicIslandPreviewVariantKind: Int] = [
        .diV01: 1,
        .diV02: 1,
        .diV03: 1,
        .diV04: 1
    ]
    @Published public var islandIsDoneByVariant: [DynamicIslandPreviewVariantKind: Bool] = [
        .diV01: false,
        .diV02: false,
        .diV03: false,
        .diV04: false
    ]
    @Published public var islandAnchorByVariant: [DynamicIslandPreviewVariantKind: String] = [
        .diV01: "08:35",
        .diV02: "08:35",
        .diV03: "09:00",
        .diV04: "08:35"
    ]
    @Published public var islandReceiptByVariant: [DynamicIslandPreviewVariantKind: String] = [:]
    @Published public var colorScheme: ColorScheme = .dark
    @Published public var allExpanded: Bool = true
    @Published public var allTagTraysOpen: Bool = false

    public let stores: [TodoUnfoldVariantKind: TodoUnfoldVariantPreviewStore]

    public init(initiallyExpanded: Bool = true) {
        self.allExpanded = initiallyExpanded
        var map: [TodoUnfoldVariantKind: TodoUnfoldVariantPreviewStore] = [:]
        for kind in TodoUnfoldVariantKind.allCases {
            let s = TodoUnfoldVariantPreviewStore(variant: kind, initiallyExpanded: initiallyExpanded)
            s.recorderStatus = .idle
            s.audioLevel = 0.0
            map[kind] = s
        }
        self.stores = map
    }

    public func store(for kind: TodoUnfoldVariantKind) -> TodoUnfoldVariantPreviewStore {
        stores[kind]!
    }

    public func setAllRecorderStages(_ stage: PreviewAtmosphereStageOption) {
        stageOption = stage
        for idx in 0..<4 {
            recorderStagesByBezel[idx] = stage
        }
    }

    public func toggleAllExpanded() {
        allExpanded.toggle()
        for kind in TodoUnfoldVariantKind.allCases {
            stores[kind]?.setExpanded(allExpanded, tagTrayOpen: allTagTraysOpen, animated: true)
        }
        let targetIslandMode: DynamicIslandSurfaceBezelMode = allExpanded ? .expanded : .compact
        for kind in DynamicIslandPreviewVariantKind.allCases {
            islandModeByVariant[kind] = targetIslandMode
        }
    }

    public func toggleAllTagTrays() {
        allTagTraysOpen.toggle()
        for kind in TodoUnfoldVariantKind.allCases {
            stores[kind]?.toggleTagTray()
        }
    }

    public func advanceIslandSubtask(for kind: DynamicIslandPreviewVariantKind) {
        let current = islandCompletedSubtasksByVariant[kind] ?? 1
        let next = current >= 3 ? 1 : (current + 1)
        islandCompletedSubtasksByVariant[kind] = next
        islandIsDoneByVariant[kind] = (next >= 3)
        islandReceiptByVariant[kind] = next >= 3 ? "✓ 全部完成" : "进度 \(next)/3"
    }

    public func toggleIslandDone(for kind: DynamicIslandPreviewVariantKind) {
        let nextDone = !(islandIsDoneByVariant[kind] ?? false)
        islandIsDoneByVariant[kind] = nextDone
        islandCompletedSubtasksByVariant[kind] = nextDone ? 3 : 1
        islandReceiptByVariant[kind] = nextDone ? "✓ 已完成" : nil
    }

    public func markIslandDone(for kind: DynamicIslandPreviewVariantKind) {
        islandIsDoneByVariant[kind] = true
        islandCompletedSubtasksByVariant[kind] = 3
        islandReceiptByVariant[kind] = "✓ 已完成"
    }

    public func snoozeIsland15m(for kind: DynamicIslandPreviewVariantKind) {
        islandReceiptByVariant[kind] = "⏰ +15m"
    }

    public func deferIslandMorning(for kind: DynamicIslandPreviewVariantKind) {
        islandReceiptByVariant[kind] = "🌙 明早 08:35"
    }

    public func selectIslandHabitAnchor(_ anchorTime: String, for kind: DynamicIslandPreviewVariantKind) {
        islandAnchorByVariant[kind] = anchorTime
        islandReceiptByVariant[kind] = "已排 \(anchorTime)"
    }
}

@MainActor
public struct TodoUnfoldFourUpPreviewBoard: View {
    @StateObject private var controller = TodoUnfoldFourUpBoardController(initiallyExpanded: true)

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topControlToolbar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

            Divider()

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                switch controller.activeTab {
                case .todoAndVerticalFilter:
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(TodoUnfoldVariantKind.allCases) { kind in
                            variantColumn(for: kind)
                        }
                    }
                    .padding(22)
                case .recorderFiveStageAtmosphere:
                    recorderFiveStageComparisonGrid
                        .padding(22)
                case .dynamicIslandFourVariants:
                    dynamicIslandFourUpComparisonGrid
                        .padding(22)
                }
            }
            .background(controller.colorScheme == .dark ? Color(white: 0.07) : Color(white: 0.94))
        }
        .preferredColorScheme(controller.colorScheme)
    }

    private var topControlToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VoxPocket · 120Hz 原生 SwiftUI 预览窗 (Todo 竖向筛选 · 录音 5 阶段色彩 · 灵动岛 DI-v01..v04)")
                        .font(.headline.bold())
                    Text("100% Native SwiftUI · 4 × 390×844 · Zero-Jump Scale & Continuous 5-Blob RGB Morph")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(PreviewHostTopTab.allCases) { tab in
                        let isSelected = controller.activeTab == tab
                        Button(action: {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                                controller.activeTab = tab
                            }
                        }) {
                            Label(tab.label, systemImage: tab.symbolName)
                                .font(.caption.weight(isSelected ? .bold : .semibold))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.07), in: Capsule())
            }

            HStack(spacing: 14) {
                if controller.activeTab == .recorderFiveStageAtmosphere {
                    HStack(spacing: 4) {
                        Text("录音页 5 阶段色彩流转")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        ForEach(PreviewAtmosphereStageOption.allCases) { option in
                            stageOptionButton(option)
                        }
                    }
                    .padding(4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }

                HStack(spacing: 6) {
                    Text("慢放倍率")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    speedButton(label: "1.0x", rate: 1.0)
                    speedButton(label: "0.5x", rate: 0.5)
                    speedButton(label: "0.25x", rate: 0.25)
                }
                .padding(4)
                .background(Color.primary.opacity(0.06), in: Capsule())

                HStack(spacing: 6) {
                    appearanceButton(label: "Dark", scheme: .dark, icon: "moon.fill")
                    appearanceButton(label: "Light", scheme: .light, icon: "sun.max.fill")
                }
                .padding(4)
                .background(Color.primary.opacity(0.06), in: Capsule())

                Spacer()

                if controller.activeTab == .todoAndVerticalFilter {
                    Button(action: { controller.toggleAllTagTrays() }) {
                        Label(controller.allTagTraysOpen ? "收起 #Tag 托盘" : "展开 #Tag 托盘", systemImage: "tag.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { controller.toggleAllExpanded() }) {
                    Label(
                        controller.allExpanded ? "一键全收起 (Collapse All)" : "一键全展开 (Expand All)",
                        systemImage: controller.allExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stageOptionButton(_ option: PreviewAtmosphereStageOption) -> some View {
        let selected = controller.stageOption == option
        return Button(action: {
            let scale = max(0.2, 1.0 / max(0.2, controller.speedMultiplier))
            withAnimation(.easeInOut(duration: AtmosphereGlass.transitionDuration * scale)) {
                controller.setAllRecorderStages(option)
            }
        }) {
            Text(option.label)
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 2: Recorder Page 5-Stage Continuous Atmosphere Preview Board

    private var recorderFiveStageComparisonGrid: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(0..<4, id: \.self) { bezelIndex in
                let stage = controller.recorderStagesByBezel[bezelIndex] ?? .idle
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("REC-0\(bezelIndex + 1)")
                            .font(.caption.weight(.black).monospaced())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())

                        Text("录音页阶段：\(stage.label)")
                            .font(.subheadline.bold())

                        Spacer()

                        HStack(spacing: 3) {
                            ForEach(PreviewAtmosphereStageOption.allCases) { opt in
                                Button(action: {
                                    let scale = max(0.2, 1.0 / max(0.2, controller.speedMultiplier))
                                    withAnimation(.easeInOut(duration: AtmosphereGlass.transitionDuration * scale)) {
                                        controller.recorderStagesByBezel[bezelIndex] = opt
                                    }
                                }) {
                                    Text(opt.label)
                                        .font(.system(size: 10, weight: stage == opt ? .bold : .regular))
                                        .foregroundStyle(stage == opt ? .white : .secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(stage == opt ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text("移除 .id(status)，5 个 RadialGradient 光团常驻并经 AnimatableRGBVector 连续插值，点击任意阶段零闪断零跳变。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 390, alignment: .leading)

                    recorderPhoneViewport(stage: stage)
                        .environment(\.colorScheme, controller.colorScheme)
                }
                .frame(width: 390)
            }
        }
    }

    private func recorderPhoneViewport(stage: PreviewAtmosphereStageOption) -> some View {
        let sentence: String = {
            switch stage {
            case .idle: "按住底部玻璃说话，松手即刻生成润色笔记。"
            case .listening: "正在聆听你的灵感，松手立即润色…"
            case .transcribing: "把早间散步录下的播客大纲润色后发给搭档确认…"
            case .refining: "正在提炼短标题、标签与习惯提醒时间槽…"
            case .error: "未检测到语音，按住底部麦克风重新说话。"
            }
        }()

        return ZStack(alignment: .bottom) {
            RecorderBackdrop(status: stage.recorderStatus, audioLevel: stage.simulatedAudioLevel)

            VStack(spacing: 0) {
                HStack {
                    Text("9:41")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Spacer()
                    Capsule()
                        .fill(Color.black.opacity(0.86))
                        .frame(width: 126, height: 32)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100")
                    }
                    .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                RecorderSentenceStage(sentence: sentence, copy: {})
                    .frame(height: 360)

                Spacer()
            }

            HStack {
                Image(systemName: "checklist")
                    .font(.title3.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .modifier(RecorderGlassModifier())

                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: stage == .listening ? "stop.fill" : "mic.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(width: 390, height: 844)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.2)
        }
    }

    // MARK: - Tab 3: Dynamic Island & Live Activity 4-Variant 120Hz Interactive Preview Board (DI-v01..v04)

    private var dynamicIslandFourUpComparisonGrid: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(DynamicIslandPreviewVariantKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(kind.badgeCode)
                            .font(.caption.weight(.black).monospaced())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())

                        Text(kind.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                    }

                    Text(kind.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 390, alignment: .leading)

                    dynamicIslandPhoneViewport(for: kind)
                        .environment(\.colorScheme, controller.colorScheme)
                }
                .frame(width: 390)
            }
        }
    }

    private func dynamicIslandPhoneViewport(for kind: DynamicIslandPreviewVariantKind) -> some View {
        let mode = controller.islandModeByVariant[kind] ?? .expanded
        let completedCount = controller.islandCompletedSubtasksByVariant[kind] ?? 1
        let receipt = controller.islandReceiptByVariant[kind]
        let stage = controller.islandPhaseByVariant[kind] ?? .listening
        let accent: Color = {
            switch stage {
            case .listening: Color(.sRGB, red: 0.32, green: 0.74, blue: 0.72, opacity: 1.0)
            case .transcribing: Color(.sRGB, red: 0.34, green: 0.56, blue: 0.90, opacity: 1.0)
            case .refining: Color(.sRGB, red: 0.58, green: 0.50, blue: 0.90, opacity: 1.0)
            case .idle: Color(.sRGB, red: 0.22, green: 0.74, blue: 0.97, opacity: 1.0)
            case .error: Color(.sRGB, red: 0.90, green: 0.46, blue: 0.50, opacity: 1.0)
            }
        }()
        let scale = max(0.15, 1.0 / max(0.15, controller.speedMultiplier))
        let spring = Animation.spring(response: 0.32 * scale, dampingFraction: 0.84)

        return ZStack(alignment: .top) {
            RecorderBackdrop(status: .idle, audioLevel: 0.0)

            VStack(spacing: 12) {
                ZStack(alignment: .top) {
                    HStack {
                        Text("9:41")
                            .font(.caption.weight(.semibold).monospacedDigit())
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "cellularbars")
                            Image(systemName: "wifi")
                            Image(systemName: "battery.100")
                        }
                        .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 37)

                    // Single continuous morphing #000000 Dynamic Island container with per-variant expanded height
                    let effectiveHeight: CGFloat = (mode == .expanded || mode == .lockScreenBanner)
                        ? kind.expandedHeight
                        : mode.targetSize.height
                    ZStack {
                        RoundedRectangle(cornerRadius: mode.cornerRadius, style: .continuous)
                            .fill(Color.black)

                        RoundedRectangle(cornerRadius: mode.cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [accent.opacity(0.65), Color.white.opacity(0.14)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: mode == .expanded ? 1.2 : 0.85
                            )

                        dynamicIslandInterior(
                            kind: kind,
                            mode: mode,
                            accent: accent,
                            stage: stage,
                            completedCount: completedCount,
                            isDone: controller.islandIsDoneByVariant[kind] ?? false,
                            activeAnchor: controller.islandAnchorByVariant[kind] ?? "08:35",
                            receipt: receipt,
                            spring: spring
                        )
                    }
                    .frame(width: mode.targetSize.width, height: effectiveHeight)
                    .clipShape(RoundedRectangle(cornerRadius: mode.cornerRadius, style: .continuous))
                    .shadow(color: accent.opacity(mode == .expanded ? 0.26 : 0.10), radius: 14, y: 6)
                    .onTapGesture {
                        withAnimation(spring) {
                            controller.islandModeByVariant[kind] = (mode == .expanded) ? .compact : .expanded
                        }
                    }
                }
                .padding(.top, 11)

                // Interactive mode switcher bar for 120Hz inspection
                HStack(spacing: 4) {
                    ForEach(DynamicIslandSurfaceBezelMode.allCases) { candidate in
                        let selected = mode == candidate
                        Button(action: {
                            withAnimation(spring) {
                                controller.islandModeByVariant[kind] = candidate
                            }
                        }) {
                            Text(candidate.shortLabel)
                                .font(.system(size: 10, weight: selected ? .bold : .medium).monospaced())
                                .foregroundStyle(selected ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selected ? accent.opacity(0.85) : Color.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(.ultraThinMaterial, in: Capsule())

                TodoUnfoldVariantCardView(
                    variant: .v02,
                    todo: controller.store(for: .v02).todos[0],
                    aiOrder: controller.store(for: .v02).aiOrdersByTodoID[controller.store(for: .v02).todos[0].id],
                    isExpanded: true,
                    expandFraction: 1.0,
                    isTagTrayOpen: false,
                    cascadeStageTwoVisible: true,
                    historicalTags: controller.store(for: .v02).historicalTags,
                    speedMultiplier: controller.speedMultiplier,
                    onToggleExpand: {},
                    onToggleTagTray: {},
                    onCycleStatus: {},
                    onCyclePriority: {},
                    onToggleTag: { _ in },
                    onAddTag: { _ in },
                    onToggleSubtask: { _ in
                        withAnimation(spring) {
                            controller.advanceIslandSubtask(for: kind)
                        }
                    },
                    onUpdateTitle: { _ in },
                    onUpdateSubtaskTitle: { _, _ in },
                    onAppendSubtask: { _ in },
                    onDispatchAI: {
                        controller.store(for: .v02).dispatchTodoToICloudAI(todoID: controller.store(for: .v02).todos[0].id)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .frame(width: 390, height: 844)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.2)
        }
    }

    @ViewBuilder
    private func dynamicIslandInterior(
        kind: DynamicIslandPreviewVariantKind,
        mode: DynamicIslandSurfaceBezelMode,
        accent: Color,
        stage: PreviewAtmosphereStageOption,
        completedCount: Int,
        isDone: Bool,
        activeAnchor: String,
        receipt: String?,
        spring: Animation
    ) -> some View {
        switch mode {
        case .minimal:
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
        case .compact:
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(kind == .diV03 ? stage.label : "P0 走查")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.leading, 12)
                Spacer()
                Text(receipt ?? "\(completedCount)/3")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.trailing, 12)
            }
        case .expanded, .lockScreenBanner:
            switch kind {
            case .diV01:
                // ① DI-v01: Height 112pt Minimal 2-Row Layout (Left [○/✓] Check Circle + P0 + Title + ⏳14:59 | Bottom ONLY [⏰ +15m] & [🌙 明早 08:35 (习惯)], ZERO subtask list & ZERO Done button)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button(action: {
                            withAnimation(spring) { controller.toggleIslandDone(for: kind) }
                        }) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(isDone ? Color.green : accent)
                        }
                        .buttonStyle(.plain)

                        Text("P0")
                            .font(.system(size: 10, weight: .black).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())

                        Text("液态玻璃交互走查")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(isDone ? .white.opacity(0.55) : .white)
                            .strikethrough(isDone, color: .white.opacity(0.45))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(receipt ?? "⏳ 14:59")
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(isDone ? Color.green : accent)
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            withAnimation(spring) { controller.snoozeIsland15m(for: kind) }
                        }) {
                            Text("⏰ +15m")
                                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.13), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            withAnimation(spring) { controller.deferIslandMorning(for: kind) }
                        }) {
                            Text("🌙 明早 08:35 (习惯)")
                                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(accent.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            case .diV02:
                // ② DI-v02: Height 148pt Left-Right Split HStack Layout (Left 118pt: Progress Ring 1/3 + Short Title + [+15m] Chip | Right 224pt: 2 Stacked Subtask Mini-Cards, 3/3 Auto-Completes, ZERO Done button)
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 3)
                                Circle()
                                    .trim(from: 0, to: CGFloat(completedCount) / 3.0)
                                    .stroke(completedCount >= 3 ? Color.green : accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text("\(completedCount)/3")
                                    .font(.system(size: 9.5, weight: .black).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 30, height: 30)

                            Text("P0")
                                .font(.system(size: 9.5, weight: .black).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.85), in: Capsule())
                        }

                        Text("液态玻璃走查")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(completedCount >= 3 ? .white.opacity(0.55) : .white)
                            .strikethrough(completedCount >= 3, color: .white.opacity(0.45))
                            .lineLimit(1)

                        Button(action: {
                            withAnimation(spring) { controller.snoozeIsland15m(for: kind) }
                        }) {
                            Text(receipt ?? "⏰ +15m")
                                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(accent.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 118, alignment: .leading)

                    VStack(spacing: 6) {
                        ForEach(0..<2, id: \.self) { rowIdx in
                            let stepChecked = completedCount > (rowIdx + 1) || (rowIdx == 0 && completedCount >= 2)
                            let stepTitle = rowIdx == 0 ? "验证双按钮底栏手势" : "核对状态与创建时间"
                            Button(action: {
                                withAnimation(spring) { controller.advanceIslandSubtask(for: kind) }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: stepChecked ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(stepChecked ? Color.green : accent)
                                    Text(stepTitle)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(stepChecked ? .white.opacity(0.55) : .white)
                                        .strikethrough(stepChecked, color: .white.opacity(0.45))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .frame(width: 224, alignment: .leading)
                                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 224)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            case .diV03:
                // ③ DI-v03: Height 156pt 4-Stage Waveform Aura + Live AI Extraction Stage (Top: 录音/转译/润色/入库 Stage Switcher | Center: 20 AtmosphereGlass Waveform Bars + #VoxPocket #iOS Bubbles | Bottom: [🎙️ 语音追补] & [✨ AI do it])
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                        Text("四阶段流光")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white)

                        Spacer(minLength: 4)

                        ForEach(
                            [
                                (PreviewAtmosphereStageOption.listening, "录音"),
                                (.transcribing, "转译"),
                                (.refining, "润色"),
                                (.idle, "入库")
                            ],
                            id: \.0
                        ) { opt, label in
                            let isCurrent = stage == opt
                            Button(action: {
                                withAnimation(spring) {
                                    controller.islandPhaseByVariant[kind] = opt
                                }
                            }) {
                                Text(label)
                                    .font(.system(size: 9.5, weight: isCurrent ? .bold : .medium))
                                    .foregroundStyle(isCurrent ? .black : .white.opacity(0.75))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(isCurrent ? accent : Color.white.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        HStack(alignment: .center, spacing: 3) {
                            ForEach(0..<20, id: \.self) { barIdx in
                                let heights: [CGFloat] = [8, 14, 22, 16, 26, 12, 20, 28, 15, 24, 18, 10, 22, 27, 14, 19, 25, 13, 17, 9]
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [accent, Color.purple.opacity(0.85)],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 3.5, height: heights[barIdx % heights.count])
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Spacer(minLength: 4)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("#VoxPocket")
                                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.16), in: Capsule())
                            Text("#iOS · 09:00")
                                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.82))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.10), in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            withAnimation(spring) {
                                controller.islandPhaseByVariant[kind] = .listening
                                controller.islandReceiptByVariant[kind] = "🎙️ 正在语音追补…"
                            }
                        }) {
                            Text("🎙️ 语音追补")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.13), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            withAnimation(spring) {
                                controller.store(for: .v02).dispatchTodoToICloudAI(todoID: controller.store(for: .v02).todos[0].id)
                                controller.islandReceiptByVariant[kind] = "✨ AI 已接单"
                            }
                        }) {
                            Text(receipt ?? "✨ AI do it")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            case .diV04:
                // ④ DI-v04: Height 138pt Horizontal 4-Node Habit Timeline Track Layout (Top: [○/✓] Check Ring + Title + Active Anchor | Middle/Bottom: 🌅 08:35 ━━●━━ ☀️ 12:30 ━━ 🌆 18:30 ━━ 🌙 21:00 Interactive Track)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button(action: {
                            withAnimation(spring) { controller.toggleIslandDone(for: kind) }
                        }) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(isDone ? Color.green : accent)
                        }
                        .buttonStyle(.plain)

                        Text("液态玻璃交互走查")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isDone ? .white.opacity(0.55) : .white)
                            .strikethrough(isDone, color: .white.opacity(0.45))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(receipt ?? "锚点 \(activeAnchor)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.16), in: Capsule())
                    }

                    // 4-Node Horizontal Habit Timeline Track
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            let anchors: [(icon: String, time: String, label: String)] = [
                                ("🌅", "08:35", "早间"),
                                ("☀️", "12:30", "午间"),
                                ("🌆", "18:30", "傍晚"),
                                ("🌙", "21:00", "夜间")
                            ]
                            ForEach(Array(anchors.enumerated()), id: \.offset) { idx, item in
                                let selected = activeAnchor == item.time
                                Button(action: {
                                    withAnimation(spring) {
                                        controller.selectIslandHabitAnchor(item.time, for: kind)
                                    }
                                }) {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle()
                                                .fill(selected ? accent : Color.white.opacity(0.18))
                                                .frame(width: selected ? 14 : 9, height: selected ? 14 : 9)
                                            if selected {
                                                Circle()
                                                    .strokeBorder(Color.white, lineWidth: 2)
                                                    .frame(width: 14, height: 14)
                                            }
                                        }
                                        Text("\(item.icon) \(item.time)")
                                            .font(.system(size: 10, weight: selected ? .bold : .medium).monospacedDigit())
                                            .foregroundStyle(selected ? accent : .white.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)

                                if idx < anchors.count - 1 {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [accent.opacity(0.55), Color.white.opacity(0.18)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(height: 2)
                                        .padding(.bottom, 14)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func speedButton(label: String, rate: Double) -> some View {
        let selected = abs(controller.speedMultiplier - rate) < 0.01
        return Button(action: { controller.speedMultiplier = rate }) {
            Text(label)
                .font(.caption.weight(selected ? .bold : .medium).monospacedDigit())
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func appearanceButton(label: String, scheme: ColorScheme, icon: String) -> some View {
        let selected = controller.colorScheme == scheme
        return Button(action: { controller.colorScheme = scheme }) {
            Label(label, systemImage: icon)
                .font(.caption.weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func variantColumn(for kind: TodoUnfoldVariantKind) -> some View {
        let store = controller.store(for: kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(kind.badgeCode)
                    .font(.caption.weight(.black).monospaced())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())

                Text(kind.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            Text(kind.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 390, alignment: .leading)

            TodoUnfoldVariantPhoneViewport(store: store)
                .environment(\.colorScheme, controller.colorScheme)
        }
        .frame(width: 390)
    }
}

#Preview("4-Up SwiftUI Todo Unfold Board (v01..v04)") {
    TodoUnfoldFourUpPreviewBoard()
        .frame(width: 1680, height: 980)
}

#Preview("v01 · Continuous Morph") {
    TodoUnfoldVariantPhoneViewport(store: TodoUnfoldVariantPreviewStore(variant: .v01, initiallyExpanded: true))
}

#Preview("v02 · Inline Drawer Zero-Header-Shift") {
    TodoUnfoldVariantPhoneViewport(store: TodoUnfoldVariantPreviewStore(variant: .v02, initiallyExpanded: true))
}

#Preview("v03 · Spatial Hero Elevation") {
    TodoUnfoldVariantPhoneViewport(store: TodoUnfoldVariantPreviewStore(variant: .v03, initiallyExpanded: true))
}

#Preview("v04 · Two-Stage Staggered Cascade") {
    TodoUnfoldVariantPhoneViewport(store: TodoUnfoldVariantPreviewStore(variant: .v04, initiallyExpanded: true))
}
