import Foundation
import Combine
import TranscriptionKit
import Observability

/// 转录用例默认实现
///
/// 桥接 `TranscriptionCoordinator` 到 `TranscriptionUseCase` 协议。
/// 自动将最终识别结果追加到 `EditingUseCase`。
public final class DefaultTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {

    private let coordinator: TranscriptionCoordinator
    private let editingUseCase: EditingUseCase
    private let logger: Logger

    private let liveTextSubject = CurrentValueSubject<String, Never>("")
    private var cancellables = Set<AnyCancellable>()
    private var _currentLanguage: Locale
    private var lastCommittedText: String = ""

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
        logger: Logger? = nil
    ) {
        self.coordinator = coordinator
        self.editingUseCase = editing
        self._currentLanguage = language
        self.logger = logger ?? PrintLogger(subsystem: "TranscriptionUseCase")

        bindCoordinator()
    }

    private func bindCoordinator() {
        // 实时转录 → liveTextSubject
        coordinator.liveResultPublisher
            .map(\.text)
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

        // 最终结果 → 自动追加到 editingUseCase
        coordinator.finalResultPublisher
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] result in
                    guard let self else { return }
                    let newText = result.text
                    guard !newText.isEmpty else { return }
                    // 用最终文本替换当前内容（SFSpeechRecognizer 返回累积文本）
                    try? self.editingUseCase.replaceAll(with: newText)
                    self.lastCommittedText = newText
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
