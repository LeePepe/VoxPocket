import Foundation
import Combine
import CoreModels
import LLMKit
import UseCases
import Observability
import PlatformAdapters
import TranscriptionKit

/// 编辑器 ViewModel
///
/// 桥接录音、转录、编辑、历史、优化用例到 `EditorViewState` 协议。
/// 录音停止后自动触发 polish 优化，同时支持手动选择其他优化类型。
@MainActor
public final class EditorViewModel: ObservableObject, EditorViewState {

    // MARK: - 依赖

    private let recordingUseCase: RecordingUseCase
    private let transcriptionUseCase: TranscriptionUseCase
    private let editingUseCase: EditingUseCase
    private let historyUseCase: HistoryUseCase
    private let refinementUseCase: RefinementUseCase
    private let clipboardService: ClipboardService?
    private let sessionUseCase: SessionUseCase?
    private let inboxService: (any ClaudeInboxService)?
    private let logger: Logger

    /// 用于在录音被阻止时显示 snackbar 通知（可选，由外部注入）
    public var snackbarService: (any SnackbarService)?

    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?
    private var silenceDetectionTask: Task<Void, Never>?
    private var lastTranscriptionUpdate: Date = Date()

    /// 防止录音操作重入的标志
    private var isRecordingOperationInProgress = false

    /// 录音前的 history undo 计数（用于取消时精确回退）
    private var undoCountBeforeRecording: Int = 0

    // MARK: - 自动停止配置

    /// 转录文本停止更新后自动停止的时间阈值（秒）
    private let autoStopDuration: TimeInterval = 2.5

    // MARK: - Published 状态

    @Published public var text: String = ""
    @Published public var isRecording: Bool = false
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var audioLevel: Float = 0
    @Published public var liveTranscription: String = ""
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false
    @Published public var isRefining: Bool = false
    @Published public var errorMessage: String?
    @Published public var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @Published public var rawTranscription: String = ""
    @Published public var streamingRefinedText: String = ""
    @Published public var autoCopiedText: String?

    // MARK: - Init

    public init(
        recording: RecordingUseCase,
        transcription: TranscriptionUseCase,
        editing: EditingUseCase,
        history: HistoryUseCase,
        refinement: RefinementUseCase,
        clipboard: ClipboardService? = nil,
        session: SessionUseCase? = nil,
        inbox: (any ClaudeInboxService)? = nil,
        logger: Logger? = nil
    ) {
        self.recordingUseCase = recording
        self.transcriptionUseCase = transcription
        self.editingUseCase = editing
        self.historyUseCase = history
        self.refinementUseCase = refinement
        self.clipboardService = clipboard
        self.sessionUseCase = session
        self.inboxService = inbox
        self.logger = logger ?? PrintLogger(subsystem: "EditorViewModel")

        bindUseCases()
    }

    // MARK: - 绑定 UseCase 发布者

    private func bindUseCases() {
        // 录音状态
        recordingUseCase.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.isRecording = state.isActive
                self.recordingDuration = state.duration ?? 0
                if self.isRecording && !self.liveTranscription.isEmpty {
                    self.scheduleAutoStop()
                }
            }
            .store(in: &cancellables)

