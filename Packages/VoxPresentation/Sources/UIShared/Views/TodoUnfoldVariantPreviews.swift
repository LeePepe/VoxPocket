import SwiftUI
import CoreModels

/// Four distinct 100% real SwiftUI Todo card in-place unfold choreographies (`v01..v04`)
/// featuring ultra-compact `52–68pt` collapsed cards, concise short titles (`<= 14` chars),
/// and smooth `matchedGeometryEffect` transitions into `description` + metadata + subtasks.
public enum TodoUnfoldVariantKind: String, CaseIterable, Identifiable, Sendable {
    case v01
    case v02
    case v03
    case v04

    public var id: String { rawValue }

    public var badgeCode: String { rawValue.uppercased() }

    public var title: String {
        switch self {
        case .v01: "Single-Line Pill Rail · 单行超紧凑胶囊轨 (~52pt)"
        case .v02: "Compact Two-Line Micro-Card · 头部零位移双行微卡 (~62pt)"
        case .v03: "Description Peek & Spatial Unfold · 单行微预览景深展开 (~66pt)"
        case .v04: "Staggered Minimal Strip · 极简横条两段式瀑布展开 (~54pt)"
        }
    }

    public var summary: String {
        switch self {
        case .v01:
            "收起态压至 ~52pt 单行胶囊轨（状态圆环 + <=14字极简短标题 + P0 + #VoxPocket + 1/3），隐藏 + 与子任务；展开时标题平滑放大至 17.5pt，Status/Priority/Tag 经 matchedGeometryEffect 零跳变连续过渡，下方生长出可编辑 Description 详情块与子任务树。"
        case .v02:
            "收起态上下内边距压至 10pt（~62pt 紧凑双行微卡），第 1 行短标题 + 1/3 + 17:31，第 2 行 22pt 微轨共排 [待处理] [P0] · #VoxPocket #iOS；展开时第 1、2 行 0px 零位移，末端平滑滑出 + 与 Linear，下方抽屉展开 Description 与子任务。"
        case .v03:
            "收起态（~66pt）第 1 行展示状态点 + 短标题 + P0 + #VoxPocket + 17:31，第 2 行带 12pt 单行浅色 Description 截断微预览；展开时卡片微抬升，单行 Description 经 matchedGeometryEffect 平滑伸展为多行可编辑详情段，并显现完整操作栏与分步卡。"
        case .v04:
            "收起态为 ~54pt 极简高密度清单条（间距 8pt，一屏容纳 7–8 条待办）；点击后第 1 阶段（0–130ms）外框撑开并经 matchedGeometryEffect 原位伸展 Status/Priority/Tag 胶囊，第 2 阶段（50–230ms）瀑布式滑入 Description 详情块、+ 标签触发器与子任务。"
        }
    }

    public func spring(speedMultiplier: Double) -> Animation {
        let scale = max(0.1, 1.0 / max(0.1, speedMultiplier))
        switch self {
        case .v01:
            return .spring(response: 0.32 * scale, dampingFraction: 0.88)
        case .v02:
            return .spring(response: 0.28 * scale, dampingFraction: 0.96)
        case .v03:
            return .spring(response: 0.38 * scale, dampingFraction: 0.86)
        case .v04:
            return .spring(response: 0.30 * scale, dampingFraction: 0.90)
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
            RecorderBackdrop(status: .idle, audioLevel: 0)

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
                        filterPillRow

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
                    .padding(.bottom, 92)
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

    private var filterPillRow: some View {
        HStack(spacing: AppTheme.Space.sm) {
            filterChip(title: "全部", count: store.todos.count, isSelected: true)
            filterChip(title: "待处理", count: store.todos.filter { $0.executionState == .inbox }.count, isSelected: false)
            filterChip(title: "AI 执行中", count: store.todos.filter { $0.executionState == .running }.count, isSelected: false)
            filterChip(title: "已完成", count: store.todos.filter { $0.executionState == .done }.count, isSelected: false)
        }
    }

    private func filterChip(title: String, count: Int, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
            Text(String(count))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : AppTheme.surfaceCard,
            in: Capsule()
        )
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
    }

    private var bottomDualGlassBar: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                }

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
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .padding(.top, 4)
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

    private var primaryTag: String {
        todo.tags.first ?? "#VoxPocket"
    }

