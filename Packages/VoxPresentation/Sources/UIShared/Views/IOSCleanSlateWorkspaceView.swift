import SwiftUI
import CoreModels
import Preferences

#if os(iOS)
@MainActor
public struct IOSCleanSlateWorkspaceView: View {
    @ObservedObject private var viewModel: VoxWorkspaceViewModel
    private let localModelLoadingStatus: LocalModelLoadingStatus?
    @State private var selectedTodo: VoiceTodo?
    @State private var isShowingNotesSheet = false
    @State private var isShowingSettingsSheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeAnimation
    @Namespace private var filterAnimation
    @Namespace private var dockGlassNamespace
    @State private var isHoldRecording = false
    @State private var isFoldExpanded = false

    public init(
        viewModel: VoxWorkspaceViewModel,
        localModelLoadingStatus: LocalModelLoadingStatus? = nil
    ) {
        self.viewModel = viewModel
        self.localModelLoadingStatus = localModelLoadingStatus
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.surfacePrimary.ignoresSafeArea()
                ScrollView {
                    Text(stageSentence)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .tracking(-0.4).lineSpacing(7).multilineTextAlignment(.center)
                        .frame(maxWidth: 360).frame(maxWidth: .infinity, minHeight: 560)
                        .padding(.horizontal, 22)
                        .accessibilityIdentifier("vox.transcript.final")
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 148)
                bottomCaptureInset
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedTodo) { todo in
            IOSCleanSlateTodoDetail(todo: todo, viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingNotesSheet) { IOSVoiceNotesHistorySheet(viewModel: viewModel) }
        .sheet(isPresented: $isShowingSettingsSheet) {
            IOSWorkspaceSettingsSheet(viewModel: viewModel, localModelLoadingStatus: localModelLoadingStatus)
        }
        .sensoryFeedback(.success, trigger: viewModel.lastCopiedBannerText)
        .task {
            if ProcessInfo.processInfo.environment["VOX_DEMO_SEED"] == "1" { await viewModel.seedDemoDataIfEmptyForPreview() }
        }
    }

    private var stageSentence: String {
        if viewModel.isRecordingActive { return "正在聆听你的灵感，松手立即润色…" }
        if viewModel.isProcessingCapture { return "正在提炼语句结构与核心要点…" }
        return viewModel.filteredCaptures.first?.refinedText.isEmpty == false
            ? (viewModel.filteredCaptures.first?.refinedText ?? "")
            : "按住底部玻璃说话，松手即刻生成润色笔记。"
    }

    // MARK: - Group 1: Compact Overview & Filter Strip

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
                        .frame(minHeight: 36)
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

    // MARK: - Group 3: Functional Bottom Capture Dock & Deterministic Receipt (Native Liquid Glass)

