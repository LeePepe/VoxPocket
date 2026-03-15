import Combine
import Foundation

/// 当本地模型尚未就绪时，自动回退到备用转录器。
///
/// 当前用于：WhisperKit 未 ready 时回退到 Apple Speech。
public final class LoadingFallbackTranscriptionCoordinator: TranscriptionCoordinator, @unchecked Sendable {
    private let primary: any TranscriptionCoordinator
    private let fallback: any TranscriptionCoordinator

    private let liveResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)
    fileprivate let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)

    private var cancellables = Set<AnyCancellable>()
    private let activeSelectionLock = NSLock()
    private var activeSelection: ActiveSelection = .primary

    private lazy var _audioCaptureService: FallbackAudioCaptureService = .init(coordinator: self)
    private lazy var _speechRecognitionService: FallbackSpeechRecognitionService = .init(coordinator: self)

    public init(
        primary: any TranscriptionCoordinator,
        fallback: any TranscriptionCoordinator
    ) {
        self.primary = primary
        self.fallback = fallback

        bind(primary, selection: .primary)
        bind(fallback, selection: .fallback)
    }

    public var audioCaptureService: AudioCaptureService { _audioCaptureService }
    public var speechRecognitionService: SpeechRecognitionService { _speechRecognitionService }

    public var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        finalResultSubject.eraseToAnyPublisher()
    }

    public var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        liveResultSubject.eraseToAnyPublisher()
    }

    public var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    public var isTranscribing: Bool {
        currentCoordinator().isTranscribing
    }

    public func start(language: Locale) async throws {
        startPrimaryPreloadIfNeeded()
        let selection = preferredSelection()
        setActiveSelection(selection)
        try await coordinator(for: selection).start(language: language)
    }

    public func stop() async {
        await currentCoordinator().stop()
    }

    public func pause() {
        currentCoordinator().pause()
    }

    public func resume() {
        currentCoordinator().resume()
    }

    private func bind(
        _ coordinator: any TranscriptionCoordinator,
        selection: ActiveSelection
    ) {
        coordinator.liveResultPublisher
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.currentSelection() == selection else { return }
                    self.liveResultSubject.send(completion: completion)
                },
                receiveValue: { [weak self] result in
                    guard let self, self.currentSelection() == selection else { return }
                    self.liveResultSubject.send(result)
                }
            )
            .store(in: &cancellables)

        coordinator.finalResultPublisher
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.currentSelection() == selection else { return }
                    self.finalResultSubject.send(completion: completion)
                },
                receiveValue: { [weak self] result in
                    guard let self, self.currentSelection() == selection else { return }
                    self.finalResultSubject.send(result)
                }
            )
            .store(in: &cancellables)

        coordinator.audioLevelPublisher
            .sink { [weak self] level in
                guard let self, self.currentSelection() == selection else { return }
                self.audioLevelSubject.send(level)
            }
            .store(in: &cancellables)

        coordinator.audioCaptureService.statePublisher
            .sink { [weak self] state in
                guard let self, self.currentSelection() == selection else { return }
                self.captureStateSubject.send(state)
                if case .idle = state {
                    self.audioLevelSubject.send(0)
                }
            }
            .store(in: &cancellables)
    }

    private func preferredSelection() -> ActiveSelection {
        guard let loadable = primary as? any ModelLoadingObservable else {
            return .primary
        }

        switch loadable.modelLoadingState {
        case .ready:
            return .primary
        case .failed, .idle, .loading, .downloading:
            return .fallback
        }
    }

    private func startPrimaryPreloadIfNeeded() {
        guard let loadable = primary as? any ModelLoadingObservable,
              case .idle = loadable.modelLoadingState,
              let preloadable = primary as? any ModelPreloadControlling else {
            return
        }

        preloadable.startModelPreloadIfNeeded()
    }

    fileprivate func currentCoordinator() -> any TranscriptionCoordinator {
        coordinator(for: currentSelection())
    }

    fileprivate func currentSpeechProviderType() -> ASRProviderType {
        currentCoordinator().speechRecognitionService.providerType
    }

    fileprivate func currentSupportedLanguages() -> [Locale] {
        currentCoordinator().speechRecognitionService.supportedLanguages
    }

    private func coordinator(for selection: ActiveSelection) -> any TranscriptionCoordinator {
        switch selection {
        case .primary:
            return primary
        case .fallback:
            return fallback
        }
    }

    private func currentSelection() -> ActiveSelection {
        activeSelectionLock.lock()
        defer { activeSelectionLock.unlock() }
        return activeSelection
    }

    private func setActiveSelection(_ selection: ActiveSelection) {
        activeSelectionLock.lock()
        activeSelection = selection
        activeSelectionLock.unlock()
    }
}

private enum ActiveSelection {
    case primary
    case fallback
}

private final class FallbackAudioCaptureService: AudioCaptureService, @unchecked Sendable {
    private weak var coordinator: LoadingFallbackTranscriptionCoordinator?

    init(coordinator: LoadingFallbackTranscriptionCoordinator) {
        self.coordinator = coordinator
    }

    var state: AudioCaptureState { coordinator?.captureStateSubject.value ?? .idle }

    var statePublisher: AnyPublisher<AudioCaptureState, Never> {
        coordinator?.captureStateSubject.eraseToAnyPublisher() ?? Just(.idle).eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        coordinator?.audioLevelPublisher ?? Just(0).eraseToAnyPublisher()
    }

    func startCapture() async throws {}
    func stopCapture() async {}
    func pauseCapture() { coordinator?.pause() }
    func resumeCapture() { coordinator?.resume() }

    func requestPermission() async -> Bool {
        await coordinator?.currentCoordinator().audioCaptureService.requestPermission() ?? false
    }

    var hasPermission: Bool {
        coordinator?.currentCoordinator().audioCaptureService.hasPermission ?? false
    }
}

private final class FallbackSpeechRecognitionService: SpeechRecognitionService, @unchecked Sendable {
    private weak var coordinator: LoadingFallbackTranscriptionCoordinator?

    init(coordinator: LoadingFallbackTranscriptionCoordinator) {
        self.coordinator = coordinator
    }

    var providerType: ASRProviderType {
        coordinator?.currentSpeechProviderType() ?? .apple
    }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        coordinator?.liveResultPublisher
            ?? Fail(error: NSError(domain: "LoadingFallbackTranscriptionCoordinator", code: -1)).eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {}
    func stopRecognition() async {}
    func checkAvailability() async -> Bool { true }

    func requestPermission() async -> Bool {
        await coordinator?.currentCoordinator().speechRecognitionService.requestPermission() ?? false
    }

    var supportedLanguages: [Locale] {
        coordinator?.currentSupportedLanguages() ?? [Locale(identifier: "zh-Hans")]
    }
}