    private var horizontalPadding: CGFloat {
        if !isExpanded {
            return 12
        }
        return variant == .v03 ? 16 : 14
    }

    private var verticalPadding: CGFloat {
        if !isExpanded {
            switch variant {
            case .v01: return 11 // ~52pt single-line pill rail
            case .v02: return 9  // ~62pt compact two-line micro-card
            case .v03: return 10 // ~66pt description peek card
            case .v04: return 11 // ~54pt staggered minimal strip
            }
        }
        return variant == .v03 ? 14 : 12
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 8 : 4) {
            switch variant {
            case .v01:
                v01CardContent
            case .v02:
                v02CardContent
            case .v03:
                v03CardContent
            case .v04:
                v04CardContent
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous)
                .strokeBorder(
                    isExpanded
                        ? Color.accentColor.opacity(variant == .v03 ? 0.52 : 0.34)
                        : Color.primary.opacity(0.06),
                    lineWidth: isExpanded ? (variant == .v03 ? 1.4 : 1.1) : 0.8
                )
        }
        .shadow(
            color: Color.black.opacity(variant == .v03 && isExpanded ? 0.16 : 0.03),
            radius: variant == .v03 && isExpanded ? 14 : 4,
            y: variant == .v03 && isExpanded ? 6 : 1
        )
        .scaleEffect(variant == .v03 && isExpanded ? 1.01 : 1.0)
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