    private var bottomCaptureInset: some View {
        GlassEffectContainer(spacing: AppTheme.Space.md) {
            VStack(spacing: AppTheme.Space.sm) {
                if let receipt = viewModel.lastCopiedBannerText {
                    deterministicReceiptPill(receipt)
                        .glassEffectID("receiptBanner", in: dockGlassNamespace)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if case .failed(_, let reason) = viewModel.captureState {
                    failureBannerPill(reason)
                        .glassEffectID("failureBanner", in: dockGlassNamespace)
                }
                captureDock
            }
        }
        .padding(.horizontal, AppTheme.Space.lg)
        .padding(.top, AppTheme.Space.xs)
        .padding(.bottom, AppTheme.Space.sm)
        .animation(reduceMotion ? nil : AppTheme.snappySpring, value: viewModel.lastCopiedBannerText)
        .animation(reduceMotion ? nil : AppTheme.gestureSpring, value: viewModel.captureState)
    }

    private func deterministicReceiptPill(_ text: String) -> some View {
        Button {
            viewModel.dismissReceiptBanner()
        } label: {
            HStack(spacing: AppTheme.Space.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.Space.md)
            .padding(.vertical, AppTheme.Space.sm)
            .modifier(IOSFunctionalGlassModifier(reduceTransparency: reduceTransparency, cornerRadius: AppTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vox.ios.receiptBanner")
    }

    private func failureBannerPill(_ reason: String) -> some View {
        HStack(spacing: AppTheme.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Space.md)
        .padding(.vertical, AppTheme.Space.xs)
        .modifier(IOSFunctionalGlassModifier(reduceTransparency: reduceTransparency, cornerRadius: AppTheme.Radius.md))
    }

    private var captureDock: some View {
        HStack(spacing: AppTheme.Space.md) {
            foldControls
            if viewModel.isRecordingActive {
                recordingActiveBar
            } else if viewModel.isProcessingCapture {
                processingActiveBar
                    .padding(.horizontal, AppTheme.Space.lg)
                    .padding(.vertical, AppTheme.Space.sm)
                    .modifier(IOSFunctionalGlassCapsuleModifier(reduceTransparency: reduceTransparency))
                    .glassEffectID("dockMainPill", in: dockGlassNamespace)
            } else {
                idleDestinationSwitcher
                    .padding(AppTheme.Space.xs)
                    .modifier(IOSFunctionalGlassCapsuleModifier(reduceTransparency: reduceTransparency))
                    .glassEffectID("dockMainPill", in: dockGlassNamespace)

                Spacer(minLength: AppTheme.Space.xs)
            }

            if !viewModel.isProcessingCapture {
                primaryRecordButton
                    .glassEffectID("dockActionOrb", in: dockGlassNamespace)
            }
        }
    }

    private var foldControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : AppTheme.gestureSpring) { isFoldExpanded.toggle() }
            } label: { Image(systemName: isFoldExpanded ? "xmark" : "square.stack.3d.up").frame(width: 44, height: 44) }
                .buttonStyle(.glass)
                .accessibilityIdentifier("vox.fold.menu.button")
            if isFoldExpanded {
                Button("待办", systemImage: "checklist") { isShowingNotesSheet = true }
                    .accessibilityIdentifier("vox.fold.todoList.button")
                Button("设置", systemImage: "gearshape") { isShowingSettingsSheet = true }
                    .accessibilityIdentifier("vox.fold.settings.button")
            }
        }
        .buttonStyle(.borderless)
    }

