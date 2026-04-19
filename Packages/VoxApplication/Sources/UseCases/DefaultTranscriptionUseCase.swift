import Foundation
import Combine
import os
import TranscriptionKit
import LokiKit

/// 转录用例默认实现
///
/// 桥接 `TranscriptionCoordinator` 到 `TranscriptionUseCase` 协议。
/// 自动将最终识别结果追加到 `EditingUseCase`。
public final class DefaultTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {

    private let coordinator: TranscriptionCoordinator
    private let editingUseCase: EditingUseCase
    private let logger: any LokiKit.Logger
    private let telemetry: any TelemetryService

    private let liveTextSubject = CurrentValueSubject<String, Never>("")
    private let snapshotSubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var _currentLanguage: Locale
    private var lastCommittedText: String = ""

    // 快照门控：thread-safe，用 OSAllocatedUnfairLock 保护
    private let _snapshotGateLock = OSAllocatedUnfairLock(initialState: false)

    public var snapshotPublisher: AnyPublisher<String, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    public var snapshotGateActive: Bool {
        get { _snapshotGateLock.withLock { $0 } }
        set { _snapshotGateLock.withLock { $0 = newValue } }
    }

    public var liveTextPublisher: AnyPublisher<String, Never> {
        liveTextSubject.eraseToAnyPublisher()
    }

    public var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        coordinator.finalResultPublisher
    }

    public var currentLanguage: Locale { _currentLanguage }

    public var supportedLanguages: [Locale] {
        coordinator.speechRecognitionService.supportedLanguages
    }

    public init(
        coordinator: TranscriptionCoordinator,
        editing: EditingUseCase,
        language: Locale = Locale(identifier: "zh-Hans"),
        logger: (any LokiKit.Logger)? = nil,
        telemetry: any TelemetryService = NoopTelemetryService()
    ) {
        self.coordinator = coordinator
        self.editingUseCase = editing
        self._currentLanguage = language
        self.logger = logger ?? PrintLogger(subsystem: "TranscriptionUseCase")
        self.telemetry = telemetry

        bindCoordinator()
    }

    private func bindCoordinator() {
        // 实时转录 → liveTextSubject
        coordinator.liveResultPublisher
            .map(\.text)
            .removeDuplicates()
            .catch { [weak self] error -> Empty<String, Never> in
                self?.logger.error("❌ liveResultPublisher error: \(error.localizedDescription)")
                // Send empty string to clear live text, but don't complete the stream
                self?.liveTextSubject.send("")
                // Return Empty that never completes, allowing stream to continue
                return Empty(completeImmediately: false)
            }
            .sink { [weak self] text in
                guard let self else { return }
                self.logger.debug("📥 [TranscriptionUseCase] Received live result, sending to liveTextSubject: '\(text)'")
                self.liveTextSubject.send(text)
            }
            .store(in: &cancellables)

        // 最终结果 → 根据门控状态决定路由
        coordinator.finalResultPublisher
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] result in
                    guard let self else { return }
                    let newText = result.text
                    guard !newText.isEmpty else { return }
                    self.lastCommittedText = newText
                    let wordCount = newText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                    if self.snapshotGateActive {
                        // 流式模式：发布快照，由 StreamingInputCoordinator 消费；不写入 EditingUseCase
                        self.snapshotSubject.send(newText)
                    } else {
                        // 默认模式：用最终文本替换当前内容
                        do {
                            try self.editingUseCase.replaceAll(with: newText)
                        } catch {
                            self.logger.error("replaceAll failed: \(error.localizedDescription)")
                        }
                        self.snapshotSubject.send(newText)
                    }
                    self.telemetry.track(name: TelemetryEventName.transcriptionCompleted.rawValue, properties: [
                        "word_count": String(wordCount),
                        "source": "apple_speech"
                    ])
                }
            )
            .store(in: &cancellables)
    }

    public func setLanguage(_ locale: Locale) {
        _currentLanguage = locale
    }

    public func commitCurrentTranscription() async throws {
        let currentLiveText = liveTextSubject.value
        guard !currentLiveText.isEmpty, currentLiveText != lastCommittedText else { return }
        try editingUseCase.replaceAll(with: currentLiveText)
        lastCommittedText = currentLiveText
    }

    public func clearLiveText() {
        liveTextSubject.send("")
        lastCommittedText = ""
    }
}
