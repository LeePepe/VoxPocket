import XCTest
import Combine
@testable import UseCases
import TranscriptionKit
import CoreModels

final class UseCasesTests: XCTestCase {
    func testRecordingOperationsAreSerialized() async throws {
        let coordinator = FakeTranscriptionCoordinator()
        let useCase = DefaultRecordingUseCase(coordinator: coordinator)

        async let startTask: Void = useCase.startRecording()
        await coordinator.waitUntilStartBegins()

        async let stopTask: Void = useCase.stopRecording()
        try await Task.sleep(nanoseconds: 100_000_000)
        let stopObservedBeforeStartFinished = await coordinator.hasStopBeenObserved()
        XCTAssertFalse(stopObservedBeforeStartFinished)

        await coordinator.finishStart()

        _ = try await startTask
        _ = try await stopTask

        let stopObservedAfterStartFinished = await coordinator.hasStopBeenObserved()
        XCTAssertTrue(stopObservedAfterStartFinished)
        let overlap = await coordinator.didStopRunDuringStart()
        XCTAssertFalse(overlap)
    }

    func testLiveTextPublisherDeduplicatesConsecutiveIdenticalTexts() async {
        let coordinator = LiveResultTranscriptionCoordinator()
        let useCase = DefaultTranscriptionUseCase(
            coordinator: coordinator,
            editing: FakeEditingUseCase()
        )

        var values: [String] = []
        let cancellable = useCase.liveTextPublisher.sink { values.append($0) }
        defer { cancellable.cancel() }

        coordinator.sendLiveText("你好")
        coordinator.sendLiveText("你好")
        coordinator.sendLiveText("你好世界")
        coordinator.sendLiveText("你好世界")
        coordinator.sendLiveText("你好世界！")
        await Task.yield()

        XCTAssertEqual(values, ["", "你好", "你好世界", "你好世界！"])
    }

    func testStartRecordingFallsBackWhenPrimaryModelIsStillLoading() async throws {
        let primary = ModelLoadingTranscriptionCoordinator(state: .loading)
        let fallback = NamedTranscriptionCoordinator(name: "fallback")
        let useCase = DefaultRecordingUseCase(coordinator: primary, fallbackCoordinator: fallback)

        try await useCase.startRecording()
        try await useCase.stopRecording()

        let primaryEvents = await primary.events()
        let fallbackEvents = await fallback.events()
        XCTAssertEqual(primaryEvents, [])
        XCTAssertEqual(fallbackEvents, ["start:zh-Hans", "stop"])
    }

    func testStartRecordingDoesNotBlockWhenCoordinatorAllowsStartDuringModelLoading() async throws {
        let coordinator = DeferredModelLoadingTranscriptionCoordinator(state: .loading)
        let useCase = DefaultRecordingUseCase(coordinator: coordinator)

        try await useCase.startRecording()
        try await useCase.stopRecording()

        let events = await coordinator.events()
        XCTAssertEqual(events, ["start:zh-Hans", "stop"])
    }

    func testStartRecordingThrowsWhenCoordinatorBlocksStartDuringModelLoadingWithoutFallback() async throws {
        let coordinator = ModelLoadingTranscriptionCoordinator(state: .loading)
        let useCase = DefaultRecordingUseCase(coordinator: coordinator)

        do {
            try await useCase.startRecording()
            XCTFail("Expected startRecording() to throw when loading blocks recording")
        } catch let error as VoxError {
            XCTAssertEqual(error.localizedDescription, "转录失败：本地模型正在初始化，请稍候再试")
        }
    }
}

private final class FakeTranscriptionCoordinator: TranscriptionCoordinator, @unchecked Sendable {
    let audioCaptureService: AudioCaptureService = FakeAudioCaptureService()
    let speechRecognitionService: SpeechRecognitionService = FakeSpeechRecognitionService()

    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        Empty().eraseToAnyPublisher()
    }

    var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        Empty().eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        Empty().eraseToAnyPublisher()
    }

    var isTranscribing: Bool { false }

    private actor State {
        var isStartInProgress = false
        var startHasBegun = false
        var stopHasBeenObserved = false
        var stopRanDuringStart = false
        var startContinuation: CheckedContinuation<Void, Never>?
        var startBeganWaiters: [CheckedContinuation<Void, Never>] = []

        func markStartBegun() {
            startHasBegun = true
            isStartInProgress = true
            let waiters = startBeganWaiters
            startBeganWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        func waitForStartBegun() async {
            if startHasBegun { return }
            await withCheckedContinuation { continuation in
                startBeganWaiters.append(continuation)
            }
        }

        func suspendStart() async {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }

        func finishStart() {
            isStartInProgress = false
            startContinuation?.resume()
            startContinuation = nil
        }

        func markStopObserved() {
            stopHasBeenObserved = true
            if isStartInProgress {
                stopRanDuringStart = true
            }
        }

        func hasStopObserved() -> Bool {
            stopHasBeenObserved
        }
    }

    private let state = State()

    func start(language: Locale) async throws {
        await state.markStartBegun()
        await state.suspendStart()
    }

    func stop() async {
        await state.markStopObserved()
    }

    func pause() {}

    func resume() {}

    func waitUntilStartBegins() async {
        await state.waitForStartBegun()
    }

    func hasStopBeenObserved() async -> Bool {
        await state.hasStopObserved()
    }

    func finishStart() async {
        await state.finishStart()
    }

    func didStopRunDuringStart() async -> Bool {
        await state.stopRanDuringStart
    }
}