    // MARK: - v01: Single-Line Pill Rail (~52pt Collapsed -> Rich Unfold)
    @ViewBuilder
    private var v01CardContent: some View {
        if !isExpanded {
            // Collapsed (~52pt): Single horizontal rail! Status circle + short title (15pt, 1 line) + P0 + #Tag + 1/3 + 17:31
            HStack(spacing: 7) {
                compactStatusCapsule(showLabel: false)
                    .matchedGeometryEffect(id: "status-\(todo.id)", in: morphNamespace)

                Button(action: onToggleExpand) {
                    Text(todo.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "title-\(todo.id)", in: morphNamespace)

                compactPriorityCapsule
                    .matchedGeometryEffect(id: "priority-\(todo.id)", in: morphNamespace)

                compactTagChip(primaryTag)
                    .matchedGeometryEffect(id: "tag-\(primaryTag)-\(todo.id)", in: morphNamespace)

                compactProgressBadge
                    .matchedGeometryEffect(id: "progress-\(todo.id)", in: morphNamespace)
            }
            .frame(minHeight: 28)
        } else {
            // Expanded: Title scales to 17.5pt bold; description unfolds below; Row 3 shows Status · Priority · 今天 17:31 · 🔔 09:00 · Linear; Row 4 shows #Tags [+]; Row 5 shows subtasks
            HStack(alignment: .center, spacing: 8) {
                Button(action: onToggleExpand) {
                    Text(todo.title)
                        .font(.system(size: 17.5, weight: .bold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "title-\(todo.id)", in: morphNamespace)

                compactProgressBadge
                    .matchedGeometryEffect(id: "progress-\(todo.id)", in: morphNamespace)
            }

            if !todo.description.isEmpty {
                expandedDescriptionEditorBlock
                    .opacity(expandFraction)
            }

            HStack(spacing: 6) {
                compactStatusCapsule(showLabel: true)
                    .matchedGeometryEffect(id: "status-\(todo.id)", in: morphNamespace)

                compactPriorityCapsule
                    .matchedGeometryEffect(id: "priority-\(todo.id)", in: morphNamespace)

                timestampLabel

                if todo.scheduledAt != nil {
                    reminderMicroBadge
                }

                Spacer(minLength: 4)

                linearActionCapsule
            }
            .opacity(expandFraction)

            expandedTagsAndPlusRow(matchedPrimaryTag: primaryTag)
                .opacity(expandFraction)

            if isTagTrayOpen {
                inlineTagTrayView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().opacity(expandFraction)

            v01ContinuousSubtaskTree
                .opacity(min(1.0, expandFraction * 1.15))
        }
    }

    // MARK: - v02: Compact Two-Line Micro-Card (Zero Header Shift · ~62pt Collapsed)
    @ViewBuilder
    private var v02CardContent: some View {
        // Line 1 (Locked at 0px vertical shift between collapsed & expanded): Short title (15.5pt) + 1/3 + 今天 17:31
        HStack(alignment: .center, spacing: 8) {
            Button(action: onToggleExpand) {
                Text(todo.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            compactProgressBadge

            timestampLabel
        }
        .frame(height: 20)

        // Line 2 (22pt micro-rail, 0px vertical shift): [○ 待处理] [P0] · #VoxPocket #iOS (+ and Linear smoothly appear at end on expand)
        HStack(spacing: 5) {
            compactStatusCapsule(showLabel: true)

            compactPriorityCapsule

            ForEach(todo.tags.prefix(isExpanded ? 3 : 2), id: \.self) { tag in
                compactTagChip(tag)
            }

            if isExpanded {
                plusTagTriggerButton
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 2)

            if isExpanded {
                linearActionCapsule
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(minHeight: 22)

        if isExpanded && isTagTrayOpen {
            inlineTagTrayView
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if isExpanded && expandFraction > 0.01 {
            VStack(alignment: .leading, spacing: 7) {
                Divider()

                if !todo.description.isEmpty {
                    expandedDescriptionEditorBlock
                }

                v02ZeroHeaderShiftDrawer
            }
            .opacity(expandFraction)
        }
    }

    // MARK: - v03: Description Peek & Spatial Unfold (~66pt Collapsed -> Spatial Hero Unfold)
    @ViewBuilder
    private var v03CardContent: some View {
        if !isExpanded {
            // Line 1: Status capsule + short title (15.5pt) + P0 + #VoxPocket + 17:31
            HStack(spacing: 6) {
                compactStatusCapsule(showLabel: false)
                    .matchedGeometryEffect(id: "status-\(todo.id)", in: morphNamespace)

                Button(action: onToggleExpand) {
                    Text(todo.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "title-\(todo.id)", in: morphNamespace)

                compactPriorityCapsule
                    .matchedGeometryEffect(id: "priority-\(todo.id)", in: morphNamespace)

                compactTagChip(primaryTag)
                    .matchedGeometryEffect(id: "tag-\(primaryTag)-\(todo.id)", in: morphNamespace)

                timestampLabel
                    .matchedGeometryEffect(id: "time-\(todo.id)", in: morphNamespace)
            }
            .frame(height: 22)

            // Line 2: 12pt single-line muted preview of todo.description
            if !todo.description.isEmpty {
                Button(action: onToggleExpand) {
                    Text(todo.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "desc-\(todo.id)", in: morphNamespace)
            }
        } else {
            // Expanded Spatial Hero: Title + progress, then full multi-line editable description (matchedGeometryEffect from 1-line peek)
            HStack(alignment: .center, spacing: 8) {
                Button(action: onToggleExpand) {
                    Text(todo.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "title-\(todo.id)", in: morphNamespace)

                compactProgressBadge
            }

            if !todo.description.isEmpty {
                expandedDescriptionEditorBlock
                    .matchedGeometryEffect(id: "desc-\(todo.id)", in: morphNamespace)
            }

            HStack(spacing: 6) {
                compactStatusCapsule(showLabel: true)
                    .matchedGeometryEffect(id: "status-\(todo.id)", in: morphNamespace)

                compactPriorityCapsule
                    .matchedGeometryEffect(id: "priority-\(todo.id)", in: morphNamespace)

                timestampLabel
                    .matchedGeometryEffect(id: "time-\(todo.id)", in: morphNamespace)

                if todo.scheduledAt != nil {
                    reminderMicroBadge
                }

                Spacer(minLength: 4)

                linearActionCapsule
            }

            expandedTagsAndPlusRow(matchedPrimaryTag: primaryTag)

            if isTagTrayOpen {
                inlineTagTrayView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().opacity(expandFraction)

            v03SpatialHeroSubtaskCards
                .opacity(min(1.0, expandFraction * 1.15))
        }
    }

    // MARK: - v04: Staggered Minimal Strip (~54pt Collapsed -> Two-Stage Cascade Unfold)
    @ViewBuilder
    private var v04CardContent: some View {
        if !isExpanded {
            // Collapsed (~54pt): High-density strip: [○] 液态玻璃交互走查   #VoxPocket  P0  今天 17:31
            HStack(spacing: 7) {
                compactStatusCapsule(showLabel: false)
                    .matchedGeometryEffect(id: "status-\(todo.id)", in: morphNamespace)

                Button(action: onToggleExpand) {
                    Text(todo.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "title-\(todo.id)", in: morphNamespace)

                compactTagChip(primaryTag)
                    .matchedGeometryEffect(id: "tag-\(primaryTag)-\(todo.id)", in: morphNamespace)

                compactPriorityCapsule
                    .matchedGeometryEffect(id: "priority-\(todo.id)", in: morphNamespace)

                timestampLabel
                    .matchedGeometryEffect(id: "time-\(todo.id)", in: morphNamespace)
            }
            .frame(minHeight: 28)
        } else {
            // Stage 1 (0–130ms): Container expands and morphs Status, Priority, #Tag, and 17:31 into expanded header rows
            HStack(alignment: .center, spacing: 8) {
                Button(action: onToggleExpand) {
                    Text(todo.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "title-\(todo.id)", in: morphNamespace)

                compactProgressBadge
            }

            HStack(spacing: 6) {
                compactStatusCapsule(showLabel: true)
                    .matchedGeometryEffect(id: "status-\(todo.id)", in: morphNamespace)

                compactPriorityCapsule
                    .matchedGeometryEffect(id: "priority-\(todo.id)", in: morphNamespace)

                timestampLabel
                    .matchedGeometryEffect(id: "time-\(todo.id)", in: morphNamespace)

                Spacer(minLength: 4)

                linearActionCapsule
            }

            // Stage 2 (50–230ms): Cascades description block, + tag trigger, and staggered subtask rows
            if !todo.description.isEmpty {
                expandedDescriptionEditorBlock
                    .opacity(cascadeStageTwoVisible ? 1.0 : 0.0)
                    .offset(y: cascadeStageTwoVisible ? 0 : -5)
            }

            expandedTagsAndPlusRow(matchedPrimaryTag: primaryTag)
                .opacity(cascadeStageTwoVisible ? 1.0 : 0.25)

            if isTagTrayOpen {
                inlineTagTrayView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .opacity(cascadeStageTwoVisible ? 1.0 : 0.0)

            v04TwoStageStaggeredCascade
        }
    }

    // MARK: - Shared Persistent Micro-Components (Zero Shape Jump)

    private func compactStatusCapsule(showLabel: Bool) -> some View {
        Button(action: onCycleStatus) {
            HStack(spacing: showLabel ? 4 : 0) {
                Image(systemName: statusSymbol)
                    .font(.caption2.weight(.bold))
                if showLabel {
                    Text(statusTitle)
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, showLabel ? 8 : 6)
            .padding(.vertical, 4)
            .frame(minHeight: 22)
            .background(statusColor.opacity(0.15), in: Capsule())
        }
        .buttonStyle(AppPressableButtonStyle())
    }

    private var compactPriorityCapsule: some View {
        Button(action: onCyclePriority) {
            Text(todo.priority.rawValue)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(priorityColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .frame(minHeight: 22)
                .background(priorityColor.opacity(0.15), in: Capsule())
        }
        .buttonStyle(AppPressableButtonStyle())
    }

    private func compactTagChip(_ tag: String) -> some View {
        Button(action: { onToggleTag(tag) }) {
            Text(tag)
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(minHeight: 22)
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

    private func expandedTagsAndPlusRow(matchedPrimaryTag: String) -> some View {
        TodoUnfoldWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(todo.tags.prefix(3), id: \.self) { tag in
                if tag == matchedPrimaryTag {
                    compactTagChip(tag)
                        .matchedGeometryEffect(id: "tag-\(tag)-\(todo.id)", in: morphNamespace)
                } else {
                    compactTagChip(tag)
                }
            }
            plusTagTriggerButton
        }
    }

    private var plusTagTriggerButton: some View {
        Button(action: onToggleTagTray) {
            Image(systemName: isTagTrayOpen ? "chevron.up" : "plus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(
                    AppTheme.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.7)
                }
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
            .frame(width: 12, height: 12)

            Text("\(completedSubtaskCount)/\(totalSubtaskCount)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(minHeight: 22)
        .background(AppTheme.surfaceElevated, in: Capsule())
    }

    private var timestampLabel: some View {
        Text("今天 17:31")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var reminderMicroBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "bell.fill")
                .font(.caption2.weight(.bold))
            Text("明早 09:00")
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(minHeight: 22)
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
                .font(.caption2.weight(.bold))
            Text(todo.externalSync?.externalID ?? "Linear")
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 22)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: Inline Single-Box Tag Tray
    private var inlineTagTrayView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TodoUnfoldWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(historicalTags.prefix(4), id: \.self) { candidate in
                    let selected = todo.tags.contains(candidate)
                    Button(action: { onToggleTag(candidate) }) {
                        HStack(spacing: 3) {
                            Image(systemName: selected ? "checkmark" : "plus")
                                .font(.caption2.weight(.bold))
                            Text(candidate)
                                .font(.caption2.weight(selected ? .semibold : .regular).monospacedDigit())
                        }
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            selected ? Color.accentColor.opacity(0.14) : AppTheme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    selected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.20),
                                    lineWidth: 0.8
                                )
                        }
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
        .padding(9)
        .background(
            AppTheme.surfacePrimary.opacity(0.68),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.8)
        }
    }

    // MARK: Subtask Body per Variant (`v01..v04`)
    @ViewBuilder
    private var subtaskDrawerBody: some View {
        switch variant {
        case .v01:
            v01ContinuousSubtaskTree
        case .v02:
            v02ZeroHeaderShiftDrawer
        case .v03:
            v03SpatialHeroSubtaskCards
        case .v04:
            v04TwoStageStaggeredCascade
        }
    }

    private var v01ContinuousSubtaskTree: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Color.accentColor.opacity(0.30))
                .padding(.vertical, 4)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(todo.subtasks) { subtask in
                    subtaskBranchRow(subtask: subtask)
                }
                addSubtaskInputRow
            }
        }
    }

    private var v02ZeroHeaderShiftDrawer: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Color.accentColor.opacity(0.28))
                .padding(.vertical, 4)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(todo.subtasks) { subtask in
                    subtaskBranchRow(subtask: subtask)
                }
                addSubtaskInputRow
            }
        }
        .scaleEffect(x: 1.0, y: max(0.01, expandFraction), anchor: .top)
        .clipped()
    }

    private var v03SpatialHeroSubtaskCards: some View {
        VStack(alignment: .leading, spacing: 7) {
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

    private var v04TwoStageStaggeredCascade: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Color.accentColor.opacity(0.32))
                .padding(.vertical, 4)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(todo.subtasks.enumerated()), id: \.element.id) { idx, subtask in
                    let stageProgress: Double = {
                        if !cascadeStageTwoVisible { return 0.0 }
                        let delay = Double(idx) * 0.14
                        return min(1.0, max(0.0, (expandFraction - delay) / max(0.2, 1.0 - delay)))
                    }()
                    subtaskBranchRow(subtask: subtask)
                        .opacity(stageProgress)
                        .offset(y: (1.0 - stageProgress) * -6.0)
                        .animation(
                            variant.spring(speedMultiplier: speedMultiplier)
                                .delay(Double(idx) * (0.035 / max(0.15, speedMultiplier))),
                            value: cascadeStageTwoVisible
                        )
                }

                addSubtaskInputRow
                    .opacity(cascadeStageTwoVisible ? 1.0 : 0.0)
            }
        }
    }

    private func subtaskBranchRow(subtask: VoiceTodoSubtask) -> some View {
        Button(action: { onToggleSubtask(subtask.id) }) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(subtask.isCompleted ? .green : .secondary)

                Text(subtask.title)
                    .font(.footnote)
                    .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                    .strikethrough(subtask.isCompleted, color: .secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

@MainActor
public final class TodoUnfoldFourUpBoardController: ObservableObject {
    @Published public var speedMultiplier: Double = 1.0 {
        didSet {
            for store in stores.values {
                store.speedMultiplier = speedMultiplier
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

            HStack(spacing: 6) {
                Text("慢放倍率")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                speedButton(label: "1.0x 正常", rate: 1.0)
                speedButton(label: "0.5x 慢放", rate: 0.5)
                speedButton(label: "0.35x 慢放", rate: 0.35)
                speedButton(label: "0.25x 逐帧", rate: 0.25)
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
