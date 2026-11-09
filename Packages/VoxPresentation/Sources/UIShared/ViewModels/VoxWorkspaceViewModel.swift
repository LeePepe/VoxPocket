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
    private var timerTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    @Published public private(set) var captures: [VoiceCapture] = []
    @Published public private(set) var todos: [VoiceTodo] = []
    @Published public private(set) var projectBindings: [ProjectBinding]
    @Published public private(set) var runnerTemplates: [AIRunnerTemplate]
    @Published public private(set) var captureState: CaptureSessionState = .idle
    @Published public var selectedCaptureMode: CaptureMode = .text
    @Published public private(set) var recordingElapsedSeconds = 0
    @Published public var audioLevel: Float = 0
    @Published public private(set) var lastCopiedBannerText: String?
    @Published public var playingCaptureID: UUID?
    @Published public var searchQuery = ""
    @Published public var selectedTodoFilter: TodoStatusFilter = .all
    @Published public var selectedProjectFilter: String?
    @Published public var sortOrder: WorkspaceSortOrder = .newestFirst
    @Published public var selectedSidebarSection: WorkspaceSidebarSection = .todoAll { didSet { applySidebarSelection(selectedSidebarSection) } }
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
    public var isRecordingActive: Bool { if case .recording = captureState { return true }; return false }
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
        startCapture(mode: selectedCaptureMode)
    }

    public func startCapture(mode: CaptureMode) {
        selectedCaptureMode = mode; captureState = .recording(mode: mode); recordingElapsedSeconds = 0; lastCopiedBannerText = nil
        startElapsedTimer()
        try? editingUseCase?.replaceAll(with: "")
        transcriptionUseCase?.clearLiveText()
        guard ProcessInfo.processInfo.environment["VOX_DEMO_RECORDING"] != "1" else { return }
        if let recordingUseCase {
            Task {
                do {
                    try await recordingUseCase.startRecording()
                } catch {
                    stopElapsedTimer()
                    captureState = .failed(stage: .recording, reason: error.localizedDescription)
                }
            }
        }
    }
    public func toggleCaptureModeDuringRecording() { guard case .recording = captureState else { return }; updatePreferredCaptureMode(selectedCaptureMode == .text ? .todo : .text) }
    public func cancelCapture() { stopElapsedTimer(); recordingUseCase?.cancelRecording(); transcriptionUseCase?.clearLiveText(); captureState = .idle; recordingElapsedSeconds = 0; audioLevel = 0 }
    public func finishCapture() {
        #if os(iOS)
        let source: DeviceSource = .iPhone
        #else
        let source: DeviceSource = .mac
        #endif
        Task { await completeCapture(deviceSource: source) }
    }
    public func completeCapture(rawTranscript: String = "", refinedText: String = "", localAudioFileName: String? = nil, durationSeconds: TimeInterval = 0, deviceSource: DeviceSource = .mac) async {
        stopElapsedTimer()
        let mode: CaptureMode = { if case .recording(let mode) = captureState { return mode }; return selectedCaptureMode }()
        captureState = .transcribing
        let stoppedDuration = recordingUseCase?.state.duration ?? durationSeconds
        if let recordingUseCase {
            do {
                try await recordingUseCase.stopRecording()
            } catch {
                captureState = .failed(stage: .recording, reason: error.localizedDescription)
                return
            }
        }
        if let transcriptionUseCase {
            do {
                try await transcriptionUseCase.commitCurrentTranscription()
            } catch {
                captureState = .failed(stage: .asr, reason: error.localizedDescription)
                return
            }
        }
        do {
            let recorded = try await captureRecorder?(mode)
            let fallbackRaw = (editingUseCase?.currentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = (recorded?.rawTranscript ?? (!rawTranscript.isEmpty ? rawTranscript : fallbackRaw)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                captureState = .failed(stage: .asr, reason: "No transcription content produced")
                return
            }
            var refined = recorded?.refinedText ?? refinedText
            captureState = .refining(mode: mode)
            if refined.isEmpty, let refinementUseCase, refinementUseCase.isConfigured {
                try await refinementUseCase.refine(customPrompt: nil)
                if let current = editingUseCase?.currentText, !current.isEmpty {
                    refined = current
                }
            }
            let audio = recorded?.localAudioFileName ?? localAudioFileName
            let duration = recorded?.durationSeconds ?? stoppedDuration
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
            captureState = .completed
            captureState = .idle
        } catch { captureState = .failed(stage: .ai, reason: error.localizedDescription) }
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
        await reload()
        guard todos.isEmpty && captures.isEmpty else {
            lastCopiedBannerText = "已存入待办 · 可随时按操作按钮继续录入"
            return
        }
        _ = try? await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "优化 iPhone 操作按钮一键语音录入与灵动岛实时声波反馈",
            refinedText: "优化 iPhone 操作按钮一键语音录入与灵动岛实时声波反馈",
            localAudioFileName: nil,
            durationSeconds: 6,
            deviceSource: .iPhone
        )
        let second = try? await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "在设置中切换录音完成后是直接存入待办还是自动复制到剪贴板",
            refinedText: "在设置中切换录音完成后是直接存入待办还是自动复制到剪贴板",
            localAudioFileName: nil,
            durationSeconds: 8,
            deviceSource: .iPhone
        )
        if let doneID = second?.todo?.id {
            _ = try? await useCase.markTodoDone(todoID: doneID)
        }
        await reload()
        lastCopiedBannerText = "已存入待办 · 可随时按操作按钮继续录入"
    }

    public func reload() async { do { captures = try await useCase.fetchCaptures(); todos = try await useCase.fetchTodos() } catch { } }
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
            .sink { [weak self] level in self?.audioLevel = level }
            .store(in: &subscriptions)
    }
    private func startElapsedTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isRecordingActive else { break }
                self.recordingElapsedSeconds += 1
            }
        }
    }
    private func stopElapsedTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
    private func perform(_ operation: @escaping () async throws -> Void) { Task { do { try await operation() } catch { captureState = .failed(stage: .ai, reason: error.localizedDescription) } } }
    private func count(_ state: TodoExecutionState) -> Int { todos.filter { $0.executionState == state }.count }
    private func matches(_ todo: VoiceTodo) -> Bool { (selectedTodoFilter == .all || todo.executionState.rawValue == selectedTodoFilter.rawValue) && (selectedProjectFilter == nil || todo.projectKey == selectedProjectFilter) && (searchQuery.isEmpty || todo.title.localizedCaseInsensitiveContains(searchQuery) || todo.taskPrompt.localizedCaseInsensitiveContains(searchQuery) || todo.rawTranscript.localizedCaseInsensitiveContains(searchQuery)) }
    private func ordered(_ lhs: Date, _ rhs: Date) -> Bool { sortOrder == .newestFirst ? lhs > rhs : lhs < rhs }
}