private final class FakeAudioCaptureService: AudioCaptureService, @unchecked Sendable {
    var state: AudioCaptureState = .idle

    var statePublisher: AnyPublisher<AudioCaptureState, Never> {
        Just(.idle).eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        Empty().eraseToAnyPublisher()
    }

    func startCapture() async throws {}

    func stopCapture() async {}

    func pauseCapture() {}

    func resumeCapture() {}

    func requestPermission() async -> Bool { true }

    var hasPermission: Bool { true }
}

private final class FakeSpeechRecognitionService: SpeechRecognitionService, @unchecked Sendable {
    var providerType: ASRProviderType { .apple }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        Empty().eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {}

    func stopRecognition() async {}

    func checkAvailability() async -> Bool { true }

    func requestPermission() async -> Bool { true }

    var supportedLanguages: [Locale] { [Locale(identifier: "zh-Hans")] }
}

private final class LiveResultTranscriptionCoordinator: TranscriptionCoordinator, @unchecked Sendable {
    let audioCaptureService: AudioCaptureService = FakeAudioCaptureService()
    let speechRecognitionService: SpeechRecognitionService = FakeSpeechRecognitionService()

    private let finalSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let liveSubject = PassthroughSubject<TranscriptionResult, Error>()

    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        finalSubject.eraseToAnyPublisher()
    }

    var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        liveSubject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        Empty().eraseToAnyPublisher()
    }

    var isTranscribing: Bool { false }

    func start(language: Locale) async throws {}
    func stop() async {}
    func pause() {}
    func resume() {}

    func sendLiveText(_ text: String) {
        liveSubject.send(
            TranscriptionResult(
                text: text,
                type: .partial,
                confidence: nil,
                timestamp: Date(),
                locale: Locale(identifier: "zh-Hans")
            )
        )
    }
}

private final class FakeEditingUseCase: EditingUseCase, @unchecked Sendable {
    private let currentTextSubject = CurrentValueSubject<String, Never>("")

    var currentText: String { currentTextSubject.value }

    var currentTextPublisher: AnyPublisher<String, Never> {
        currentTextSubject.eraseToAnyPublisher()
    }

    func applyEdit(range: CoreModels.TextRange, newText: String) throws {}
    func replaceAll(with text: String) throws { currentTextSubject.send(text) }
    func insert(_ text: String, at location: Int) throws {}
    func delete(range: CoreModels.TextRange) throws {}
    func append(_ text: String) throws {}
    func mergeRecentEdits() {}
}

private class NamedTranscriptionCoordinator: TranscriptionCoordinator, @unchecked Sendable {
    let audioCaptureService: AudioCaptureService = FakeAudioCaptureService()
    let speechRecognitionService: SpeechRecognitionService = FakeSpeechRecognitionService()

    private actor State {
        var events: [String] = []
        func append(_ event: String) { events.append(event) }
        func snapshot() -> [String] { events }
    }

    private let state = State()
    private let name: String

    init(name: String) {
        self.name = name
    }

    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        Empty().eraseToAnyPublisher()
    }

    var liveResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        Empty().eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        Empty().eraseToAnyPublisher()
    }

    var isTranscribing: Bool { false }

    func start(language: Locale) async throws {
        await state.append("start:\(language.identifier)")
    }

    func stop() async {
        await state.append("stop")
    }

    func pause() {
        Task { await state.append("pause") }
    }

    func resume() {
        Task { await state.append("resume") }
    }

    func events() async -> [String] {
        await state.snapshot()
    }
}

private final class ModelLoadingTranscriptionCoordinator: NamedTranscriptionCoordinator, ModelLoadingObservable, @unchecked Sendable {
    private let loadingSubject: CurrentValueSubject<ModelLoadingState, Never>

    init(state: ModelLoadingState) {
        self.loadingSubject = CurrentValueSubject(state)
        super.init(name: "primary")
    }

    var modelLoadingState: ModelLoadingState {
        loadingSubject.value
    }

    var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> {
        loadingSubject.eraseToAnyPublisher()
    }
}

private final class DeferredModelLoadingTranscriptionCoordinator:
    NamedTranscriptionCoordinator,
    ModelLoadingObservable,
    ModelLoadingStartControlling,
    @unchecked Sendable {
    private let loadingSubject: CurrentValueSubject<ModelLoadingState, Never>

    init(state: ModelLoadingState) {
        self.loadingSubject = CurrentValueSubject(state)
        super.init(name: "deferred")
    }

    var modelLoadingState: ModelLoadingState {
        loadingSubject.value
    }

    var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> {
        loadingSubject.eraseToAnyPublisher()
    }

    var blocksRecordingUntilModelReady: Bool {
        false
    }
}