        // 音频电平
        recordingUseCase.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)

        // 实时转录 + 自动停止检测
        transcriptionUseCase.liveTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.logger.log(.debug, "Received live transcription update", context: [
                    "length": text.count,
                    "is_recording": self.isRecording
                ])
                self.liveTranscription = text
                // 每次转录文本更新，重置自动停止计时
                if self.isRecording && !text.isEmpty {
                    self.scheduleAutoStop()
                } else {
                    self.logger.log(.debug, "Skipped auto-stop scheduling", context: [
                        "is_recording": self.isRecording,
                        "is_empty": text.isEmpty
                    ])
                }
            }
            .store(in: &cancellables)

        // 当前文本
        editingUseCase.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$text)

        // 会话切换：加载历史会话文本到编辑器
        sessionUseCase?.currentSessionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }

                // 切换会话时终止当前临时流，避免旧会话残留状态干扰
                self.cancelRefinement()
                self.liveTranscription = ""
                self.streamingRefinedText = ""
                self.rawTranscription = session?.rawText ?? ""

                do {
                    try self.editingUseCase.replaceAll(with: session?.displayText ?? "")
                    self.historyUseCase.clearHistory()
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
            .store(in: &cancellables)

        // 撤销/重做
        historyUseCase.canUndoPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$canUndo)

        historyUseCase.canRedoPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$canRedo)

        // 优化状态
        refinementUseCase.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.isRefining = state.isRefining
            }
            .store(in: &cancellables)
    }

    // MARK: - 录音操作

    /// 开始新的 session（清空所有内容）
    public func startNewSession() async {
        clearText()
        await startRecording()
    }

    /// 开始录音（智能判断续写 vs 新建）
    public func startRecording() async {
        // 记录录音前的 undo count（用于 cancel 时精确回退）
        undoCountBeforeRecording = historyUseCase.undoCount

        // 取消进行中的优化
        cancelRefinement()

        // 判断是否为续写模式（text 不为空则续写）
        let isAppendMode = !text.isEmpty

        // 清空临时状态（不管是新建还是续写）
        rawTranscription = ""
        streamingRefinedText = ""
        transcriptionUseCase.clearLiveText()
        liveTranscription = ""

        logger.log(.debug, "Start recording requested", context: [
            "mode": isAppendMode ? "append" : "new_session",
            "current_text_length": text.count
        ])

        do {
            try await recordingUseCase.startRecording()
        } catch VoxError.modelNotReady {
            snackbarService?.showWarning("本地模型正在加载中，请稍候再试")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopRecording() async {
        // 立即标记为非录音状态，防止新的转录触发 scheduleAutoStop
        // 这样可以阻止在停止过程中收到的延迟转录结果重新触发 auto stop
        let wasRecording = isRecording
        isRecording = false

        // 取消自动停止计时
        silenceDetectionTask?.cancel()
        silenceDetectionTask = nil

        // 防止重复调用 stopRecording
        guard wasRecording else { return }

        // 保存录音前是否有内容（用于判断续写模式）
        let hadPreviousContent = !text.isEmpty

        do {
            try await recordingUseCase.stopRecording()

            // 提交转录到编辑区
            if hadPreviousContent {
                // 续写模式：追加到现有文本 → History 记录 1
                let newText = liveTranscription
                logger.log(.debug, "Committing transcription in append mode", context: [
                    "previous_text_length": text.count,
                    "new_transcription_length": newText.count
                ])
                if !newText.isEmpty {
                    try? editingUseCase.append("\n" + newText)
                }
                logger.log(.debug, "Append mode commit completed", context: [
                    "current_text_length": editingUseCase.currentText.count
                ])
            } else {
                // New session 模式：替换全部 → History 记录 1
                logger.log(.debug, "Committing transcription in new session mode", context: [
                    "transcription_length": liveTranscription.count
                ])
                try? await transcriptionUseCase.commitCurrentTranscription()
            }

            // 冻结整个 text 用于优化（包括旧内容 + 新转录）
            rawTranscription = editingUseCase.currentText
            logger.log(.debug, "Prepared text for refinement", context: [
                "raw_text_length": rawTranscription.count
            ])

            // 自动执行优化（针对整个 text）
            await autoRefine()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 调度自动停止任务
    /// 每次转录文本更新时调用，重置计时器
    private func scheduleAutoStop() {
        // 取消之前的任务
        silenceDetectionTask?.cancel()

        // 更新最后更新时间
        lastTranscriptionUpdate = Date()

        logger.debug("Reset auto-stop timer after transcription update")

        // 启动新的自动停止任务
        silenceDetectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.autoStopDuration))
                // 如果任务没有被取消，说明超过阈值时间没有新的转录结果
                if !Task.isCancelled, self.isRecording {
                    self.logger.log(.debug, "Auto-stopping recording after inactivity", context: [
                        "duration_seconds": self.autoStopDuration
                    ])
                    await self.stopRecording()
                }
            } catch {
                // Task 被取消，不做处理
            }
        }
    }

    public func toggleRecording() async {
        // 防止重入：如果已有录音操作正在进行，忽略新的切换请求
        guard !isRecordingOperationInProgress else {
            logger.debug("toggleRecording() ignored - operation already in progress")
            return
        }

        isRecordingOperationInProgress = true
        defer { isRecordingOperationInProgress = false }

        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - 优化操作

    /// 自动触发优化
    private func autoRefine() async {
        guard !rawTranscription.isEmpty else { return }
        guard refinementUseCase.isConfigured else { return }
        await performStreaming()
    }

    public func refine() async {
        // 手动触发：如果没有 rawTranscription，使用当前 text
        if rawTranscription.isEmpty {
            rawTranscription = text
        }
        await performStreaming()
    }

    private func performStreaming() async {
        cancelRefinement()
        streamingRefinedText = ""

        let stream = refinementUseCase.refineStreaming(customPrompt: nil)

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .chunk(let text):
                        self.streamingRefinedText = text
                    case .state:
                        // 状态已经通过 statePublisher 自动同步
                        break
                    }
                }
                // 流结束：将优化结果提交到编辑器
                if !Task.isCancelled, !self.streamingRefinedText.isEmpty {
                    self.logger.log(.debug, "Refinement stream completed", context: [
                        "raw_text_length": self.rawTranscription.count,
                        "refined_text_length": self.streamingRefinedText.count
                    ])
                    try? self.editingUseCase.replaceAll(with: self.streamingRefinedText)
                    self.logger.log(.debug, "Applied refined text to editor", context: [
                        "current_text_length": self.editingUseCase.currentText.count
                    ])

                    // 自动复制精炼结果到剪贴板
                    self.clipboardService?.copy(self.streamingRefinedText)
                    self.autoCopiedText = self.streamingRefinedText
                    self.logger.log(.debug, "Auto-copied refined text", context: [
                        "text_length": self.streamingRefinedText.count
                    ])

                    // 保存会话到持久化存储
                    if let sessionUseCase = self.sessionUseCase {
                        Task {
                            try? await sessionUseCase.saveCompletedSession(
                                title: nil,
                                rawText: self.rawTranscription,
                                refinedText: self.streamingRefinedText
                            )
                        }
                    }

                    // 将优化结果写入 Claude inbox，触发自动计划流程
                    if let inboxService = self.inboxService {
                        Task {
                            try? await inboxService.appendToInbox(self.streamingRefinedText)
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func cancelRefinement() {
        streamingTask?.cancel()
        streamingTask = nil
        refinementUseCase.cancel()
    }

    /// 取消当前识别（回退到录音前状态）
    ///
    /// 取消正在进行的优化，并通过 undo 精确回退到录音前的状态。
    /// - New session: 回退到空白状态
    /// - 续写模式: 回退到续写前的状态
    ///
    /// 注意：当前 History 功能未实现，此方法暂时只清空临时状态
    public func cancelRecording() {
        // 取消正在进行的优化
        cancelRefinement()

        // 清空临时状态
        streamingRefinedText = ""
        rawTranscription = ""
        liveTranscription = ""

        // TODO: 当 History 实现后，使用以下代码精确回退：
        // let currentUndoCount = historyUseCase.undoCount
        // let stepsToUndo = currentUndoCount - undoCountBeforeRecording
        // for _ in 0..<stepsToUndo {
        //     if canUndo {
        //         try? historyUseCase.undo()
        //     }
        // }

        logger.debug("cancelRecording() called but History rollback is not implemented yet")
    }

    // MARK: - 编辑操作

    public func undo() {
        do {
            try historyUseCase.undo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func redo() {
        do {
            try historyUseCase.redo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateText(_ newText: String, range: NSRange) {
        let textRange = CoreModels.TextRange(location: range.location, length: range.length)
        do {
            try editingUseCase.applyEdit(range: textRange, newText: newText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 清除操作

    public func clearError() {
        errorMessage = nil
    }

    public func clearText() {
        cancelRefinement()
        rawTranscription = ""
        streamingRefinedText = ""
        do {
            try editingUseCase.replaceAll(with: "")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
