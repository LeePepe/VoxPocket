import Foundation
import Combine
import CoreModels
import Preferences
import UseCases

@MainActor
public final class VoxWorkspaceViewModel: ObservableObject, VoxWorkspaceViewState {
    private let useCase: any VoiceCaptureAndTodoUseCase
    private let preferencesStore: any PreferencesStore
    private let onCopyTextToClipboard: (@MainActor @Sendable (String) -> Void)?
    private let captureRecorder: (@Sendable (_ mode: CaptureMode) async throws -> (rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval))?
    private let recordingUseCase: (any RecordingUseCase)?
    private let transcriptionUseCase: (any TranscriptionUseCase)?
    private let editingUseCase: (any EditingUseCase)?
    private let refinementUseCase: (any RefinementUseCase)?
    private var reloadTask: Task<Void, Never>?
    private var captureStartTask: Task<Bool, Never>?
    private var captureGeneration = UUID()
    private var isCompletingCapture = false
    private var timerTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var aiOrderProgressTasks: [UUID: Task<Void, Never>] = [:]

    @Published public private(set) var captures: [VoiceCapture] = []
    @Published public private(set) var todos: [VoiceTodo] = []
    @Published public private(set) var aiOrdersByTodoID: [UUID: ICloudAIExecutionOrder] = [:]
    @Published public private(set) var projectBindings: [ProjectBinding]
    @Published public private(set) var runnerTemplates: [AIRunnerTemplate]
    @Published public private(set) var captureState: CaptureSessionState = .idle
    @Published public var selectedCaptureMode: CaptureMode = .text
    @Published public private(set) var recordingElapsedSeconds = 0
    @Published public var audioLevel: Float = 0
    @Published public private(set) var liveTranscription = ""
    @Published public private(set) var streamingRefinedText = ""
    @Published public private(set) var latestCompletedText = ""
    @Published public private(set) var lastCopiedBannerText: String?
    @Published public var playingCaptureID: UUID?
    @Published public var searchQuery = ""
    @Published public var selectedTodoFilter: TodoStatusFilter = .all
    @Published public var selectedProjectFilter: String?
    @Published public var sortOrder: WorkspaceSortOrder = .newestFirst
    @Published public var selectedSidebarSection: WorkspaceSidebarSection = .todoAll { didSet { applySidebarSelection(selectedSidebarSection) } }
    @Published public var activePage: WorkspacePage = .recorder
    @Published public var expandedTodoID: UUID?
    @Published public private(set) var appendingTargetTodoID: UUID?
    @Published public private(set) var voiceAppendedSubtaskIDs: [UUID: [UUID]] = [:]
    @Published public var selectedTodoID: UUID?
    @Published public var selectedCaptureID: UUID?

    public init(
        useCase: any VoiceCaptureAndTodoUseCase,
        projectBindings: [ProjectBinding] = [],
        runnerTemplates: [AIRunnerTemplate] = AIRunnerTemplate.defaultPresets,
        preferencesStore: any PreferencesStore = UserDefaultsPreferencesStore.shared,
        defaultCaptureMode: CaptureMode = .text,
        onCopyTextToClipboard: (@MainActor @Sendable (String) -> Void)? = nil,
        captureRecorder: (@Sendable (_ mode: CaptureMode) async throws -> (rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval))? = nil,
        recordingUseCase: (any RecordingUseCase)? = nil,
        transcriptionUseCase: (any TranscriptionUseCase)? = nil,
        editingUseCase: (any EditingUseCase)? = nil,
        refinementUseCase: (any RefinementUseCase)? = nil
    ) {
        self.useCase = useCase
        self.projectBindings = projectBindings
        self.runnerTemplates = runnerTemplates
        self.preferencesStore = preferencesStore
        self.selectedCaptureMode = defaultCaptureMode
        self.onCopyTextToClipboard = onCopyTextToClipboard
        self.captureRecorder = captureRecorder
        self.recordingUseCase = recordingUseCase
        self.transcriptionUseCase = transcriptionUseCase
        self.editingUseCase = editingUseCase
        self.refinementUseCase = refinementUseCase
        bindRecordingTelemetry()
        reloadTask = Task { [weak self] in
            await self?.loadPreferredCaptureDestination(defaultMode: defaultCaptureMode)
            await self?.reload()
        }
        let reportsStream = useCase.aiOrderStatusReports
        Task { [weak self] in
            for await report in reportsStream {
                await self?.applyAIExecutionStatusReport(report)
            }
        }
    }

    public var filteredTodos: [VoiceTodo] { todos.filter { todo in matches(todo) }.sorted { ordered($0.updatedAt, $1.updatedAt) } }
    public var filteredCaptures: [VoiceCapture] { captures.filter { capture in searchQuery.isEmpty || capture.rawTranscript.localizedCaseInsensitiveContains(searchQuery) || capture.refinedText.localizedCaseInsensitiveContains(searchQuery) }.sorted { ordered($0.updatedAt, $1.updatedAt) } }
    public var inboxCount: Int { count(.inbox) }
    public var runningCount: Int { count(.running) }
    public var doneCount: Int { count(.done) }
    public var failedCount: Int { count(.failed) }
    public var totalTodoCount: Int { todos.count }
    public var projectCounts: [String: Int] { Dictionary(grouping: todos.compactMap(\.projectKey), by: { $0 }).mapValues(\.count) }

