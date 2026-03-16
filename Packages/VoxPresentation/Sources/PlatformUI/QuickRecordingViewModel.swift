#if os(macOS)
import Foundation
import Combine
import CoreModels
import LLMKit
import UseCases
import PlatformAdapters
import UIShared
import Observability

/// 快速录音 ViewModel
///
/// 轻量级 ViewModel，用于快速录音流程：
/// 按下开始录音 → 抬起停止 → LLM 优化 → 复制粘贴 → 完成
@MainActor
public final class QuickRecordingViewModel: ObservableObject {

    // MARK: - 依赖

    private let recordingUseCase: RecordingUseCase
    private let transcriptionUseCase: TranscriptionUseCase
    private let refinementUseCase: RefinementUseCase
    private let clipboardService: ClipboardService
    private let logger: Logger

    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?

    // MARK: - Published 状态

    @Published public var recorderStatus: RecorderStatus = .idle
    @Published public var liveTranscription: String = ""
    @Published public var refinedText: String = ""
    @Published public var errorMessage: String?

    /// 完成回调（参数为最终文本）
    public var onComplete: ((String) -> Void)?
    /// 无识别结果回调（如空转录）
    public var onNoResult: (() -> Void)?

    // MARK: - 内部状态

    public private(set) var rawTranscription: String = ""
    private var isProcessing: Bool = false
    private var isStartingRecordingInternal: Bool = false
    private var shouldStopAfterStart: Bool = false
    private var latestFinalTranscription: String = ""

    public var isStartingRecording: Bool {
        isStartingRecordingInternal
    }

    // MARK: - Init

    public init(
        recordingUseCase: RecordingUseCase,
        transcriptionUseCase: TranscriptionUseCase,
        refinementUseCase: RefinementUseCase,
        clipboardService: ClipboardService,
        logger: Logger? = nil
    ) {
        self.recordingUseCase = recordingUseCase
        self.transcriptionUseCase = transcriptionUseCase
        self.refinementUseCase = refinementUseCase
        self.clipboardService = clipboardService
        self.logger = logger ?? PrintLogger(subsystem: "QuickRecordingVM")

        bindUseCases()
    }

    // MARK: - 绑定 UseCase 发布者

    private func bindUseCases() {
        recordingUseCase.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isActive {
                    self.recorderStatus = .listening
                } else if !self.isProcessing {
                    self.recorderStatus = .idle
                }
            }
            .store(in: &cancellables)

        transcriptionUseCase.liveTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.liveTranscription = text
            }
            .store(in: &cancellables)

        transcriptionUseCase.finalResultPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] result in
                    guard let self else { return }
                    self.latestFinalTranscription = result.text
                }
            )
            .store(in: &cancellables)

        refinementUseCase.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isRefining {
                    self.recorderStatus = .refining
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 录音操作

    public func startRecording() async {
        // 允许从 .error 状态重试
        if recorderStatus == .error {
            recorderStatus = .idle
            errorMessage = nil
        }
        guard recorderStatus == .idle, !isStartingRecordingInternal else {
            logger.debug("Start recording ignored because recorder is busy")
            return
        }
        isStartingRecordingInternal = true
        shouldStopAfterStart = false

        // 重置状态
        liveTranscription = ""
        refinedText = ""
        rawTranscription = ""
        latestFinalTranscription = ""
        errorMessage = nil
        isProcessing = false
        transcriptionUseCase.clearLiveText()

        do {
            try await recordingUseCase.startRecording()
            isStartingRecordingInternal = false
            recorderStatus = .listening
            logger.debug("Recording started")

            if shouldStopAfterStart {
                shouldStopAfterStart = false
                await stopRecording()
            }
        } catch {
            isStartingRecordingInternal = false
            errorMessage = error.localizedDescription
            recorderStatus = .error
            logger.warning("Start recording failed: \(error.localizedDescription)")
        }
    }

    /// 停止录音并启动优化流程
    public func stopRecording() async {
        if isStartingRecordingInternal {
            shouldStopAfterStart = true
            logger.debug("Stop requested while start is in progress")
            return
        }

        guard recorderStatus == .listening else {
            logger.debug("Stop recording ignored because recorder is not listening")
            return
        }

        isProcessing = true
        recorderStatus = .transcribing

        let recognitionCompletionTask = makeRecognitionCompletionWaitTask()
        await Task.yield()

        do {
            try await recordingUseCase.stopRecording()
            _ = await recognitionCompletionTask.value
            rawTranscription = bestAvailableTranscription()
            liveTranscription = rawTranscription
            logger.log(.debug, "Recording stopped", context: [
                "transcription_length": rawTranscription.count
            ])

            guard !rawTranscription.isEmpty else {
                recorderStatus = .idle
                isProcessing = false
                onNoResult?()
                return
            }

            // 将转录文本提交到 EditingUseCase，供 RefinementUseCase 读取
            try await transcriptionUseCase.commitCurrentTranscription()

            recorderStatus = .refining
            await performRefinement()
        } catch {
            recognitionCompletionTask.cancel()
            errorMessage = error.localizedDescription
            recorderStatus = .error
            isProcessing = false
        }
    }

    public func cancelRecording() async {
        streamingTask?.cancel()
        streamingTask = nil
        refinementUseCase.cancel()

        if recorderStatus == .listening {
            try? await recordingUseCase.stopRecording()
        }

        recorderStatus = .idle
        isProcessing = false
        logger.debug("Recording cancelled")
    }

    // MARK: - LLM 优化 → 复制粘贴 → 完成

    private func makeRecognitionCompletionWaitTask(timeout: TimeInterval = 2.5) -> Task<Bool, Never> {
        Task { [transcriptionUseCase] in
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await event in transcriptionUseCase.lifecycleEventPublisher.values {
                        if event == .recognitionCompleted {
                            return true
                        }
                    }

                    return false
                }

                group.addTask {
                    try? await Task.sleep(for: .seconds(timeout))
                    return false
                }

                let value = await group.next() ?? false
                group.cancelAll()
                return value
            }
        }
    }

    private func bestAvailableTranscription() -> String {
        let finalText = latestFinalTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalText.isEmpty {
            return finalText
        }

        return liveTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performRefinement() async {
        let stream = refinementUseCase.refineStreaming(customPrompt: nil)

        streamingTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .chunk(let text):
                        // chunk 是累积的完整文本，直接替换
                        self.refinedText = text
                    case .state:
                        break
                    }
                }

                if !Task.isCancelled {
                    await self.completeWithText(self.refinedText)
                }
            } catch {
                if !Task.isCancelled {
                    // 优化失败，使用原始转录
                    await self.completeWithText(self.rawTranscription)
                }
            }
        }
    }

    /// 复制到剪贴板、模拟粘贴、触发完成回调
    private func completeWithText(_ text: String) async {
        guard !text.isEmpty else {
            recorderStatus = .idle
            isProcessing = false
            return
        }

        recorderStatus = .done

        clipboardService.copy(text)

        do {
            try await clipboardService.simulatePaste()
            logger.log(.debug, "Pasted refined text", context: [
                "text_length": text.count
            ])
        } catch {
            logger.log(.debug, "Paste simulation failed", context: [
                "error": error.localizedDescription
            ])
        }

        isProcessing = false
        onComplete?(text)
        recorderStatus = .idle
    }
}
#endif
