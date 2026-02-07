import Foundation
import Combine
import CoreModels
import LLMKit
import UseCases

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

    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?
    private var silenceDetectionTask: Task<Void, Never>?
    private var lastTranscriptionUpdate: Date = Date()

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

    // MARK: - Init

    public init(
        recording: RecordingUseCase,
        transcription: TranscriptionUseCase,
        editing: EditingUseCase,
        history: HistoryUseCase,
        refinement: RefinementUseCase
    ) {
        self.recordingUseCase = recording
        self.transcriptionUseCase = transcription
        self.editingUseCase = editing
        self.historyUseCase = history
        self.refinementUseCase = refinement

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
                self.liveTranscription = text
                // 每次转录文本更新，重置自动停止计时
                if self.isRecording && !text.isEmpty {
                    self.scheduleAutoStop()
                }
            }
            .store(in: &cancellables)

        // 当前文本
        editingUseCase.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$text)

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

    public func startRecording() async {
        // 取消进行中的优化
        cancelRefinement()
        rawTranscription = ""
        streamingRefinedText = ""

        do {
            try await recordingUseCase.startRecording()
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

        do {
            try await recordingUseCase.stopRecording()
            // 将最新的实时转录提交到编辑区，避免 final 为空导致后续优化无文本
            try? await transcriptionUseCase.commitCurrentTranscription()
            // 冻结原始转录文本（使用最新的实时转录内容）
            rawTranscription = liveTranscription
            // 自动执行优化
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

        print("🔄 [Auto Stop] Transcription updated, resetting timer")

        // 启动新的自动停止任务
        silenceDetectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.autoStopDuration))
                // 如果任务没有被取消，说明超过阈值时间没有新的转录结果
                if !Task.isCancelled, self.isRecording {
                    print("⏹️ [Auto Stop] No transcription update for \(self.autoStopDuration)s, stopping recording")
                    await self.stopRecording()
                }
            } catch {
                // Task 被取消，不做处理
            }
        }
    }

    public func toggleRecording() async {
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
                        self.streamingRefinedText += text
                    case .state:
                        // 状态已经通过 statePublisher 自动同步
                        break
                    }
                }
                // 流结束：将优化结果提交到编辑器
                if !Task.isCancelled, !self.streamingRefinedText.isEmpty {
                    try? self.editingUseCase.replaceAll(with: self.streamingRefinedText)
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