    public func clearSearchPreservingFilters() { searchQuery = "" }
    public func dismissReceiptBanner() { lastCopiedBannerText = nil }
    public var expandedTodo: VoiceTodo? {
        guard let expandedTodoID else { return nil }
        return todos.first(where: { $0.id == expandedTodoID })
    }
    public var companionTodos: [VoiceTodo] {
        guard let expandedTodoID, filteredTodos.contains(where: { $0.id == expandedTodoID }) else {
            return filteredTodos
        }
        return filteredTodos.filter { $0.id != expandedTodoID }
    }
    public var availableHistoricalTags: [String] {
        var ordered: [String] = []
        func appendUnique(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let formatted = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
            if !ordered.contains(formatted) {
                ordered.append(formatted)
            }
        }
        for todo in todos {
            for tag in todo.tags {
                appendUnique(tag)
            }
            if let projectKey = todo.projectKey {
                appendUnique(projectKey)
            }
        }
        for binding in projectBindings {
            appendUnique(binding.displayName)
            appendUnique(binding.projectKey)
        }
        for fallback in ["#VoxPocket", "#iOS", "#AI", "#Glass", "#Podcast"] {
            appendUnique(fallback)
        }
        return ordered
    }
    public func voiceAppendedSubtasks(for todoID: UUID) -> [VoiceTodoSubtask] {
        guard let todo = todos.first(where: { $0.id == todoID }) else { return [] }
        let recordedIDs = voiceAppendedSubtaskIDs[todoID] ?? []
        let matched = recordedIDs.compactMap { id in todo.subtasks.first(where: { $0.id == id }) }
        return matched
    }
    public var appendingTargetTodoTitle: String? {
        if let appendingTargetTodoID, let target = todos.first(where: { $0.id == appendingTargetTodoID }) {
            return target.title
        }
        if activePage == .todo, let expanded = expandedTodo {
            return expanded.title
        }
        return nil
    }
    public func toggleActivePage() {
        activePage = (activePage == .recorder) ? .todo : .recorder
    }
    public func switchToPage(_ page: WorkspacePage) {
        activePage = page
    }
    public func toggleExpandedTodo(_ todoID: UUID) {
        if expandedTodoID == todoID {
            expandedTodoID = nil
        } else {
            expandedTodoID = todoID
        }
    }
    public var isRecordingActive: Bool { if case .recording = captureState { return true }; return false }
    public var recorderStatus: RecorderStatus {
        switch captureState {
        case .recording: .listening
        case .transcribing: .transcribing
        case .refining: .refining
        case .failed: .error
        case .completed: .done
        case .idle: .idle
        }
    }
    public var isProcessingCapture: Bool {
        switch captureState {
        case .transcribing, .refining: return true
        default: return false
        }
    }

    public func updatePreferredCaptureMode(_ mode: CaptureMode) {
        selectedCaptureMode = mode
        if case .recording = captureState {
            captureState = .recording(mode: mode)
        }
        let store = preferencesStore
        Task {
            await store.setValue(mode, for: .iosQuickCaptureDestination)
            NotificationCenter.default.post(name: PreferencesNotification.iosQuickCaptureDestinationDidChange, object: nil)
        }
    }

    public func startCaptureInPreferredMode() {
        if activePage == .todo {
            startCapture(mode: .todo)
        } else {
            startCapture(mode: selectedCaptureMode)
        }
    }

    public func startCaptureAndWait() async {
        startCaptureInPreferredMode()
        _ = await captureStartTask?.value
    }

