import SwiftUI
import CoreModels

/// Four distinct 100% real SwiftUI Todo card in-place unfold choreographies (`v01..v04`).
public enum TodoUnfoldVariantKind: String, CaseIterable, Identifiable, Sendable {
    case v01
    case v02
    case v03
    case v04

    public var id: String { rawValue }

    public var badgeCode: String { rawValue.uppercased() }

    public var title: String {
        switch self {
        case .v01: "Continuous Morph · 单树连续几何变形"
        case .v02: "Inline Drawer · 头部零位移纯下推抽屉"
        case .v03: "Spatial Hero Elevation · 景深微抬升与分步卡"
        case .v04: "Two-Stage Cascade · 两段式错峰瀑布展开"
        }
    }

    public var summary: String {
        switch self {
        case .v01:
            "单树持久化 Header，标题字重与字号连续平滑插值，Status · Priority · 今天 17:31 原位锚定零跳变，#Tag + 下方内联展开标签托盘与垂直细线子任务树。"
        case .v02:
            "收起态与展开态的卡片头部（Title + Status/Priority/时间 + #Tag + 行）像素坐标 100% 锁定不动（0px 位移），仅在底部通过顶部锚点弹簧抽屉纯净展开子任务与 Linear 操作。"
        case .v03:
            "点击展开时卡片以高阻尼弹簧（response: 0.38, damping: 0.86）微幅抬升阴影与亮色描边，子任务化作独立圆角微卡片，未选中兄弟卡片柔和退后至 0.78 透明度。"
        case .v04:
            "两段式相位编排：第 1 阶段（0–120ms）外框撑开并显现右侧 Linear 与收起按钮；第 2 阶段（60–260ms）子任务分支按 35ms 梯次自上而下错峰滑入。"
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
        let firstID = UUID(uuidString: "11111111-2222-3333-4444-555555555501") ?? UUID()
        let secondID = UUID(uuidString: "11111111-2222-3333-4444-555555555502") ?? UUID()
        let thirdID = UUID(uuidString: "11111111-2222-3333-4444-555555555503") ?? UUID()

        self.todos = [
            VoiceTodo(
                id: firstID,
                title: "整理下周设计评审要展示的液态玻璃交互走查清单",
                taskPrompt: "整理下周设计评审要展示的液态玻璃交互走查清单",
                rawTranscript: "整理下周设计评审要展示的液态玻璃交互走查清单",
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
                externalSync: ExternalTodoSyncMetadata(provider: "linear", externalID: "TIA-508"),
                createdAt: fixedTimestamp,
                updatedAt: fixedTimestamp
            ),
            VoiceTodo(
                id: secondID,
                title: "把早间散步录下的播客大纲润色后发给搭档确认",
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
                title: "验证 Apple Watch 离线语音同步至待办收件箱",
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
                let delayMs = Int(85.0 / max(0.15, speedMultiplier))
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
                    VStack(alignment: .leading, spacing: AppTheme.Space.md) {
                        filterPillRow

                        VStack(spacing: store.variant == .v03 ? 16 : AppTheme.Space.md) {
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
                                    cascadeStageTwoVisible: store.cascadeStageTwoVisible || (interpolationProgress ?? 0) > 0.32,
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
                                    onUpdateSubtaskTitle: { subID, title in store.updateSubtaskTitle(todoID: todo.id, subtaskID: subID, title: title) },
                                    onAppendSubtask: { title in store.appendSubtask(todoID: todo.id, title: title) }
                                )
                                .opacity(siblingDimmed ? 0.78 : 1.0)
                                .scaleEffect(siblingDimmed ? 0.985 : 1.0)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Space.lg)
                    .padding(.top, AppTheme.Space.xs)
                    .padding(.bottom, 96)
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
                .frame(width: 40, height: 40)
                .background(AppTheme.surfaceCard, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                }
        }
    }

    private var filterPillRow: some View {
        HStack(spacing: AppTheme.Space.sm) {
            filterChip(title: "全部", count: 3, isSelected: true)
            filterChip(title: "待处理", count: 1, isSelected: false)
            filterChip(title: "AI 执行中", count: 1, isSelected: false)
            filterChip(title: "已完成", count: 1, isSelected: false)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
                .frame(width: 50, height: 50)
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
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.accentColor.opacity(0.28), radius: 10, y: 4)

                Image(systemName: "mic.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .padding(.top, 6)
    }
}

// MARK: - Individual Variant Card (`v01..v04`)

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
    public let onUpdateSubtaskTitle: (UUID, String) -> Void
    public let onAppendSubtask: (String) -> Void

    @State private var draftTitle: String = ""
    @State private var newTagText: String = ""
    @State private var newSubtaskText: String = ""

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

    private var titleFontSize: CGFloat {
        switch variant {
        case .v01:
            return 17.0 + CGFloat(expandFraction) * 2.5
        case .v02:
            // v02 Zero-Header-Shift: locked at 17pt so the header never reflows or jumps even 1px
            return 17.0
        case .v03:
            return 17.0 + CGFloat(expandFraction) * 2.0
        case .v04:
            return 17.0 + CGFloat(expandFraction) * 1.5
        }
    }

    private var cardVerticalSpacing: CGFloat {
        switch variant {
        case .v03:
            return 8.0 + CGFloat(expandFraction) * 4.0
        default:
            return AppTheme.Space.sm
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: cardVerticalSpacing) {
            row1TitleAndProgress

            row2UnifiedMetadataCapsules

            row3PersistentTagsAndPlus

            if isTagTrayOpen {
                inlineTagTrayView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isExpanded && expandFraction > 0.01 {
                Divider()
                    .opacity(expandFraction)

                subtaskDrawerBody
                    .opacity(min(1.0, expandFraction * 1.15))
            }
        }
        .padding(variant == .v03 && isExpanded ? 18 : AppTheme.Space.lg)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    isExpanded
                        ? Color.accentColor.opacity(variant == .v03 ? 0.52 : 0.34)
                        : Color.primary.opacity(0.06),
                    lineWidth: isExpanded ? (variant == .v03 ? 1.5 : 1.2) : 0.8
                )
        }
        .shadow(
            color: Color.black.opacity(variant == .v03 && isExpanded ? 0.16 : 0.04),
            radius: variant == .v03 && isExpanded ? 16 : 6,
            y: variant == .v03 && isExpanded ? 8 : 2
        )
        .scaleEffect(variant == .v03 && isExpanded ? 1.012 : 1.0)
        .onAppear {
            draftTitle = todo.title
        }
        .onChange(of: todo.title) { _, updated in
            draftTitle = updated
        }
    }

    // MARK: Row 1 — Full-Width Title + Progress Ring + Optional Chevron
    private var row1TitleAndProgress: some View {
        HStack(alignment: .top, spacing: AppTheme.Space.sm) {
            Button(action: onToggleExpand) {
                Text(todo.title)
                    .font(.system(size: titleFontSize, weight: isExpanded && variant != .v02 ? .bold : .semibold))
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                progressBadge

                if variant == .v02 {
                    // v02 keeps the chevron slot permanently mounted so Row 1 width never shifts on expand
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(AppTheme.surfaceElevated, in: Circle())
                    }
                    .buttonStyle(AppPressableButtonStyle())
                } else if isExpanded {
                    Button(action: onToggleExpand) {
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(AppTheme.surfaceElevated, in: Circle())
                    }
                    .buttonStyle(AppPressableButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var progressBadge: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)

            Text("\(completedSubtaskCount)/\(totalSubtaskCount)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.surfaceElevated, in: Capsule())
    }

    // MARK: Row 2 — Persistent Status · Priority · Timestamp (`今天 17:31`) · Linear
    private var row2UnifiedMetadataCapsules: some View {
        HStack(spacing: 6) {
            Button(action: onCycleStatus) {
                HStack(spacing: 4) {
                    Image(systemName: statusSymbol)
                        .font(.caption2.weight(.bold))
                    Text(statusTitle)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minHeight: 28)
                .background(statusColor.opacity(0.15), in: Capsule())
            }
            .buttonStyle(AppPressableButtonStyle())

            Button(action: onCyclePriority) {
                Text(todo.priority.rawValue)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(priorityColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minHeight: 28)
                    .background(priorityColor.opacity(0.15), in: Capsule())
            }
            .buttonStyle(AppPressableButtonStyle())

            Text("今天 17:31")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            if isExpanded && variant != .v02 {
                linearActionCapsule
                    .opacity(expandFraction)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
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
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minHeight: 28)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: Row 3 — Persistent Rounded-Rect `#Tag` Chips + Always-Present `+` Button
    private var row3PersistentTagsAndPlus: some View {
        TodoUnfoldWrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(todo.tags.prefix(3), id: \.self) { tag in
                Button(action: { onToggleTag(tag) }) {
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
            }

            Button(action: onToggleTagTray) {
                Image(systemName: isTagTrayOpen ? "chevron.up" : "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
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
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                linearActionCapsule
            }

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
