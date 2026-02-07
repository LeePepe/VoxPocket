#if os(macOS)
import Foundation
import Combine
import CoreModels
import LLMKit
import UseCases
import PlatformAdapters
import UIShared

/// 快速录音 ViewModel
///
/// 轻量级 ViewModel，用于快速录音流程：
/// 录音 → 转录 → 意图识别 → LLM 优化 → 粘贴
@MainActor
public final class QuickRecordingViewModel: ObservableObject {

    // MARK: - 依赖

    private let recordingUseCase: RecordingUseCase
    private let transcriptionUseCase: TranscriptionUseCase
    private let refinementUseCase: RefinementUseCase
    private let clipboardService: ClipboardService

    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?
    private var silenceDetectionTask: Task<Void, Never>?
    private var lastTranscriptionUpdate: Date = Date()

    // MARK: - 自动停止配置

    /// 转录文本停止更新后自动停止的时间阈值（秒）
    private let autoStopDuration: TimeInterval = 2.5

    // MARK: - Published 状态

    @Published public var recorderStatus: RecorderStatus = .idle
    @Published public var liveTranscription: String = ""
    @Published public var refinedText: String = ""
    @Published public var errorMessage: String?

    /// 完成回调
    public var onComplete: ((String) -> Void)?

    // MARK: - 内部状态

    private var rawTranscription: String = ""
    private var isProcessing: Bool = false

    // MARK: - Init

    public init(
        recordingUseCase: RecordingUseCase,
        transcriptionUseCase: TranscriptionUseCase,
        refinementUseCase: RefinementUseCase,
        clipboardService: ClipboardService
    ) {
        self.recordingUseCase = recordingUseCase
        self.transcriptionUseCase = transcriptionUseCase
        self.refinementUseCase = refinementUseCase
        self.clipboardService = clipboardService

        bindUseCases()
    }

    // MARK: - 绑定 UseCase 发布者

    private func bindUseCases() {
        // 录音状态
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

        // 实时转录
        transcriptionUseCase.liveTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.liveTranscription = text
                // 每次转录文本更新，重置自动停止计时
                if self.recorderStatus == .listening && !text.isEmpty {
                    self.scheduleAutoStop()
                }
            }
            .store(in: &cancellables)

        // 优化状态
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
        guard recorderStatus == .idle else {
            print("⚠️ [QuickRecording] Already recording or processing")
            return
        }

        // 重置状态
        liveTranscription = ""
        refinedText = ""
        rawTranscription = ""
        errorMessage = nil
        isProcessing = false

        do {
            try await recordingUseCase.startRecording()
            recorderStatus = .listening
            print("🎙️ [QuickRecording] Started recording")
        } catch {
            errorMessage = error.localizedDescription
            recorderStatus = .error
        }
    }

    public func stopRecording() async {
        guard recorderStatus == .listening else {
            print("⚠️ [QuickRecording] Not recording")
            return
        }

        // 取消自动停止计时
        silenceDetectionTask?.cancel()
        silenceDetectionTask = nil

        // 立即设置状态，防止延迟的转录结果重新触发 scheduleAutoStop
        isProcessing = true
        recorderStatus = .transcribing

        do {
            try await recordingUseCase.stopRecording()
            rawTranscription = liveTranscription
            print("⏹️ [QuickRecording] Stopped recording, got: \(rawTranscription.prefix(50))...")

            // 执行优化流程
            await processTranscription()
        } catch {
            errorMessage = error.localizedDescription
            recorderStatus = .error
            isProcessing = false
        }
    }

    public func cancelRecording() async {
        silenceDetectionTask?.cancel()
        silenceDetectionTask = nil
        streamingTask?.cancel()
        streamingTask = nil
        refinementUseCase.cancel()

        if recorderStatus == .listening {
            try? await recordingUseCase.stopRecording()
        }

        recorderStatus = .idle
        isProcessing = false
        print("❌ [QuickRecording] Cancelled")
    }

    // MARK: - 自动停止

    private func scheduleAutoStop() {
        silenceDetectionTask?.cancel()
        lastTranscriptionUpdate = Date()

        print("🔄 [QuickRecording] Transcription updated, resetting auto-stop timer")

        silenceDetectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.autoStopDuration))
                if !Task.isCancelled, self.recorderStatus == .listening {
                    print("⏹️ [QuickRecording] Auto-stopping after \(self.autoStopDuration)s of silence")
                    await self.stopRecording()
                }
            } catch {
                // Task 被取消
            }
        }
    }

    // MARK: - 处理流程

    private func processTranscription() async {
        guard !rawTranscription.isEmpty else {
            recorderStatus = .idle
            isProcessing = false
            return
        }

        recorderStatus = .refining

        // 执行意图识别和优化
        await performRefinement()
    }

    private func performRefinement() async {
        // 执行流式优化
        let stream = refinementUseCase.refineStreaming(customPrompt: nil)

        streamingTask = Task { [weak self] in
            guard let self else { return }
            var finalText = ""

            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .chunk(let text):
                        finalText += text
                        self.refinedText = finalText
                    case .state:
                        break
                    }
                }

                // 优化完成
                if !Task.isCancelled {
                    await self.handleRefinementComplete(finalText)
                }
            } catch {
                if !Task.isCancelled {
                    // 优化失败，使用原始转录
                    await self.handleRefinementComplete(self.rawTranscription)
                }
            }
        }
    }

    private func handleRefinementComplete(_ text: String) async {
        guard !text.isEmpty else {
            recorderStatus = .idle
            isProcessing = false
            return
        }

        recorderStatus = .done

        // 复制到剪贴板
        clipboardService.copy(text)

        // 模拟粘贴
        do {
            try await clipboardService.simulatePaste()
            print("✅ [QuickRecording] Pasted text: \(text.prefix(50))...")
        } catch {
            print("⚠️ [QuickRecording] Paste simulation failed: \(error)")
            // 粘贴失败，文本已在剪贴板中
        }

        isProcessing = false
        onComplete?(text)
    }
}
#endif