    public func startCapture(mode: CaptureMode) {
        guard !isRecordingActive, !isProcessingCapture, !isCompletingCapture, captureStartTask == nil else { return }
        let generation = UUID()
        captureGeneration = generation
        let effectiveMode: CaptureMode
        if activePage == .todo, let expandedTodoID, todos.contains(where: { $0.id == expandedTodoID }) {
            appendingTargetTodoID = expandedTodoID
            effectiveMode = .text
        } else {
            appendingTargetTodoID = nil
            effectiveMode = activePage == .todo ? .todo : mode
            if activePage != .todo {
                selectedCaptureMode = mode
            }
        }
        captureState = .recording(mode: effectiveMode)
        recordingElapsedSeconds = 0
        lastCopiedBannerText = nil
        liveTranscription = ""
        streamingRefinedText = ""
        latestCompletedText = ""
        NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingStarted"), object: nil, userInfo: ["mode": effectiveMode.rawValue])
        startElapsedTimer()
        try? editingUseCase?.replaceAll(with: "")
        transcriptionUseCase?.clearLiveText()
        if isDemoRecordingEnabled {
            if appendingTargetTodoID != nil {
                liveTranscription = "补充子任务：核对双按钮极简底栏在降低透明度模式下的对比度"
            } else {
                liveTranscription = "把刚才散步想到的播客开场白记一下，先从一个深夜收到听众来信的故事切入"
            }
            audioLevel = 0.72
            return
        }
        guard let recordingUseCase else { return }
        captureStartTask = Task {
            defer { captureStartTask = nil }
            do {
                try await recordingUseCase.startRecording()
                guard captureGeneration == generation else {
                    recordingUseCase.cancelRecording()
                    return false
                }
                return true
            } catch {
                guard captureGeneration == generation else { return false }
                stopElapsedTimer()
                appendingTargetTodoID = nil
                captureState = .failed(stage: .recording, reason: error.localizedDescription)
                NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingEnded"), object: nil)
                return false
            }
        }
    }
    public var isDemoRecordingEnabled: Bool = (ProcessInfo.processInfo.environment["VOX_DEMO_RECORDING"] == "1")
    public func toggleCaptureModeDuringRecording() { guard case .recording = captureState else { return }; updatePreferredCaptureMode(selectedCaptureMode == .text ? .todo : .text) }
    public func cancelCapture() {
        captureGeneration = UUID()
        stopElapsedTimer()
        if !isDemoRecordingEnabled {
            recordingUseCase?.cancelRecording()
            transcriptionUseCase?.clearLiveText()
        }
        appendingTargetTodoID = nil
        liveTranscription = ""
        streamingRefinedText = ""
        captureState = .idle
        recordingElapsedSeconds = 0
        audioLevel = 0
        NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingEnded"), object: nil)
    }
    public func finishCapture() {
        #if os(iOS)
        let source: DeviceSource = .iPhone
        #else
        let source: DeviceSource = .mac
        #endif
        Task { await completeCapture(deviceSource: source) }
    }
    public func completeCapture(rawTranscript: String = "", refinedText: String = "", localAudioFileName: String? = nil, durationSeconds: TimeInterval = 0, deviceSource: DeviceSource = .mac) async {
        guard isRecordingActive, !isCompletingCapture else { return }
        isCompletingCapture = true
        defer { isCompletingCapture = false }
        let generation = captureGeneration
        let started = await captureStartTask?.value ?? true
        guard started, captureGeneration == generation, isRecordingActive else {
            if !isRecordingActive {
                NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingEnded"), object: nil)
            }
            return
        }
        stopElapsedTimer()
        let mode: CaptureMode = { if case .recording(let mode) = captureState { return mode }; return selectedCaptureMode }()
        captureState = .transcribing
        NotificationCenter.default.post(
            name: Notification.Name("vox.liveActivity.phaseUpdated"),
            object: nil,
            userInfo: [
                "phase": "transcribing",
                "mode": mode.rawValue,
                "title": "语音转译中…",
                "hex": "#578FE6"
            ]
        )
        let stoppedDuration = recordingUseCase?.state.duration ?? durationSeconds
        if !isDemoRecordingEnabled, let recordingUseCase {
            do {
                try await recordingUseCase.stopRecording()
            } catch {
                captureState = .failed(stage: .recording, reason: error.localizedDescription)
                NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingEnded"), object: nil)
                return
            }
        }
        if !isDemoRecordingEnabled, let transcriptionUseCase {
            do {
                try await transcriptionUseCase.commitCurrentTranscription()
            } catch {
                captureState = .failed(stage: .asr, reason: error.localizedDescription)
                NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingEnded"), object: nil)
                return
            }
        }
        do {
            let recorded = try await captureRecorder?(mode)
            let fallbackRaw = (isDemoRecordingEnabled ? liveTranscription : editingUseCase?.currentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = (recorded?.rawTranscript ?? (!rawTranscript.isEmpty ? rawTranscript : fallbackRaw)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                appendingTargetTodoID = nil
                liveTranscription = ""
                streamingRefinedText = ""
                latestCompletedText = ""
                lastCopiedBannerText = "未检测到语音，按住底部麦克风重新说话。"
                captureState = .idle
                NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingEnded"), object: nil)
                return
            }
            var refined = recorded?.refinedText ?? refinedText
            if isDemoRecordingEnabled && refined.isEmpty {
                if appendingTargetTodoID != nil {
                    refined = "核对双按钮极简底栏在降低透明度模式下的对比度"
                } else {
                    refined = "播客开场灵感：从一封深夜收到的听众来信切入，顺势引出本期关于「慢下来思考」的核心主题。"
                }
            }
            guard captureGeneration == generation else { return }
            captureState = .refining(mode: mode)
            NotificationCenter.default.post(
                name: Notification.Name("vox.liveActivity.phaseUpdated"),
                object: nil,
                userInfo: [
                    "phase": "refining",
                    "mode": mode.rawValue,
                    "title": "AI 提炼中…",
                    "subtitle": String(raw.prefix(40)),
                    "hex": "#9480E6"
                ]
            )
            if refined.isEmpty, let refinementUseCase, refinementUseCase.isConfigured {
                try await refinementUseCase.refine(customPrompt: nil)
                if let current = editingUseCase?.currentText, !current.isEmpty {
                    refined = current
                }
            }
            guard captureGeneration == generation else { return }
            let audio = recorded?.localAudioFileName ?? localAudioFileName
            let duration = recorded?.durationSeconds ?? stoppedDuration
            let targetAppendID = appendingTargetTodoID
            appendingTargetTodoID = nil
            if let targetAppendID, todos.contains(where: { $0.id == targetAppendID }) {
                let appended = try await appendVoiceCaptureToTodo(
                    targetAppendID,
                    subtaskTitle: refined.isEmpty ? raw : refined,
                    rawTranscript: raw,
                    localAudioFileName: audio,
                    durationSeconds: duration,
                    deviceSource: deviceSource
                )
                latestCompletedText = (refined.isEmpty ? raw : refined).trimmingCharacters(in: .whitespacesAndNewlines)
                lastCopiedBannerText = "已补充至待办 · \(appended.title)"
                NotificationCenter.default.post(
                    name: Notification.Name("vox.liveActivity.completedReceipt"),
                    object: nil,
                    userInfo: [
                        "phase": "completedReceipt",
                        "mode": mode.rawValue,
                        "todoID": appended.id.uuidString,
                        "title": appended.title,
                        "priority": appended.priority.rawValue,
                        "completedSubtasks": appended.subtasks.filter(\.isCompleted).count,
                        "totalSubtasks": appended.subtasks.count,
                        "hex": "#57BD99"
                    ]
                )
                captureState = .completed
                captureState = .idle
                return
            }
            let outcome = try await useCase.recordCompletedCapture(mode: mode, rawTranscript: raw, refinedText: refined, localAudioFileName: audio, durationSeconds: duration, deviceSource: deviceSource)
            await reload()
            let finalCopyText = (outcome.capture.refinedText.isEmpty ? outcome.capture.rawTranscript : outcome.capture.refinedText).trimmingCharacters(in: .whitespacesAndNewlines)
            if mode == .text {
                if !finalCopyText.isEmpty {
                    onCopyTextToClipboard?(finalCopyText)
                }
                lastCopiedBannerText = "已复制到剪贴板 · 可直接粘贴"
            } else if let todo = outcome.todo {
                lastCopiedBannerText = "已存入待办 · \(todo.title)"
            } else {
                lastCopiedBannerText = "已存入待办"
            }
            latestCompletedText = finalCopyText
            NotificationCenter.default.post(
                name: Notification.Name("vox.liveActivity.completedReceipt"),
                object: nil,
                userInfo: [
                    "phase": "completedReceipt",
                    "mode": mode.rawValue,
                    "todoID": outcome.todo?.id.uuidString ?? "",
                    "title": outcome.todo?.title ?? String(finalCopyText.prefix(20)),
                    "priority": outcome.todo?.priority.rawValue ?? "P1",
                    "completedSubtasks": outcome.todo?.subtasks.filter(\.isCompleted).count ?? 0,
                    "totalSubtasks": outcome.todo?.subtasks.count ?? 0,
                    "hex": "#57BD99"
                ]
            )
            captureState = .completed
            captureState = .idle
        } catch {
            appendingTargetTodoID = nil
            captureState = .failed(stage: .ai, reason: error.localizedDescription)
            NotificationCenter.default.post(name: Notification.Name("vox.liveActivity.recordingEnded"), object: nil)
        }
    }

    @discardableResult
    public func appendVoiceCaptureToTodo(
        _ todoID: UUID,
        subtaskTitle: String,
        rawTranscript: String = "",
        localAudioFileName: String? = nil,
        durationSeconds: TimeInterval = 0,
        deviceSource: DeviceSource = .iPhone
    ) async throws -> VoiceTodo {
        let cleaned = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRaw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleaned : rawTranscript
        _ = try await useCase.recordCompletedCapture(
            mode: .text,
            rawTranscript: effectiveRaw,
            refinedText: cleaned,
            localAudioFileName: localAudioFileName,
            durationSeconds: durationSeconds,
            deviceSource: deviceSource
        )
        guard let current = todos.first(where: { $0.id == todoID }) else {
            await reload()
            guard let reloaded = todos.first(where: { $0.id == todoID }) else {
                throw VoiceTodoUseCaseError.todoNotFound
            }
            let updated = reloaded.withAppendedSubtask(cleaned)
            let saved = try await useCase.updateTodo(updated)
            if let newestSubtaskID = saved.subtasks.last?.id {
                var existing = voiceAppendedSubtaskIDs[todoID] ?? []
                if !existing.contains(newestSubtaskID) {
                    existing.append(newestSubtaskID)
                    voiceAppendedSubtaskIDs[todoID] = existing
                }
            }
            await reload()
            lastCopiedBannerText = "已补充至待办 · \(saved.title)"
            return saved
        }
        let updated = current.withAppendedSubtask(cleaned)
        let saved = try await useCase.updateTodo(updated)
        if let newestSubtaskID = saved.subtasks.last?.id {
            var existing = voiceAppendedSubtaskIDs[todoID] ?? []
            if !existing.contains(newestSubtaskID) {
                existing.append(newestSubtaskID)
                voiceAppendedSubtaskIDs[todoID] = existing
            }
        }
        await reload()
        lastCopiedBannerText = "已补充至待办 · \(saved.title)"
        return saved
    }

    public func updateTodoTitle(todoID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }), todo.title != trimmed else { return }
            let updated = todo.withTitle(trimmed)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func updateTodoDescription(todoID: UUID, description: String) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }), todo.description != trimmed else { return }
            let updated = todo.withDescription(trimmed)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func updateTodoStatus(todoID: UUID, state: TodoExecutionState) {
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            if state == .done {
                _ = try await useCase.markTodoDone(todoID: todoID)
                await reload()
                lastCopiedBannerText = "已完成待办 · \(todo.title)"
            } else {
                let updated = todo.withExecutionState(
                    state,
                    startedAt: state == .running ? (todo.lastStartedAt ?? Date()) : todo.lastStartedAt,
                    completedAt: nil
                )
                _ = try await useCase.updateTodo(updated)
                await reload()
            }
        }
    }

    public func cycleTodoStatus(todoID: UUID) {
        guard let todo = todos.first(where: { $0.id == todoID }) else { return }
        let nextState: TodoExecutionState
        switch todo.executionState {
        case .inbox, .failed:
            nextState = .running
        case .running:
            nextState = .done
        case .done:
            nextState = .inbox
        }
        updateTodoStatus(todoID: todoID, state: nextState)
    }

    public func toggleTodoSubtask(todoID: UUID, subtaskID: UUID) {
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            let updated = todo.withToggledSubtask(subtaskID)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func updateTodoSubtaskTitle(todoID: UUID, subtaskID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            let updated = todo.withUpdatedSubtaskTitle(subtaskID, title: trimmed)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func appendSubtask(to todoID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            let updated = todo.withAppendedSubtask(trimmed)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func updateTodoPriority(todoID: UUID, priority: TodoPriority) {
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            let updated = todo.withPriority(priority)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func cycleTodoPriority(todoID: UUID) {
        guard let todo = todos.first(where: { $0.id == todoID }) else { return }
        let nextPriority: TodoPriority
        switch todo.priority {
        case .p0: nextPriority = .p1
        case .p1: nextPriority = .p2
        case .p2: nextPriority = .p0
        }
        updateTodoPriority(todoID: todoID, priority: nextPriority)
    }

    public func toggleTodoTag(todoID: UUID, tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let formatted = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            if !todo.tags.contains(formatted) && todo.tags.count >= 3 {
                lastCopiedBannerText = "最多 3 个标签 · 点按已有标签可移除"
                return
            }
            let updated = todo.withToggledTag(formatted)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func rescheduleTodoReminder(todoID: UUID, newDate: Date, timeSlot: String? = nil) {
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            let updated = try await useCase.rescheduleTodoReminder(todoID: todoID, newDate: newDate, timeSlot: timeSlot)
            await reload()
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            lastCopiedBannerText = "已更新提醒时间 · \(fmt.string(from: updated.scheduledAt ?? newDate)) (\(todo.title))"
        }
    }

    public func shiftTodoReminderByMinutes(todoID: UUID, deltaMinutes: Int) {
        guard let todo = todos.first(where: { $0.id == todoID }) else { return }
        let baseDate = todo.scheduledAt ?? Date().addingTimeInterval(3600)
        let newDate = baseDate.addingTimeInterval(TimeInterval(deltaMinutes * 60))
        rescheduleTodoReminder(todoID: todoID, newDate: newDate, timeSlot: todo.timeSlot)
    }

    public func assignTodoHabitSlot(todoID: UUID, slotRawValue: String) {
        let cal = Calendar.current
        let now = Date()
        let defaultMinutes: Int
        switch slotRawValue {
        case "morning":   defaultMinutes = 540  // 09:00
        case "forenoon":  defaultMinutes = 600  // 10:00
        case "noon":      defaultMinutes = 750  // 12:30
        case "afternoon": defaultMinutes = 900  // 15:00
        case "evening":   defaultMinutes = 1110 // 18:30
        case "night":     defaultMinutes = 1230 // 20:30
        default:          defaultMinutes = 540
        }
        let startOfToday = cal.startOfDay(for: now)
        var target = cal.date(byAdding: .minute, value: defaultMinutes, to: startOfToday) ?? now.addingTimeInterval(3600)
        if target <= now.addingTimeInterval(60) {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86_400)
        }
        rescheduleTodoReminder(todoID: todoID, newDate: target, timeSlot: slotRawValue)
    }

    public func clearTodoReminder(todoID: UUID) {
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            let updated = todo.withReminder(scheduledAt: nil, timeSlot: nil)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func addTodoTag(todoID: UUID, tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let formatted = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            if !todo.tags.contains(formatted) && todo.tags.count >= 3 {
                lastCopiedBannerText = "最多 3 个标签 · 点按已有标签可移除"
                return
            }
            let updated = todo.withAddedTag(formatted)
            _ = try await useCase.updateTodo(updated)
            await reload()
        }
    }

    public func copyTodoContent(_ todo: VoiceTodo) {
        let subtaskLines = todo.subtasks.map { "- [\($0.isCompleted ? "x" : " ")] \($0.title)" }.joined(separator: "\n")
        var sections = [todo.title]
        if !todo.description.isEmpty {
            sections.append(todo.description)
        }
        if !subtaskLines.isEmpty {
            sections.append(subtaskLines)
        }
        let body = sections.joined(separator: "\n")
        onCopyTextToClipboard?(body)
        lastCopiedBannerText = "已复制待办 · \(todo.title)"
    }

    public func syncTodoToLinear(_ todoID: UUID) {
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            let synced = try await useCase.syncTodoToExternal(todoID: todoID)
            await reload()
            lastCopiedBannerText = "已同步 Linear · \(synced.externalSync?.externalID ?? todo.title)"
        }
    }

    public func aiOrder(for todoID: UUID) -> ICloudAIExecutionOrder? {
        aiOrdersByTodoID[todoID]
    }

    public func applyAIExecutionStatusReport(_ report: AIExecutionStatusReport) async {
        let existing = aiOrdersByTodoID[report.todoID]
            ?? ICloudAIExecutionOrder(
                orderID: report.orderID,
                todoID: report.todoID,
                state: report.state,
                progressStage: report.progressStage,
                progressFraction: report.progressFraction,
                outputSummary: report.outputSummary,
                assignedRunnerName: report.assignedRunnerName,
                updatedAt: report.updatedAt
            )
        let updatedOrder = existing.applying(report)
        aiOrdersByTodoID[report.todoID] = updatedOrder
        await reload()
        switch report.state {
        case .queued:
            lastCopiedBannerText = "已上传 iCloud · 等待 Mac 接单"
        case .claimedByMac, .running:
            lastCopiedBannerText = "Mac 已接单 · \(report.progressStage)"
        case .completed:
            lastCopiedBannerText = "AI 已完成 · \(report.outputSummary ?? report.progressStage)"
        case .failed:
            lastCopiedBannerText = "AI 执行失败 · \(report.outputSummary ?? report.progressStage)"
        }
    }

    public func dispatchTodoToICloudAI(_ todoID: UUID) {
        guard let todo = todos.first(where: { $0.id == todoID }) else { return }
        aiOrderProgressTasks[todoID]?.cancel()
        aiOrderProgressTasks[todoID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let queued = try await useCase.dispatchTodoToICloudAI(todoID: todoID)
                self.aiOrdersByTodoID[todoID] = queued
                await self.reload()
                self.lastCopiedBannerText = "已上传 iCloud · 等待 Mac 接单 (\(todo.title))"
            } catch {
                let failed = ICloudAIExecutionOrder(from: todo).sanitizedForCloudSync().withState(
                    .failed,
                    progressStage: "执行失败",
                    progressFraction: 1.0,
                    outputSummary: error.localizedDescription
                )
                self.aiOrdersByTodoID[todoID] = failed
                self.lastCopiedBannerText = "AI 派单失败 · \(error.localizedDescription)"
            }
        }
    }

    public func toggleTodoDone(_ todoID: UUID) {
        perform { [weak self] in
            guard let self, let todo = todos.first(where: { $0.id == todoID }) else { return }
            if todo.executionState == .done {
                _ = try await useCase.updateTodo(todo.withExecutionState(.inbox, completedAt: nil))
                await reload()
            } else {
                _ = try await useCase.markTodoDone(todoID: todoID)
                await reload()
                lastCopiedBannerText = "已完成待办 · \(todo.title)"
            }
        }
    }

    public func deleteTodo(_ todoID: UUID) {
        perform { [weak self] in
            guard let self else { return }
            try await useCase.deleteTodo(id: todoID)
            await reload()
        }
    }

    public func prepareDemoRefinedState() async {
        await reloadTask?.value
        latestCompletedText = "播客开场灵感：从一封深夜收到的听众来信切入，顺势引出本期关于「慢下来思考」的核心主题。"
        lastCopiedBannerText = "润色完成 · 点按文字即可复制"
    }

    public func copyLatestCompletedText() {
        guard !latestCompletedText.isEmpty else { return }
        onCopyTextToClipboard?(latestCompletedText)
        lastCopiedBannerText = "已复制到剪贴板 · 可直接粘贴"
    }

    public func copyCaptureText(_ capture: VoiceCapture) {
        let content = (capture.refinedText.isEmpty ? capture.rawTranscript : capture.refinedText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        onCopyTextToClipboard?(content)
        lastCopiedBannerText = "已复制到剪贴板 · 可直接粘贴"
    }

    public func convertCaptureToTodo(_ captureID: UUID) { perform { [weak self] in guard let self else { return }; let todo = try await useCase.convertCaptureToTodo(captureID: captureID); await reload(); lastCopiedBannerText = "已转为待办 · \(todo.title)" } }
    public func retryCapture(_ captureID: UUID, mode: CaptureMode? = nil) { perform { [weak self] in guard let self else { return }; _ = try await useCase.retryCapture(id: captureID, targetMode: mode); await reload() } }
    public func runTodoWithAI(_ todoID: UUID, projectID: UUID?, runnerKind: AIRunnerKind? = nil) { perform { [weak self] in guard let self, let project = projectID.flatMap({ id in projectBindings.first(where: { $0.id == id }) }) ?? projectBindings.first else { return }; let template = runnerTemplates.first(where: { $0.kind == runnerKind }) ?? runnerTemplates.first(where: { $0.kind == project.defaultRunnerKind }) ?? AIRunnerTemplate.herdrDefault; _ = try await useCase.runTodoWithAI(todoID: todoID, project: project, template: template); await reload() } }
    public func saveTodoEdits(id: UUID, title: String, taskPrompt: String, projectKey: String?, runnerKind: AIRunnerKind? = nil) { perform { [weak self] in guard let self, let todo = todos.first(where: { $0.id == id }) else { return }; _ = try await useCase.updateTodo(todo.withEdits(title: title, taskPrompt: taskPrompt, projectKey: projectKey, assignedRunnerKind: runnerKind)); await reload() } }
    public func addProjectBinding(_ binding: ProjectBinding) { projectBindings.append(binding) }
    public func removeProjectBinding(id: UUID) { projectBindings.removeAll { $0.id == id } }
    public func updateRunnerTemplate(_ template: AIRunnerTemplate) { runnerTemplates.removeAll { $0.kind == template.kind }; runnerTemplates.append(template) }

    private func applySidebarSelection(_ section: WorkspaceSidebarSection) {
        switch section {
        case .todoInbox: selectedTodoFilter = .inbox; selectedProjectFilter = nil
        case .todoRunning: selectedTodoFilter = .running; selectedProjectFilter = nil
        case .todoDone: selectedTodoFilter = .done; selectedProjectFilter = nil
        case .todoAll: selectedTodoFilter = .all; selectedProjectFilter = nil
        case .project(let key): selectedTodoFilter = .all; selectedProjectFilter = key
        case .voiceNotes: break
        }
    }
    public func seedDemoDataIfEmptyForPreview() async {
        await reloadTask?.value
        await reload()
        guard todos.isEmpty && captures.isEmpty else {
            if !todos.contains(where: { $0.title.contains("液态玻璃") || $0.title.contains("整理下周设计评审") }) {
                let first = try? await useCase.recordCompletedCapture(
                    mode: .todo,
                    rawTranscript: "整理下周设计评审要展示的液态玻璃交互走查清单",
                    refinedText: "整理下周设计评审要展示的液态玻璃交互走查清单",
                    localAudioFileName: nil,
                    durationSeconds: 6,
                    deviceSource: .iPhone
                )
                if let firstTodo = first?.todo {
                    let enrichedFirst = firstTodo
                        .withTitle("液态玻璃交互走查")
                        .withDescription("整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单")
                        .withPriority(.p0)
                        .withTags(["#VoxPocket", "#iOS", "#Glass"])
                        .withAppendedSubtask("录制录音页默认空态与实时转写声波走查")
                        .withAppendedSubtask("验证左下切换与右下录音双按钮侧滑手势")
                    _ = try? await useCase.updateTodo(enrichedFirst)
                }
            }
            if !todos.contains(where: { $0.title.contains("播客大纲") || $0.title.contains("把早间散步录下的播客大纲") }) {
                let second = try? await useCase.recordCompletedCapture(
                    mode: .todo,
                    rawTranscript: "把早间散步录下的播客大纲润色后发给搭档确认",
                    refinedText: "把早间散步录下的播客大纲润色后发给搭档确认",
                    localAudioFileName: nil,
                    durationSeconds: 8,
                    deviceSource: .iPhone
                )
                if let secondTodo = second?.todo {
                    let enrichedSecond = secondTodo
                        .withTitle("早间播客大纲润色")
                        .withDescription("把早间散步录下的播客大纲润色后发给搭档确认，重点核对听众来信切入段")
                        .withPriority(.p1)
                        .withTags(["#Podcast", "#AI"])
                        .withAppendedSubtask("补充听众深夜来信的开场引子")
                    _ = try? await useCase.updateTodo(enrichedSecond)
                    _ = try? await useCase.markTodoDone(todoID: secondTodo.id)
                }
            }
            if !captures.contains(where: { $0.refinedText.contains("好的工具应当像空气一样安静") }) {
                _ = try? await useCase.recordCompletedCapture(
                    mode: .text,
                    rawTranscript: "傍晚路过书店读到一句话：好的工具应当像空气一样安静，只在你需要开口时浮现光亮。",
                    refinedText: "傍晚路过书店读到一句话：好的工具应当像空气一样安静，只在你需要开口时浮现光亮。",
                    localAudioFileName: nil,
                    durationSeconds: 5,
                    deviceSource: .iPhone
                )
            }
            await reload()
            if let firstTodo = todos.first(where: { $0.title.contains("液态玻璃") || $0.title.contains("整理下周设计评审") }),
               let lastSubtaskID = firstTodo.subtasks.last?.id,
               voiceAppendedSubtaskIDs[firstTodo.id] == nil {
                voiceAppendedSubtaskIDs[firstTodo.id] = [lastSubtaskID]
            }
            latestCompletedText = "傍晚路过书店读到一句话：好的工具应当像空气一样安静，只在你需要开口时浮现光亮。"
            lastCopiedBannerText = "已存入待办 · 可随时按操作按钮继续录入"
            return
        }
        let first = try? await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "整理下周设计评审要展示的液态玻璃交互走查清单",
            refinedText: "整理下周设计评审要展示的液态玻璃交互走查清单",
            localAudioFileName: nil,
            durationSeconds: 6,
            deviceSource: .iPhone
        )
        if let firstTodo = first?.todo {
            let enrichedFirst = firstTodo
                .withTitle("液态玻璃交互走查")
                .withDescription("整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单")
                .withPriority(.p0)
                .withTags(["#VoxPocket", "#iOS", "#Glass"])
                .withAppendedSubtask("录制录音页默认空态与实时转写声波走查")
                .withAppendedSubtask("验证左下切换与右下录音双按钮侧滑手势")
            if let savedFirst = try? await useCase.updateTodo(enrichedFirst),
               let lastSubtaskID = savedFirst.subtasks.last?.id {
                voiceAppendedSubtaskIDs[savedFirst.id] = [lastSubtaskID]
            }
        }
        let second = try? await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "把早间散步录下的播客大纲润色后发给搭档确认",
            refinedText: "把早间散步录下的播客大纲润色后发给搭档确认",
            localAudioFileName: nil,
            durationSeconds: 8,
            deviceSource: .iPhone
        )
        if let secondTodo = second?.todo {
            let enrichedSecond = secondTodo
                .withTitle("早间播客大纲润色")
                .withDescription("把早间散步录下的播客大纲润色后发给搭档确认，重点核对听众来信切入段")
                .withPriority(.p1)
                .withTags(["#Podcast", "#AI"])
                .withAppendedSubtask("补充听众深夜来信的开场引子")
            _ = try? await useCase.updateTodo(enrichedSecond)
            _ = try? await useCase.markTodoDone(todoID: secondTodo.id)
        }
        _ = try? await useCase.recordCompletedCapture(
            mode: .text,
            rawTranscript: "傍晚路过书店读到一句话：好的工具应当像空气一样安静，只在你需要开口时浮现光亮。",
            refinedText: "傍晚路过书店读到一句话：好的工具应当像空气一样安静，只在你需要开口时浮现光亮。",
            localAudioFileName: nil,
            durationSeconds: 5,
            deviceSource: .iPhone
        )
        await reload()
        lastCopiedBannerText = "已存入待办 · 可随时按操作按钮继续录入"
    }

    public func reload() async {
        do {
            captures = try await useCase.fetchCaptures()
            todos = try await useCase.fetchTodos()
            if let latest = captures.filter({ $0.state == .completed }).max(by: { $0.createdAt < $1.createdAt }) {
                latestCompletedText = (latest.refinedText.isEmpty ? latest.rawTranscript : latest.refinedText).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch { }
    }
    private func loadPreferredCaptureDestination(defaultMode: CaptureMode) async {
        if let stored: CaptureMode = await preferencesStore.getValue(for: .iosQuickCaptureDestination) {
            selectedCaptureMode = stored
        } else {
            selectedCaptureMode = defaultMode
        }
    }
    private func bindRecordingTelemetry() {
        recordingUseCase?.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, !isDemoRecordingEnabled else { return }
                audioLevel = level
            }
            .store(in: &subscriptions)
        transcriptionUseCase?.liveTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, !isDemoRecordingEnabled else { return }
                liveTranscription = text
            }
            .store(in: &subscriptions)
        editingUseCase?.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, !isDemoRecordingEnabled else { return }
                if isProcessingCapture { streamingRefinedText = text }
            }
            .store(in: &subscriptions)
    }
    private func startElapsedTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isRecordingActive else { break }
                self.recordingElapsedSeconds += 1
                NotificationCenter.default.post(
                    name: Notification.Name("vox.liveActivity.elapsedUpdated"),
                    object: nil,
                    userInfo: ["seconds": self.recordingElapsedSeconds, "mode": self.selectedCaptureMode.rawValue]
                )
            }
        }
    }
    private func stopElapsedTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
    private func perform(_ operation: @escaping () async throws -> Void) { Task { do { try await operation() } catch { captureState = .failed(stage: .ai, reason: error.localizedDescription) } } }
    private func count(_ state: TodoExecutionState) -> Int { todos.filter { $0.executionState == state }.count }
    private func matches(_ todo: VoiceTodo) -> Bool { (selectedTodoFilter == .all || todo.executionState.rawValue == selectedTodoFilter.rawValue) && (selectedProjectFilter == nil || todo.projectKey == selectedProjectFilter) && (searchQuery.isEmpty || todo.title.localizedCaseInsensitiveContains(searchQuery) || todo.description.localizedCaseInsensitiveContains(searchQuery) || todo.taskPrompt.localizedCaseInsensitiveContains(searchQuery) || todo.rawTranscript.localizedCaseInsensitiveContains(searchQuery)) }
    private func ordered(_ lhs: Date, _ rhs: Date) -> Bool { sortOrder == .newestFirst ? lhs > rhs : lhs < rhs }
}
