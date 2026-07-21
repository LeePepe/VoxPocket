#if os(macOS)
import Foundation
import Combine
import CoreModels
import LLMKit
import UseCases
import PlatformAdapters
import UIShared
import LokiKit

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
    private let streamingCoordinator: (any StreamingInputCoordinator)?
    private let logger: Logger
    private let telemetryService: (any TelemetryService)?

    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?

    // MARK: - 计时

    private var sessionStartTime: Date?
    private var transcriptionEndTime: Date?

    // MARK: - Published 状态

    @Published public var recorderStatus: RecorderStatus = .idle
    @Published public var liveTranscription: String = ""
    @Published public var refinedText: String = ""
    @Published public var errorMessage: String?
    /// 归一化音频电平（0…1），驱动灵动岛波形；非录音时为 nil。
    @Published public var audioLevel: Float = 0

    /// 供波形使用的归一化电平：仅 listening 时有值，其余状态返回 nil（波形转不定态/静止）。
    public var normalizedAudioLevel: Double? {
        recorderStatus == .listening ? Double(max(0, min(1, audioLevel))) : nil
    }

    /// 完成回调（参数为最终文本）
    public var onComplete: ((String) -> Void)?
    /// 无识别结果回调（如空转录）
    public var onNoResult: (() -> Void)?

    // MARK: - 内部状态

    public private(set) var rawTranscription: String = ""
    private var isProcessing: Bool = false
    private var isStartingRecordingInternal: Bool = false
    private var shouldStopAfterStart: Bool = false

    public var isStartingRecording: Bool {
        isStartingRecordingInternal
    }

    public var showsLiveTranscription: Bool {
        guard !liveTranscription.isEmpty else { return false }

        switch recorderStatus {
        case .listening, .transcribing, .refining:
            return true
        case .idle, .done, .error:
            return false
        }
    }

    // MARK: - Init

    public init(
        recordingUseCase: RecordingUseCase,
        transcriptionUseCase: TranscriptionUseCase,
        refinementUseCase: RefinementUseCase,
        clipboardService: ClipboardService,
        streamingCoordinator: (any StreamingInputCoordinator)? = nil,
        logger: Logger? = nil,
        telemetryService: (any TelemetryService)? = nil
    ) {
        self.recordingUseCase = recordingUseCase
        self.transcriptionUseCase = transcriptionUseCase
        self.refinementUseCase = refinementUseCase
        self.clipboardService = clipboardService
        self.streamingCoordinator = streamingCoordinator
        self.logger = logger ?? PrintLogger(subsystem: "QuickRecordingVM")
        self.telemetryService = telemetryService

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

        // 音频电平 → 波形
        recordingUseCase.audioLevelPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)

        transcriptionUseCase.liveTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.liveTranscription = text
            }
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

        // 流式协调器：订阅已精炼的语音文本用于实时显示
        if let coordinator = streamingCoordinator {
            coordinator.refinedVoiceTextPublisher
                .sink { [weak self] text in
                    guard let self else { return }
                    // send() 从 MainActor 发出，直接更新 refinedText
                    self.refinedText = text
                    if !text.isEmpty {
                        self.recorderStatus = .refining
                    }
                }
                .store(in: &cancellables)
        }
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
        errorMessage = nil
        isProcessing = false
        transcriptionUseCase.clearLiveText()

        do {
            try await recordingUseCase.startRecording()
            isStartingRecordingInternal = false
            recorderStatus = .listening
            sessionStartTime = Date()
            logger.debug("Recording started")

            // 流式模式：启动协调器（设置语音锚点、激活快照门控）
            if let coordinator = streamingCoordinator {
                await coordinator.startStreaming()
            }

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

        // 先让出一次主线程执行片段，确保 receive(on: .main) 排队的 liveText 更新
        // 在“停止前快照”之前有机会落地，避免误判为无语音内容。
        await Task.yield()

        // await 之前 snapshot Apple Speech 是否已有内容。
        // 不能在 await 之后检查 liveTranscription：Apple Speech 结束时可能抛出错误，
        // DefaultTranscriptionUseCase 的 catch block 会发 ""，Combine 的
        // receive(on: .main) 会在 await 恢复时把 liveTranscription 覆盖为 ""，
        // 导致误判为无内容、触发 onNoResult、提前关窗、丢弃 Whisper 结果。
        let hadSpeechBeforeStop = !liveTranscription.isEmpty
        let liveTranscriptionSnapshot = liveTranscription
        let finalResultTask = makeFinalResultWaitTask(timeout: 15.0)

        do {
            try await recordingUseCase.stopRecording()

            // 如果停止前完全没有文字，立刻触发 onNoResult，无需等待识别收敛
            if !hadSpeechBeforeStop {
                finalResultTask.cancel()
                recorderStatus = .idle
                isProcessing = false
                logger.debug("stopRecording: no speech content before stop → calling onNoResult")
                onNoResult?()
                return
            }

            rawTranscription = await waitForCompletedTranscription(finalResultTask: finalResultTask, liveSnapshot: liveTranscriptionSnapshot)
            let now = Date()
            transcriptionEndTime = now
            liveTranscription = rawTranscription
            logger.log(.debug, "Recording stopped", context: [
                "transcription_length": rawTranscription.count,
                "transcription_preview": String(rawTranscription.prefix(30))
            ])
            if let start = sessionStartTime {
                let durationMs = Int(now.timeIntervalSince(start) * 1000)
                telemetryService?.track(
                    name: TelemetryEventName.transcriptionCompleted.rawValue,
                    properties: [
                        "duration_ms": String(durationMs),
                        "char_count": String(rawTranscription.count),
                        "source": "quick"
                    ]
                )
            }

            guard !rawTranscription.isEmpty else {
                streamingCoordinator?.cancel()
                recorderStatus = .idle
                isProcessing = false
                logger.debug("stopRecording: rawTranscription empty → calling onNoResult")
                onNoResult?()
                return
            }

            recorderStatus = .refining

            if let coordinator = streamingCoordinator {
                // 流式模式：等待协调器完成最后一次精炼
                await coordinator.stopStreaming()
                let outputText = ensureSentenceTerminator(refinedText.isEmpty ? rawTranscription : refinedText)
                await completeWithText(outputText)
            } else {
                // 非流式模式：提交转录后统一精炼
                // 将转录文本提交到 EditingUseCase，供 RefinementUseCase 读取
                try await transcriptionUseCase.commitCurrentTranscription()
                await performRefinement()
            }
        } catch {
            finalResultTask.cancel()
            errorMessage = error.localizedDescription
            recorderStatus = .error
            isProcessing = false
        }
    }

    public func cancelRecording() async {
        streamingTask?.cancel()
        streamingTask = nil
        streamingCoordinator?.cancel()
        refinementUseCase.cancel()

        if recorderStatus == .listening {
            try? await recordingUseCase.stopRecording()
        }

        recorderStatus = .idle
        isProcessing = false
        logger.debug("Recording cancelled")
    }

    // MARK: - LLM 优化 → 复制粘贴 → 完成

    /// 停止录音后，等待识别流的最终结果收敛，避免松手瞬间丢字。
    ///
    /// 优先等待 finalResultPublisher（包含 WhisperKit + LLM 合并结果），
    /// 超时后回退到轮询 liveTranscription 收敛；若 liveTranscription 被 Apple Speech
    /// 错误清空，则使用 liveSnapshot 兜底，避免丢弃已识别内容。
    private func waitForCompletedTranscription(
        finalResultTask: Task<String?, Never>,
        liveSnapshot: String = "",
        settleMaxWait: TimeInterval = 0.8
    ) async -> String {
        if let finalText = await finalResultTask.value {
            logger.debug("waitForCompletedTranscription: got finalResult '\(finalText.prefix(30))'")
            return finalText
        }

        logger.debug("waitForCompletedTranscription: finalResultTask timed out, falling back to settle (liveTranscription='\(self.liveTranscription.prefix(30))')")
        let settled = await waitForTranscriptionToSettle(maxWait: settleMaxWait)
        if !settled.isEmpty { return settled }
        if !liveSnapshot.isEmpty {
            logger.debug("waitForCompletedTranscription: settled empty, using liveSnapshot '\(liveSnapshot.prefix(30))'")
        }
        return liveSnapshot
    }

    /// 超时时间需覆盖完整的 WhisperKit 解码 + LLM 合并耗时（实测可达 ~2.6s）。
    /// stopRecording() 本身已 await 完整管道，因此 finalResultSubject.send() 必然在
    /// stopRecording() 返回前触发——只要本 Task 未超时即可收到。
    private func makeFinalResultWaitTask(timeout: TimeInterval = 15.0) -> Task<String?, Never> {
        let startTime = Date()
        return Task { [transcriptionUseCase, logger] in
            await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    do {
                        for try await result in transcriptionUseCase.finalResultPublisher.values {
                            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty {
                                let elapsed = Date().timeIntervalSince(startTime)
                                logger.debug("finalResultTask: received result after \(String(format: "%.2f", elapsed))s — '\(text.prefix(30))'")
                                return text
                            }
                        }
                    } catch {
                        return nil
                    }

                    return nil
                }

                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(timeout))
                    } catch {
                        logger.debug("finalResultTask: cancelled before timeout")
                        return nil
                    }
                    guard !Task.isCancelled else {
                        logger.debug("finalResultTask: cancelled before timeout")
                        return nil
                    }
                    let elapsed = Date().timeIntervalSince(startTime)
                    logger.debug("finalResultTask: timed out after \(String(format: "%.2f", elapsed))s (limit=\(timeout)s)")
                    return nil
                }

                let value = await group.next() ?? nil
                group.cancelAll()
                return value
            }
        }
    }

    private func waitForTranscriptionToSettle(
        maxWait: TimeInterval = 0.8,
        quietWindow: TimeInterval = 0.12,
        pollInterval: TimeInterval = 0.03
    ) async -> String {
        var lastSnapshot = liveTranscription
        var lastChange = Date()
        let deadline = Date().addingTimeInterval(maxWait)

        while Date() < deadline {
            try? await Task.sleep(for: .seconds(pollInterval))

            if liveTranscription != lastSnapshot {
                lastSnapshot = liveTranscription
                lastChange = Date()
                continue
            }

            if Date().timeIntervalSince(lastChange) >= quietWindow {
                break
            }
        }

        return liveTranscription
    }

    private func performRefinement() async {
        let refinementStart = Date()
        let metadata = TranscriptionMetadata(
            type: .final,
            confidence: nil,
            locale: transcriptionUseCase.currentLanguage
        )
        let stream = refinementUseCase.refineStreaming(
            customPrompt: nil,
            transcriptionMetadata: metadata
        )

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
                    let outputText = self.ensureSentenceTerminator(self.refinedText)
                    let refinementMs = Int(Date().timeIntervalSince(refinementStart) * 1000)
                    self.logger.log(.debug, "Refinement completed", context: [
                        "raw_length": self.rawTranscription.count,
                        "refined_length": self.refinedText.count,
                        "output_length": outputText.count,
                        "text_changed": outputText != self.rawTranscription
                    ])
                    self.telemetryService?.track(
                        name: TelemetryEventName.refinementCompleted.rawValue,
                        properties: [
                            "duration_ms": String(refinementMs),
                            "raw_length": String(self.rawTranscription.count),
                            "refined_length": String(outputText.count),
                            "source": "quick"
                        ]
                    )
                    await self.completeWithText(outputText)
                }
            } catch {
                if !Task.isCancelled {
                    // 优化失败，使用原始转录
                    let outputText = self.ensureSentenceTerminator(self.rawTranscription)
                    self.logger.log(.debug, "Refinement failed, fallback to raw transcription", context: [
                        "raw_length": self.rawTranscription.count,
                        "output_length": outputText.count,
                        "text_changed": outputText != self.rawTranscription
                    ])
                    await self.completeWithText(outputText)
                }
            }
        }
    }

    private static let sentenceTerminators = CharacterSet(charactersIn: ".!?。！？")
    private static let trailingClosers = CharacterSet(charactersIn: "\"'”’）)]】》」』")

    /// 确保输出文本有句末终止标点，避免模型偶发返回无标点结果。
    private func ensureSentenceTerminator(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard !Self.endsWithSentenceTerminator(trimmed) else { return trimmed }

        let code = transcriptionUseCase.currentLanguage.language.languageCode?.identifier ?? ""
        let terminator = code.hasPrefix("zh") ? "。" : "."
        return trimmed + terminator
    }

    private static func endsWithSentenceTerminator(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return false }

        var index = scalars.count - 1
        while trailingClosers.contains(scalars[index]), index > 0 {
            index -= 1
        }
        return sentenceTerminators.contains(scalars[index])
    }

    // DEBUG: 追踪 completeWithText 调用次数，排查双次粘贴问题
    private var completeCallCount = 0

    /// 复制到剪贴板、模拟粘贴、触发完成回调
    private func completeWithText(_ text: String) async {
        completeCallCount += 1
        logger.log(.debug, "completeWithText called", context: [
            "call_count": completeCallCount,
            "text_length": text.count,
            "text_preview": String(text.prefix(20))
        ])
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
                "text_length": text.count,
                "text_changed_from_raw": text != rawTranscription
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