    private var idleDestinationSwitcher: some View {
        HStack(spacing: AppTheme.Space.xs) {
            ForEach([CaptureMode.todo, CaptureMode.text], id: \.self) { mode in
                let isSelected = viewModel.selectedCaptureMode == mode
                Button {
                    withAnimation(reduceMotion ? nil : AppTheme.snappySpring) {
                        viewModel.updatePreferredCaptureMode(mode)
                    }
                } label: {
                    HStack(spacing: AppTheme.Space.xs) {
                        Image(systemName: mode == .todo ? "checklist" : "doc.on.clipboard")
                            .font(.caption.weight(.semibold))
                        Text(mode == .todo ? "存入待办" : "复制文字")
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    }
                    .padding(.horizontal, AppTheme.Space.md)
                    .frame(minHeight: 44)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill((mode == .todo ? Color.orange : Color.accentColor).opacity(0.20))
                                .matchedGeometryEffect(id: "captureDestination", in: modeAnimation)
                        }
                    }
                    .foregroundStyle(isSelected ? (mode == .todo ? Color.orange : Color.accentColor) : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .todo ? "Todo 模式" : "文字模式")
                .accessibilityIdentifier("vox.ios.mode.\(mode.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedCaptureMode)
    }

    private var primaryRecordButton: some View {
        Button {
            if isHoldRecording {
                isHoldRecording = false
                return
            }
            if viewModel.isRecordingActive {
                viewModel.finishCapture()
            } else {
                viewModel.startCaptureInPreferredMode()
            }
        } label: {
            Image(systemName: viewModel.isRecordingActive ? "stop.fill" : "mic.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 28, height: 28)
                .padding(6)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(
            viewModel.isRecordingActive
                ? Color.red
                : (viewModel.selectedCaptureMode == .todo ? Color.orange : Color.accentColor)
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.28)
                .onEnded { _ in
                    if !viewModel.isRecordingActive {
                        isHoldRecording = true
                        viewModel.startCaptureInPreferredMode()
                    }
                }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { _ in
                    if isHoldRecording && viewModel.isRecordingActive {
                        isHoldRecording = false
                        viewModel.finishCapture()
                    }
                }
        )
        .accessibilityLabel(viewModel.isRecordingActive ? "停止录音" : "开始录音")
        .accessibilityIdentifier(viewModel.isRecordingActive ? "vox.stop.button" : "vox.record.button")
    }

    private var recordingActiveBar: some View {
        HStack(spacing: AppTheme.Space.sm) {
            Button {
                viewModel.cancelCapture()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .padding(6)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("取消")
            .glassEffectID("dockCancelOrb", in: dockGlassNamespace)

            Button {
                viewModel.toggleCaptureModeDuringRecording()
            } label: {
                HStack(spacing: AppTheme.Space.sm) {
                    IOSLiveWaveformBars(level: viewModel.audioLevel)
                    Text(Self.formatDuration(TimeInterval(viewModel.recordingElapsedSeconds)))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(viewModel.selectedCaptureMode == .todo ? "存入待办" : "复制文字")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, AppTheme.Space.sm)
                        .padding(.vertical, AppTheme.Space.xs)
                        .background(
                            (viewModel.selectedCaptureMode == .todo ? Color.orange : Color.accentColor).opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(viewModel.selectedCaptureMode == .todo ? Color.orange : Color.accentColor)
                }
                .padding(.horizontal, AppTheme.Space.md)
                .frame(maxWidth: .infinity, minHeight: 48)
                .modifier(IOSFunctionalGlassCapsuleModifier(reduceTransparency: reduceTransparency))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vox.recording.indicator")
            .glassEffectID("dockMainPill", in: dockGlassNamespace)
        }
    }

    private var processingActiveBar: some View {
        HStack(spacing: AppTheme.Space.sm) {
            ProgressView()
            Text(viewModel.selectedCaptureMode == .todo ? "正在提炼待办…" : "正在润色并复制文字…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(minHeight: 48)
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

    static func formatDuration(_ value: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60)
    }
}

private struct IOSFunctionalGlassCapsuleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.thickMaterial, in: Capsule())
        } else {
            content.glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}

private struct IOSFunctionalGlassModifier: ViewModifier {
    let reduceTransparency: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                .thickMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Live Waveform Bars

private struct IOSLiveWaveformBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.red)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: 20)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let clamped = CGFloat(max(0.15, min(1.0, level)))
        let weights: [CGFloat] = [0.45, 0.7, 1.0, 0.6, 0.85, 0.55, 0.75]
        return max(6, 20 * clamped * weights[index % weights.count])
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

// MARK: - Secondary Voice Notes Sheet (Folded P2 Lens)

private struct IOSVoiceNotesHistorySheet: View {
    @ObservedObject var viewModel: VoxWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppTheme.Space.md) {
                    if viewModel.filteredCaptures.isEmpty {
                        ContentUnavailableView(
                            "暂无速记",
                            systemImage: "waveform",
                            description: Text("开始一次录音即可看到本地语音笔记。")
                        )
                        .padding(.top, AppTheme.Space.section)
                    }
                    ForEach(viewModel.filteredCaptures) { capture in
                        IOSCleanSlateCaptureCard(capture: capture, viewModel: viewModel)
                    }
                }
                .padding(AppTheme.Space.lg)
            }
            .background(AppTheme.surfacePrimary.ignoresSafeArea())
            .navigationTitle("语音速记")
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
