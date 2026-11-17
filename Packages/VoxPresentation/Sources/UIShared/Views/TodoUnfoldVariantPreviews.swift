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
        case .v01: "Inline Horizontal Tag Rail · 单轨内联标签条 (v02收起 + v03子任务)"
        case .v02: "Unified Clipped Tag Shelf · 同框卷轴标签架 (v02收起 + v03子任务)"
        case .v03: "Inline Morphing Pill Editor · 原位胶囊伸展编辑 (v02收起 + v03子任务)"
        case .v04: "Flat Toggle Tag Matrix · 一目了然平铺芯片槽 (v02收起 + v03子任务)"
        }
    }

    public var summary: String {
        switch self {
        case .v01:
            "第 1 行独占标题（15.5pt<->18pt 平滑缩放）；第 2 行固定 [状态] [P0] [>=2子步进度] [今天 17:31] + 末尾常驻翻转箭头；Filter 移至左下返回按钮正上方 Liquid Glass 胶囊；展开抽屉内 Linear 独占一行 + 单轨内联标签条。"
        case .v02:
            "【Owner 终局选定方案】第 1 行独占标题（15.5pt<->18pt 平滑缩放）；第 2 行固定 [状态] [P0] [>=2子步进度] [今天 17:31] + 末尾常驻翻转箭头；左下返回按钮正上方 Liquid Glass Filter；展开抽屉采用同框裁剪标签架 + v03 子任务微卡 + Linear 独立行。"
        case .v03:
            "第 1 行独占标题（15.5pt<->18pt 平滑缩放）；第 2 行固定 [状态] [P0] [>=2子步进度] [今天 17:31] + 末尾常驻翻转箭头；左下返回按钮正上方 Liquid Glass Filter；展开抽屉含原位胶囊横向伸展标签编辑 + Linear 独立行。"
        case .v04:
            "第 1 行独占标题（15.5pt<->18pt 平滑缩放）；第 2 行固定 [状态] [P0] [>=2子步进度] [今天 17:31] + 末尾常驻翻转箭头；左下返回按钮正上方 Liquid Glass Filter；展开抽屉含平铺一键切换标签芯片槽 + Linear 独立行。"
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
    @Published public var selectedFilter: String = "全部"
    @Published public var speedMultiplier: Double = 1.0
    @Published public var cascadeStageTwoVisible: Bool = false
    @Published public var recorderStatus: RecorderStatus = .idle
    @Published public var audioLevel: Float = 0.0

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
            RecorderBackdrop(status: store.recorderStatus, audioLevel: store.audioLevel)

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
                                    onAppendSubtask: { title in store.appendSubtask(todoID: todo.id, title: title) }
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

    private var bottomLeadingFilterGlassStrip: some View {
        HStack(spacing: 4) {
            filterChip(title: "全部", count: store.todos.count, isSelected: store.selectedFilter == "全部")
            filterChip(title: "待处理", count: store.todos.filter { $0.executionState == .inbox }.count, isSelected: store.selectedFilter == "待处理")
            filterChip(title: "AI 执行中", count: store.todos.filter { $0.executionState == .running }.count, isSelected: store.selectedFilter == "AI 执行中")
            filterChip(title: "已完成", count: store.todos.filter { $0.executionState == .done }.count, isSelected: store.selectedFilter == "已完成")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .modifier(RecorderGlassModifier())
    }

    private func filterChip(title: String, count: Int, isSelected: Bool) -> some View {
        Button(action: { store.selectedFilter = title }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                Text(String(count))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
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

    private var bottomDualGlassBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                bottomLeadingFilterGlassStrip
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

    @Namespace private var morphNamespace
    @State private var draftTitle: String = ""
    @State private var draftDescription: String = ""
    @State private var newTagText: String = ""
    @State private var newSubtaskText: String = ""

    public init(
        variant: TodoUnfoldVariantKind,
        todo: VoiceTodo,
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
        onAppendSubtask: @escaping (String) -> Void
    ) {
        self.variant = variant
        self.todo = todo
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
    }

    // MARK: - Persistent v02 Header (Row 1: Full-Width Title ONLY with Smooth v03 Font-Size Scaling | Row 2: Status + Priority + Conditional Subtask Count (>=2) + Timestamp + Spacer + Persistent Rotating Chevron)

    private var v02HeaderRow1TitleAndTime: some View {
        HStack(alignment: .center, spacing: 0) {
            if isExpanded {
                TextField("待办短标题", text: $draftTitle)
                    .modifier(AnimatableTitleFontModifier(progress: expandFraction))
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .onSubmit {
                        onUpdateTitle(draftTitle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(todo.title)
                    .modifier(AnimatableTitleFontModifier(progress: expandFraction))
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var v02HeaderRow2StatusAndPriority: some View {
        HStack(spacing: 6) {
            // 1. Status capsule: ALWAYS displays icon + text label at fixed 24pt height in both collapsed and expanded states!
            fixedStatusCapsule

            // 2. Priority capsule: fixed 24pt height in both states; when collapsed, hit-testing is disabled so tapping priority expands the card!
            fixedPriorityCapsule
                .allowsHitTesting(isExpanded)

            // 3. Conditional Subtask Progress: ONLY shown when todo.subtasks.count >= 2, placed to the LEFT of timestamp!
            if totalSubtaskCount >= 2 {
                compactProgressBadge
                    .allowsHitTesting(false)
            }

            // 4. Timestamp ('今天 17:31')
            timestampLabel
                .allowsHitTesting(false)

            // 5. Spacer
            Spacer(minLength: 4)

            // 6. Persistent trailing chevron.down (ALWAYS visible in both collapsed and expanded states, rotating 180 deg on expand)
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
        .frame(height: 24)
    }

    private var dedicatedLinearAndReminderRow: some View {
        HStack(spacing: 8) {
            linearActionCapsule

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

    private var linearActionCapsule: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.right.circle")
                .font(.system(size: 11, weight: .bold))
            Text(todo.externalSync?.externalID ?? "Linear")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: - 4 Distinct Zero-Overlap Tag Designs Across `v01..v04` (No `.move(edge: .top)` Overlap!)

    @ViewBuilder
    private var zeroOverlapTagSectionForVariant: some View {
        switch variant {
        case .v01:
            v01InlineHorizontalTagRail
        case .v02:
            v02UnifiedClippedTagShelf
        case .v03:
            v03InlineMorphingPillEditor
        case .v04:
            v04FlatToggleTagMatrix
        }
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

@MainActor
public final class TodoUnfoldFourUpBoardController: ObservableObject {
    @Published public var speedMultiplier: Double = 1.0 {
        didSet {
            for store in stores.values {
                store.speedMultiplier = speedMultiplier
            }
        }
    }
    @Published public var stageOption: PreviewAtmosphereStageOption = .idle {
        didSet {
            for store in stores.values {
                store.recorderStatus = stageOption.recorderStatus
                store.audioLevel = stageOption.simulatedAudioLevel
            }
        }
    }
    @Published public var colorScheme: ColorScheme = .dark
    @Published public var allExpanded: Bool = true
    @Published public var allTagTraysOpen: Bool = false

    public let stores: [TodoUnfoldVariantKind: TodoUnfoldVariantPreviewStore]

    public init(initiallyExpanded: Bool = true) {
        self.allExpanded = initiallyExpanded
        var map: [TodoUnfoldVariantKind: TodoUnfoldVariantPreviewStore] = [:]
        for kind in TodoUnfoldVariantKind.allCases {
            map[kind] = TodoUnfoldVariantPreviewStore(variant: kind, initiallyExpanded: initiallyExpanded)
        }
        self.stores = map
    }

    public func store(for kind: TodoUnfoldVariantKind) -> TodoUnfoldVariantPreviewStore {
        stores[kind]!
    }

    public func toggleAllExpanded() {
        allExpanded.toggle()
        for kind in TodoUnfoldVariantKind.allCases {
            stores[kind]?.setExpanded(allExpanded, tagTrayOpen: allTagTraysOpen, animated: true)
        }
    }

    public func toggleAllTagTrays() {
        allTagTraysOpen.toggle()
        for kind in TodoUnfoldVariantKind.allCases {
            stores[kind]?.toggleTagTray()
        }
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
                HStack(alignment: .top, spacing: 20) {
                    ForEach(TodoUnfoldVariantKind.allCases) { kind in
                        variantColumn(for: kind)
                    }
                }
                .padding(22)
            }
            .background(controller.colorScheme == .dark ? Color(white: 0.07) : Color(white: 0.94))
        }
        .preferredColorScheme(controller.colorScheme)
    }

    private var topControlToolbar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VoxPocket · Todo 原地展开 4 套真 SwiftUI 动效预览台 (v01–v04)")
                    .font(.headline.bold())
                Text("100% Native SwiftUI · 4 × 390×844 · 120Hz Interactive Host")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("阶段氛围")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                ForEach(PreviewAtmosphereStageOption.allCases) { option in
                    stageOptionButton(option)
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.06), in: Capsule())

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

            Button(action: { controller.toggleAllTagTrays() }) {
                Label(controller.allTagTraysOpen ? "收起 #Tag 托盘" : "展开 #Tag 托盘", systemImage: "tag.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

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

    private func stageOptionButton(_ option: PreviewAtmosphereStageOption) -> some View {
        let selected = controller.stageOption == option
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.35)) {
                controller.stageOption = option
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
