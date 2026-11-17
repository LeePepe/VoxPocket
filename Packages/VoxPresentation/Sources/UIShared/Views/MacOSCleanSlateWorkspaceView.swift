import SwiftUI
import CoreModels
import Preferences
import UseCases

#if os(macOS)
/// Top-level destinations in the modernized macOS Liquid Glass desktop workspace (`VS-003 × VS-005 × VS-007`).
public enum MacOSWorkspaceDestination: String, CaseIterable, Identifiable, Sendable {
    case recorderAndNotes = "recorder"
    case todos = "todos"
    case aiAutoPickupConsole = "ai-console"
    case settings = "settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recorderAndNotes: "🎙️ 录音与速记"
        case .todos: "☑️ 待办清单"
        case .aiAutoPickupConsole: "⚡ AI 自动接单"
        case .settings: "⚙️ 脚本与快捷键"
        }
    }

    public var subtitle: String {
        switch self {
        case .recorderAndNotes: "5 阶段光团 · 速记直转待办"
        case .todos: "iOS 100% 对齐 · #Tag 与子步骤"
        case .aiAutoPickupConsole: "iCloud AIOrders · VOX_STATUS"
        case .settings: "模板参数与全局热键"
        }
    }

    public var symbolName: String {
        switch self {
        case .recorderAndNotes: "waveform.circle.fill"
        case .todos: "checklist"
        case .aiAutoPickupConsole: "bolt.horizontal.circle.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// Modernized macOS native Liquid Glass workspace without legacy `.sheet` management modal or `148pt` `RecorderDock` gray mask.
@MainActor
public struct MacOSCleanSlateWorkspaceView: View {
    @ObservedObject private var viewModel: VoxWorkspaceViewModel
    @State private var selectedDestination: MacOSWorkspaceDestination
    private let isPreviewDemoMode: Bool
    @State private var aiRunnerConfig: UserAIRunnerConfig = UserAIRunnerConfig()
    @State private var consoleLogLines: [String]
    @State private var previewDemoOrders: [ICloudAIExecutionOrder] = []
    @State private var isSimulatingPickup: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        viewModel: VoxWorkspaceViewModel,
        initialDestination: MacOSWorkspaceDestination = .recorderAndNotes,
        isPreviewDemoMode: Bool = false
    ) {
        self.viewModel = viewModel
        _selectedDestination = State(initialValue: initialDestination)
        self.isPreviewDemoMode = isPreviewDemoMode
        _consoleLogLines = State(
            initialValue: isPreviewDemoMode
                ? [
                    "[DEMO 09:41:02] MacAIOrderAutoPickupService listening on iCloud AIOrders (poll=2.0s)",
                    "[DEMO 09:41:05] VOX_STATUS: 已认领订单 · 准备启动 Mac AI Agent",
                    "[DEMO 09:41:08] VOX_PROGRESS: 0.45",
                    "[DEMO 09:41:09] VOX_STATUS: 正在分析与执行子步骤 (1/3) · 液态玻璃交互走查"
                ]
                : []
        )
    }

    public var body: some View {
        ZStack {
            RecorderBackdrop(
                status: selectedDestination == .recorderAndNotes ? viewModel.recorderStatus : .idle,
                audioLevel: selectedDestination == .recorderAndNotes ? viewModel.audioLevel : 0
            )

            HStack(alignment: .top, spacing: 0) {
                leftNavigationRail
                    .frame(width: 204)

                Divider()
                    .opacity(0.22)

                primaryStageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .windowToolbar)
        .voxTheme()
        .task {
            if let loaded: UserAIRunnerConfig = await UserDefaultsPreferencesStore.shared.getValue(for: .userAIRunnerConfig) {
                aiRunnerConfig = loaded
            }
            if viewModel.selectedTodoID == nil {
                viewModel.selectedTodoID = viewModel.todos.first?.id
            }
            if viewModel.expandedTodoID == nil {
                viewModel.expandedTodoID = viewModel.todos.first?.id
            }
        }
        .onChange(of: viewModel.todos.count) { _, _ in
            if viewModel.selectedTodoID == nil {
                viewModel.selectedTodoID = viewModel.todos.first?.id
            }
            if viewModel.expandedTodoID == nil {
                viewModel.expandedTodoID = viewModel.todos.first?.id
            }
        }
        .onChange(of: viewModel.aiOrdersByTodoID) { _, orders in
            guard let newest = orders.values.max(by: { $0.updatedAt < $1.updatedAt }) else { return }
            let pct = Int((newest.progressFraction * 100).rounded())
            let line = "[\(Self.logTimeFormatter.string(from: newest.updatedAt))] VOX_STATUS: [\(newest.state.rawValue)] \(newest.progressStage) (\(pct)%)"
            if consoleLogLines.last != line {
                consoleLogLines.append(line)
            }
        }
    }

    // MARK: - Left Liquid Glass Navigation Rail (`204pt` Width)

    private var leftNavigationRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("VoxPocket")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("macOS Liquid Glass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(MacOSWorkspaceDestination.allCases) { destination in
                    destinationRowButton(destination)
                }
            }
            .padding(.horizontal, 10)

            if selectedDestination == .todos {
                Divider()
                    .padding(.horizontal, 12)

                todoSidebarQuickFilters
                    .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            aiAutoPickupMiniStatusCard
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surfaceCard.opacity(0.62))
    }

    private func destinationRowButton(_ destination: MacOSWorkspaceDestination) -> some View {
        let isSelected = selectedDestination == destination
        let badgeCount: Int? = {
            switch destination {
            case .recorderAndNotes: return viewModel.captures.count
            case .todos: return viewModel.totalTodoCount
            case .aiAutoPickupConsole: return max(viewModel.runningCount, viewModel.aiOrdersByTodoID.count)
            case .settings: return nil
            }
        }()

        return Button(action: {
            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                selectedDestination = destination
                viewModel.switchToPage(destination == .todos ? .todo : .recorder)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: destination.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(destination.title)
                        .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    Text(destination.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (isSelected ? Color.accentColor : Color.secondary).opacity(0.14),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.9)
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vox.macos.nav." + destination.rawValue)
    }

    private var todoSidebarQuickFilters: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("状态筛选")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            ForEach([TodoStatusFilter.all, .inbox, .running, .done, .failed], id: \.self) { filter in
                if filter != .failed || viewModel.failedCount > 0 || viewModel.selectedTodoFilter == .failed {
                    let isSelected = viewModel.selectedTodoFilter == filter
                    Button(action: {
                        withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                            viewModel.selectedTodoFilter = filter
                        }
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
                                .frame(width: 6, height: 6)
                            Text(filterTitle(for: filter))
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                            Spacer(minLength: 4)
                            Text("\(filterCount(for: filter))")
                                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("vox.macos.todo.filter." + filter.rawValue)
                }
            }
        }
    }

    private var aiAutoPickupMiniStatusCard: some View {
        Button(action: {
            withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                selectedDestination = .aiAutoPickupConsole
            }
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(aiRunnerConfig.isAutoPickupEnabled ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(aiRunnerConfig.isAutoPickupEnabled ? "监听中 · iCloud AIOrders" : "已暂停自动接单")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text("Runner: \(aiRunnerConfig.runnerDisplayName)")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.surfaceElevated.opacity(0.85),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vox.macos.sidebar.aiStatusCard")
    }

    // MARK: - Primary Stage Content Router

    @ViewBuilder
    private var primaryStageContent: some View {
        switch selectedDestination {
        case .recorderAndNotes:
            recorderAndQuickNotesStage
        case .todos:
            macosTodoParityWorkspaceStage
        case .aiAutoPickupConsole:
            macAIAutoPickupConsoleStage
        case .settings:
            macosInlineSettingsStage
        }
    }

    // MARK: - Section 1: `🎙️ 录音与速记` (Pure Top Atmosphere + Floating Glass Bar, ZERO `RecorderDock` Mask)

    private var recorderAndQuickNotesStage: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                RecorderSentenceStage(sentence: sentence) {
                    guard !viewModel.isRecordingActive, !viewModel.isProcessingCapture else { return }
                    viewModel.copyLatestCompletedText()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !viewModel.filteredCaptures.isEmpty {
                    recentCapturesStrip
                        .padding(.horizontal, 20)
                        .padding(.bottom, 76)
                }
            }

            floatingRecorderControlPillBar
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
    }

    private var recentCapturesStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("最近语音速记", systemImage: "waveform")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let banner = viewModel.lastCopiedBannerText {
                    Text(banner)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.filteredCaptures.prefix(4)) { capture in
                        let displayText = capture.refinedText.isEmpty ? capture.rawTranscript : capture.refinedText
                        HStack(spacing: 8) {
                            Text(displayText)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: 220, alignment: .leading)

                            Button("转待办") {
                                viewModel.convertCaptureToTodo(capture.id)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button("复制") {
                                viewModel.copyCaptureText(capture)
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            AppTheme.surfaceCard.opacity(0.78),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                        }
                    }
                }
            }
        }
    }

    private var floatingRecorderControlPillBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach([CaptureMode.text, .todo], id: \.self) { mode in
                    let isSelected = viewModel.selectedCaptureMode == mode
                    Button(action: { viewModel.updatePreferredCaptureMode(mode) }) {
                        Label(
                            mode == .text ? "录文字" : "记待办",
                            systemImage: mode == .text ? "doc.on.clipboard" : "checklist"
                        )
                        .font(.caption.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.accentColor : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .modifier(RecorderGlassModifier())

            Text(feedback)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: {
                withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                    selectedDestination = .todos
                }
            }) {
                Label("待办 (\(viewModel.totalTodoCount))", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .modifier(RecorderGlassModifier())
            .accessibilityIdentifier("vox.macos.quickOpenTodos")

            RecorderButton(
                isRecording: viewModel.isRecordingActive,
                isProcessing: viewModel.isProcessingCapture,
                start: { await viewModel.startCaptureAndWait() },
                stop: { await viewModel.completeCapture() },
                cancel: { viewModel.cancelCapture() }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            AppTheme.surfaceCard.opacity(0.66),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
    }

    // MARK: - Section 2: `☑️ 待办清单` (100% iOS-Parity Todo Cards + Split Detail Inspector)

    private var macosTodoParityWorkspaceStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("待办清单")
                    .font(.title3.bold())

                HStack(spacing: 5) {
                    ForEach([TodoStatusFilter.all, .inbox, .running, .done, .failed], id: \.self) { filter in
                        if filter != .failed || viewModel.failedCount > 0 || viewModel.selectedTodoFilter == .failed {
                            let isSelected = viewModel.selectedTodoFilter == filter
                            Button(action: {
                                withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                    viewModel.selectedTodoFilter = filter
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(filterTitle(for: filter))
                                        .font(.caption.weight(isSelected ? .bold : .medium))
                                    Text("\(filterCount(for: filter))")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .opacity(0.8)
                                }
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                TextField("搜索待办、标签或子步骤…", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 210)
                    .accessibilityIdentifier("vox.macos.todo.search")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()
                .opacity(0.22)

            if viewModel.filteredTodos.isEmpty {
                ContentUnavailableView(
                    "暂无匹配待办",
                    systemImage: "checklist",
                    description: Text("切换筛选条件或通过语音录入新待办。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.filteredTodos) { todo in
                            MacOSParityTodoCardView(
                                todo: todo,
                                isExpanded: viewModel.expandedTodoID == todo.id,
                                aiOrder: viewModel.aiOrder(for: todo.id),
                                historicalTags: viewModel.availableHistoricalTags,
                                onToggleExpand: {
                                    withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                                        viewModel.toggleExpandedTodo(todo.id)
                                        viewModel.selectedTodoID = todo.id
                                    }
                                },
                                onCycleStatus: { viewModel.cycleTodoStatus(todoID: todo.id) },
                                onSelectStatus: { state in viewModel.updateTodoStatus(todoID: todo.id, state: state) },
                                onCyclePriority: { viewModel.cycleTodoPriority(todoID: todo.id) },
                                onSelectPriority: { pri in viewModel.updateTodoPriority(todoID: todo.id, priority: pri) },
                                onUpdateTitle: { title in viewModel.updateTodoTitle(todoID: todo.id, title: title) },
                                onUpdateDescription: { desc in viewModel.updateTodoDescription(todoID: todo.id, description: desc) },
                                onToggleTag: { tag in viewModel.toggleTodoTag(todoID: todo.id, tag: tag) },
                                onAddTag: { tag in viewModel.addTodoTag(todoID: todo.id, tag: tag) },
                                onToggleSubtask: { subID in viewModel.toggleTodoSubtask(todoID: todo.id, subtaskID: subID) },
                                onUpdateSubtaskTitle: { subID, title in
                                    viewModel.updateTodoSubtaskTitle(todoID: todo.id, subtaskID: subID, title: title)
                                },
                                onAppendSubtask: { title in viewModel.appendSubtask(to: todo.id, title: title) },
                                onShiftReminderMinutes: { mins in viewModel.shiftTodoReminderByMinutes(todoID: todo.id, deltaMinutes: mins) },
                                onAssignReminderSlot: { slot in viewModel.assignTodoHabitSlot(todoID: todo.id, slotRawValue: slot) },
                                onClearReminder: { viewModel.clearTodoReminder(todoID: todo.id) },
                                onDispatchAI: {
                                    dispatchAndStreamOrderInWorkspace(for: todo)
                                }
                            )
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    // MARK: - Section 3: `⚡ Mac AI 自动接单监控台` (`MacAIOrderAutoPickupService` & `ICloudAIExecutionOrder` Live Console)

    private var macAIAutoPickupConsoleStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Mac AI 自动接单监控台")
                                .font(.title3.bold())
                            Text(aiRunnerConfig.isAutoPickupEnabled ? "监听中 · iCloud AIOrders" : "已暂停")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(aiRunnerConfig.isAutoPickupEnabled ? Color.green : Color.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    (aiRunnerConfig.isAutoPickupEnabled ? Color.green : Color.orange).opacity(0.14),
                                    in: Capsule()
                                )
                        }
                        Text("自动扫描 Application Support/VoxPocket/AIOrders 与 iCloud KVS 队列，认领待办并实时回传 VOX_STATUS / VOX_PROGRESS。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: triggerSimulatedAutoPickupPass) {
                        Label(
                            isSimulatingPickup
                                ? "正在同步状态…"
                                : (isPreviewDemoMode ? "⚡ Preview 模拟接单演示" : "🔄 刷新 iCloud 队列状态"),
                            systemImage: isPreviewDemoMode ? "bolt.horizontal.circle.fill" : "arrow.clockwise.circle.fill"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSimulatingPickup)
                    .accessibilityIdentifier("vox.macos.aiConsole.simulatePickup")
                }

                // Runner configuration summary card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("当前 Runner 配置 (\(aiRunnerConfig.runnerDisplayName))", systemImage: "terminal.fill")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("工作目录: \(aiRunnerConfig.defaultWorkingDirectory)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    let sampleOrder = sampleOrderForCommandPreview
                    let previewCommand = aiRunnerConfig.interpolateCommand(
                        order: sampleOrder,
                        orderFilePath: "~/Library/Application Support/VoxPocket/AIOrders/\(sampleOrder.orderID.uuidString).json",
                        statusFilePath: "~/Library/Application Support/VoxPocket/AIOrders/\(sampleOrder.orderID.uuidString).status.json"
                    )

                    Text(previewCommand)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            AppTheme.surfacePrimary.opacity(0.75),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .padding(14)
                .background(
                    AppTheme.surfaceCard,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                }

                // Active & recent orders list
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("iCloud AI 执行订单队列")
                            .font(.subheadline.bold())
                        if isPreviewDemoMode && viewModel.aiOrdersByTodoID.isEmpty {
                            Text("Preview 示例数据")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }

                    if displayedAIOrders.isEmpty {
                        ContentUnavailableView(
                            "暂无活跃或排队的 iCloud AI 订单",
                            systemImage: "icloud.and.arrow.up",
                            description: Text("在待办清单中点击「✨ AI do it」将待办提交至 iCloud AIOrders，等待 Mac Runner 认领执行。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .background(
                            AppTheme.surfaceCard.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                    } else {
                        ForEach(displayedAIOrders) { order in
                            aiOrderMonitorCard(order)
                        }
                    }
                }

                // Live VOX_STATUS / VOX_PROGRESS streaming console
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("实时执行日志流 (VOX_STATUS / VOX_PROGRESS)", systemImage: "apple.terminal")
                            .font(.subheadline.bold())
                        Spacer()
                        Button("清空日志") {
                            consoleLogLines.removeAll()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }

                    if consoleLogLines.isEmpty {
                        Text("等待 iCloud AIOrders 状态流更新…")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                Color.black.opacity(0.78),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(consoleLogLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(line.contains("VOX_STATUS:") ? Color.cyan : .secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                        .background(
                            Color.black.opacity(0.78),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                }
            }
            .padding(18)
        }
    }

    private var sampleOrderForCommandPreview: ICloudAIExecutionOrder {
        if let firstOrder = displayedAIOrders.first {
            return firstOrder
        }
        if let firstTodo = viewModel.todos.first {
            return ICloudAIExecutionOrder(from: firstTodo)
        }
        return ICloudAIExecutionOrder(
            todoID: UUID(),
            title: "液态玻璃交互走查",
            description: "整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单",
            subtasks: ["录制默认空态与声波走查", "验证双按钮侧滑手势"],
            tags: ["#VoxPocket", "#Glass"],
            priority: "P0"
        )
    }

    private var displayedAIOrders: [ICloudAIExecutionOrder] {
        let liveOrders = Array(viewModel.aiOrdersByTodoID.values)
            .sorted { $0.updatedAt > $1.updatedAt }
        if !liveOrders.isEmpty {
            return liveOrders
        }
        guard isPreviewDemoMode else {
            return []
        }
        if !previewDemoOrders.isEmpty {
            return previewDemoOrders
        }
        return viewModel.todos.prefix(3).enumerated().map { idx, todo in
            let state: AIOrderExecutionState = idx == 0 ? .running : (todo.executionState == .done ? .completed : .queued)
            let fraction: Double = idx == 0 ? 0.68 : (todo.executionState == .done ? 1.0 : 0.12)
            let stage: String = idx == 0
                ? "正在执行 \(max(1, todo.subtasks.count)) 项子步骤…"
                : (todo.executionState == .done ? "执行完成" : "已上传 iCloud · 等待 Mac 接单")
            return ICloudAIExecutionOrder(
                todoID: todo.id,
                title: todo.title,
                description: todo.description,
                subtasks: todo.subtasks.map(\.title),
                tags: todo.tags,
                priority: todo.priority.rawValue,
                projectKey: todo.projectKey,
                state: state,
                progressStage: stage,
                progressFraction: fraction,
                outputSummary: todo.lastExecutionSummary,
                assignedRunnerName: aiRunnerConfig.runnerDisplayName
            )
        }
    }

    private func aiOrderMonitorCard(_ order: ICloudAIExecutionOrder) -> some View {
        let matchedTodo = viewModel.todos.first(where: { $0.id == order.todoID })
        let displayTitle = !order.title.isEmpty ? order.title : (matchedTodo?.title ?? "AI 执行任务")
        let tint: Color = {
            switch order.state {
            case .queued: return .cyan
            case .claimedByMac, .running: return .orange
            case .completed: return .green
            case .failed: return .red
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(order.priority)
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.82), in: Capsule())

                Text(displayTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                Text(order.formattedButtonLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
            }

            ProgressView(value: order.progressFraction)
                .tint(tint)

            HStack {
                Text("Order ID: \(order.orderID.uuidString.prefix(8))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("子步骤: \(order.subtaskCount) 项 · 进度 \(Int((order.progressFraction * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.9)
        }
    }

    // MARK: - Section 4: `⚙️ AI 脚本与快捷键设置` (Direct Inline `MacOSSettingsView` without `.sheet`)

    private var macosInlineSettingsStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 脚本模板与全局快捷键设置")
                        .font(.title3.bold())
                    Text("直接配置 MacAIOrderAutoPickupService 脚本占位符 ({{order_file}}, {{status_file}}, {{title}}, {{cwd}}) 与全局热键。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()
                .opacity(0.22)

            MacOSSettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Interactive AI Order Dispatch & Live `MacAIOrderAutoPickupService` Execution

    private func dispatchAndStreamOrderInWorkspace(for todo: VoiceTodo) {
        consoleLogLines.append("[\(Self.logTimeFormatter.string(from: Date()))] 已派发待办至 iCloud AIOrders (todoID=\(todo.id.uuidString.prefix(8)))")
        viewModel.dispatchTodoToICloudAI(todo.id)
    }

    private func triggerSimulatedAutoPickupPass() {
        guard !isSimulatingPickup else { return }
        isSimulatingPickup = true
        if isPreviewDemoMode {
            consoleLogLines.append("[\(Self.logTimeFormatter.string(from: Date()))] [Preview Demo] VOX_PROGRESS: 1.00 · VOX_STATUS: Preview 演示订单已完成")
            if let first = displayedAIOrders.first {
                previewDemoOrders = [
                    first.withState(
                        .completed,
                        progressStage: "执行完成 (Preview Demo)",
                        progressFraction: 1.0,
                        outputSummary: "完成 \(max(1, first.subtaskCount)) 项步骤",
                        assignedRunnerName: aiRunnerConfig.runnerDisplayName
                    )
                ] + Array(displayedAIOrders.dropFirst())
            }
            isSimulatingPickup = false
        } else {
            Task { @MainActor in
                defer { isSimulatingPickup = false }
                if let loaded: UserAIRunnerConfig = await UserDefaultsPreferencesStore.shared.getValue(for: .userAIRunnerConfig) {
                    aiRunnerConfig = loaded
                }
                await viewModel.reload()
                consoleLogLines.append("[\(Self.logTimeFormatter.string(from: Date()))] 已刷新 iCloud AIOrders 队列状态 (活跃订单: \(viewModel.aiOrdersByTodoID.count))")
            }
        }
    }

    private func filterTitle(for filter: TodoStatusFilter) -> String {
        switch filter {
        case .all: "全部"
        case .inbox: "待处理"
        case .running: "AI 执行中"
        case .done: "已完成"
        case .failed: "需重试"
        }
    }

    private func filterCount(for filter: TodoStatusFilter) -> Int {
        switch filter {
        case .all: viewModel.totalTodoCount
        case .inbox: viewModel.inboxCount
        case .running: viewModel.runningCount
        case .done: viewModel.doneCount
        case .failed: viewModel.failedCount
        }
    }

    private var sentence: String {
        if viewModel.isRecordingActive { return viewModel.liveTranscription.isEmpty ? "正在聆听你的灵感，松手立即润色…" : viewModel.liveTranscription }
        if viewModel.isProcessingCapture { return viewModel.streamingRefinedText.isEmpty ? "正在提炼语句结构与核心要点…" : viewModel.streamingRefinedText }
        return viewModel.latestCompletedText.isEmpty ? "按住底部玻璃说话，松手即刻生成润色笔记。" : viewModel.latestCompletedText
    }

    private var feedback: String {
        if viewModel.isRecordingActive { return "正在聆听 · 松手立即润色" }
        if viewModel.isProcessingCapture { return "正在提炼语句结构与核心要点…" }
        return viewModel.lastCopiedBannerText ?? "按住右侧麦克风说话 · 点按也可启停"
    }

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - 100% iOS-Parity Expandable Todo Card for macOS Desktop Workspace (`v02` Clipped Tag Shelf + `v03` Subtasks + `✨ AI do it`)

@MainActor
private struct MacOSParityTodoCardView: View {
    let todo: VoiceTodo
    let isExpanded: Bool
    let aiOrder: ICloudAIExecutionOrder?
    let historicalTags: [String]
    let onToggleExpand: () -> Void
    let onCycleStatus: () -> Void
    let onSelectStatus: (TodoExecutionState) -> Void
    let onCyclePriority: () -> Void
    let onSelectPriority: (TodoPriority) -> Void
    let onUpdateTitle: (String) -> Void
    let onUpdateDescription: (String) -> Void
    let onToggleTag: (String) -> Void
    let onAddTag: (String) -> Void
    let onToggleSubtask: (UUID) -> Void
    let onUpdateSubtaskTitle: (UUID, String) -> Void
    let onAppendSubtask: (String) -> Void
    let onShiftReminderMinutes: (Int) -> Void
    let onAssignReminderSlot: (String) -> Void
    let onClearReminder: () -> Void
    let onDispatchAI: () -> Void

    @State private var draftTitle: String = ""
    @State private var draftDescription: String = ""
    @State private var isTagTrayOpen: Bool = false
    @State private var newTagText: String = ""
    @State private var newSubtaskText: String = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isDescriptionFocused: Bool

    private var isDone: Bool { todo.executionState == .done }
    private var completedSubtaskCount: Int { todo.subtasks.filter(\.isCompleted).count }
    private var totalSubtaskCount: Int { todo.subtasks.count }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Title + Creation Time + Expand Chevron
            HStack(spacing: 8) {
                if isExpanded {
                    TextField("待办短标题", text: $draftTitle)
                        .font(.system(size: 15.5, weight: .semibold))
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onSubmit { commitTitleIfValid() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(todo.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("今天 " + Self.timeFormatter.string(from: todo.updatedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 24, height: 24)
                        .background(AppTheme.surfaceElevated, in: Circle())
                }
                .buttonStyle(AppPressableButtonStyle())
            }
            .padding(.bottom, 6)

            // Row 2: Status Capsule + Priority P0..P2 + 🔔 Reminder Time + >=2 Subtask Progress
            HStack(spacing: 6) {
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
                .contextMenu {
                    Button("待处理") { onSelectStatus(.inbox) }
                    Button("进行中") { onSelectStatus(.running) }
                    Button("已完成") { onSelectStatus(.done) }
                }

                Button(action: onCyclePriority) {
                    Text(todo.priority.rawValue)
                        .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(priorityColor)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(priorityColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(AppPressableButtonStyle())
                .contextMenu {
                    ForEach(TodoPriority.allCases, id: \.self) { level in
                        Button(level.rawValue) { onSelectPriority(level) }
                    }
                }

                if todo.scheduledAt != nil || isExpanded {
                    Menu {
                        Button("早上 09:00") { onAssignReminderSlot("morning") }
                        Button("下午 15:00") { onAssignReminderSlot("afternoon") }
                        Button("晚上 20:30") { onAssignReminderSlot("night") }
                        Divider()
                        Button("延后 15 分钟 (+15m)") { onShiftReminderMinutes(15) }
                        if todo.scheduledAt != nil {
                            Button("清除提醒", role: .destructive) { onClearReminder() }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: todo.scheduledAt == nil ? "bell" : "bell.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(todo.scheduledAt.map { "🔔 " + Self.timeFormatter.string(from: $0) } ?? "设置提醒")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(todo.scheduledAt == nil ? .secondary : Color.accentColor)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(
                            (todo.scheduledAt == nil ? Color.secondary : Color.accentColor).opacity(0.13),
                            in: Capsule()
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if totalSubtaskCount >= 2 {
                    Text("\(completedSubtaskCount)/\(totalSubtaskCount)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(AppTheme.surfaceElevated, in: Capsule())
                }

                Spacer(minLength: 4)
            }

            // Expand-only drawer via TodoExpandRevealLayout + .clipped()
            TodoExpandRevealLayout(progress: isExpanded ? 1.0 : 0.0) {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.top, 8)

                    TextField("补充背景说明或语音上下文…", text: $draftDescription, axis: .vertical)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($isDescriptionFocused)
                        .onSubmit { commitDescriptionIfChanged() }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            AppTheme.surfacePrimary.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    v02ClippedTagShelf

                    v03SubtaskList

                    HStack(spacing: 8) {
                        Button(action: onDispatchAI) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.caption.weight(.bold))
                                Text(aiOrder?.formattedButtonLabel ?? "✨ AI do it")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .frame(height: 27)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(AppPressableButtonStyle())

                        if let aiOrder {
                            ProgressView(value: aiOrder.progressFraction)
                                .frame(maxWidth: 140)
                        }

                        Spacer()
                    }
                }
            }
            .clipped()
            .opacity(isExpanded ? 1.0 : 0.0)
            .allowsHitTesting(isExpanded)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            AppTheme.surfaceCard,
            in: RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous)
                .strokeBorder(
                    isExpanded ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: isExpanded ? 1.2 : 0.8
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: isExpanded ? AppTheme.Radius.md : 14, style: .continuous))
        .onTapGesture {
            if !isExpanded {
                onToggleExpand()
            }
        }
        .onAppear {
            draftTitle = todo.title
            draftDescription = todo.description
        }
        .onChange(of: todo.title) { _, updated in
            if !isTitleFocused { draftTitle = updated }
        }
        .onChange(of: todo.description) { _, updated in
            if !isDescriptionFocused { draftDescription = updated }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused { commitTitleIfValid() }
        }
        .onChange(of: isDescriptionFocused) { _, focused in
            if !focused { commitDescriptionIfChanged() }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                commitTitleIfValid()
                commitDescriptionIfChanged()
            }
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

    private var v02ClippedTagShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(todo.tags.isEmpty ? ["#VoxPocket"] : todo.tags, id: \.self) { tag in
                    Button(action: { onToggleTag(tag) }) {
                        Text(tag)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.13), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: {
                    withAnimation(AppTheme.snappySpring) {
                        isTagTrayOpen.toggle()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isTagTrayOpen ? "chevron.up" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("标签")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            TodoExpandRevealLayout(progress: isTagTrayOpen ? 1.0 : 0.0) {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()

                    HStack(spacing: 6) {
                        ForEach(historicalTags.prefix(6), id: \.self) { candidate in
                            let selected = todo.tags.contains(candidate)
                            Button(action: { onToggleTag(candidate) }) {
                                Text(candidate)
                                    .font(.caption2.weight(selected ? .bold : .regular).monospacedDigit())
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
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
            }
            .clipped()
            .opacity(isTagTrayOpen ? 1.0 : 0.0)
            .allowsHitTesting(isTagTrayOpen)
        }
        .background(AppTheme.surfacePrimary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var v03SubtaskList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(todo.subtasks) { subtask in
                HStack(spacing: 8) {
                    Button(action: { onToggleSubtask(subtask.id) }) {
                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(subtask.isCompleted ? Color.green : .secondary)
                    }
                    .buttonStyle(.plain)

                    TextField(
                        "子步骤",
                        text: Binding(
                            get: { subtask.title },
                            set: { onUpdateSubtaskTitle(subtask.id, $0) }
                        )
                    )
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .strikethrough(subtask.isCompleted, color: .secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

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
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AppTheme.surfacePrimary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private var priorityColor: Color {
        switch todo.priority {
        case .p0: .red
        case .p1: .orange
        case .p2: .blue
        }
    }
}
#endif

