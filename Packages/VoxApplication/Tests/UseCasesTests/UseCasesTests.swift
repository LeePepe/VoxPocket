import XCTest
import Combine
@testable import UseCases
import TranscriptionKit
import CoreModels
import LokiKit
import Synchronization

final class UseCasesTests: XCTestCase {
    func testRecordingAndTranscriptionCompleteWhileFakeAsyncFlushIsDeferred() async throws {
        let telemetry = FakeConsumerTelemetry()
        let coordinator = LiveResultTranscriptionCoordinator()
        let editing = FakeConsumerEditing(text: "")
        let recording = DefaultRecordingUseCase(coordinator: coordinator, telemetry: telemetry)
        let transcription = DefaultTranscriptionUseCase(
            coordinator: coordinator, editing: editing,
            logger: FakeTranscriptionLogger(), telemetry: telemetry
        )
        var snapshots: [String] = []
        let subscription = transcription.snapshotPublisher.sink { snapshots.append($0) }
        let flush = Task { await telemetry.flush() }
        defer { subscription.cancel() }
        await telemetry.flushStarted.wait()

        do {
            try await recording.startRecording()
            try await recording.stopRecording()
        } catch {
            telemetry.releaseFlush.signal()
            await flush.value
            throw error
        }
        coordinator.sendFinalText(FakeConsumerContent.input)

        XCTAssertEqual(editing.currentText, FakeConsumerContent.input)
        XCTAssertEqual(snapshots, [FakeConsumerContent.input])
        XCTAssertFalse(telemetry.flushCompleted)
        XCTAssertEqual(telemetry.events.map(\.name), ["recording.stopped", "transcription.completed"])
        assertConsumerMetric(
            telemetry.events.filter { $0.name == "recording.stopped" },
            name: "recording.stopped", key: "duration_s"
        )
        XCTAssertEqual(telemetry.events.last?.properties, ["word_count": "1", "source": "apple_speech"])
        assertConsumerPrivacy(telemetry.events)
        telemetry.releaseFlush.signal()
        await flush.value
        XCTAssertTrue(telemetry.flushCompleted)
    }

    func testRecordingStopEmitsOnlyDurationWithTelemetryEnabledOrDisabled() async throws {
        for enabled in [true, false] {
            let telemetry = FakeConsumerTelemetry(isEnabled: enabled)
            let coordinator = NamedTranscriptionCoordinator(name: "synthetic")
            let useCase = DefaultRecordingUseCase(coordinator: coordinator, telemetry: telemetry)
            try await useCase.startRecording()
            XCTAssertTrue(telemetry.events.isEmpty)
            try await useCase.stopRecording()
            let events = await coordinator.events()
            XCTAssertEqual(events, ["start:zh-Hans", "stop"])
            XCTAssertEqual(useCase.state, .idle)
            if enabled {
                assertConsumerMetric(telemetry.events, name: "recording.stopped", key: "duration_s")
            } else {
                XCTAssertTrue(telemetry.events.isEmpty)
            }
            assertConsumerPrivacy(telemetry.events)
        }
    }

    func testRecordingCancellationStopsCoordinatorAndResetsStateWithoutStopTelemetry() async throws {
        let telemetry = FakeConsumerTelemetry()
        let coordinator = NamedTranscriptionCoordinator(name: "synthetic")
        let useCase = DefaultRecordingUseCase(coordinator: coordinator, telemetry: telemetry)
        try await useCase.startRecording()
        let reset = expectation(description: "Cancellation publishes idle after stopping")
        let subscription = useCase.statePublisher.dropFirst().sink {
            if $0 == .idle { reset.fulfill() }
        }
        defer { subscription.cancel() }
        useCase.cancelRecording()
        await fulfillment(of: [reset], timeout: 2)
        let events = await coordinator.events()
        XCTAssertEqual(events, ["start:zh-Hans", "stop"])
        XCTAssertEqual(useCase.state, .idle)
        XCTAssertTrue(telemetry.events.isEmpty)
        assertConsumerPrivacy(telemetry.events)
    }

    func testRecordingStartFailurePreservesErrorAndDoesNotEmitTelemetry() async {
        let telemetry = FakeConsumerTelemetry()
        let coordinator = ModelLoadingTranscriptionCoordinator(state: .failed(FakeConsumerError.sensitive.detail))
        let useCase = DefaultRecordingUseCase(coordinator: coordinator, telemetry: telemetry)
        do {
            try await useCase.startRecording()
            XCTFail("Expected the synthetic model-loading state to reject start")
        } catch {
            XCTAssertTrue(error is VoxError)
            XCTAssertTrue(error.localizedDescription.contains(FakeConsumerContent.errorBody))
        }
        let events = await coordinator.events()
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(useCase.state, .idle)
        XCTAssertTrue(telemetry.events.isEmpty)
        assertConsumerPrivacy(telemetry.events)
    }

    func testFinalTranscriptionPreservesEditingAndSnapshotRoutingWithMetricsOnly() {
        for enabled in [true, false] {
            for snapshotGate in [true, false] {
                let coordinator = LiveResultTranscriptionCoordinator()
                let telemetry = FakeConsumerTelemetry(isEnabled: enabled)
                let editing = FakeConsumerEditing(text: "")
                let logger = FakeTranscriptionLogger()
                let useCase = DefaultTranscriptionUseCase(
                    coordinator: coordinator, editing: editing, logger: logger, telemetry: telemetry
                )
                useCase.snapshotGateActive = snapshotGate
                var snapshots: [String] = []
                let subscription = useCase.snapshotPublisher.sink { snapshots.append($0) }
                defer { subscription.cancel() }
                coordinator.sendLiveText(FakeConsumerContent.input)
                coordinator.sendFinalText("")
                XCTAssertTrue(telemetry.events.isEmpty)
                XCTAssertTrue(snapshots.isEmpty)
                XCTAssertEqual(editing.currentText, "")
                let finalText = FakeConsumerContent.input + " " + FakeConsumerContent.output
                coordinator.sendFinalText(finalText)
                XCTAssertEqual(snapshots, [finalText])
                XCTAssertEqual(editing.currentText, snapshotGate ? "" : finalText)
                XCTAssertEqual(telemetry.events.count, enabled ? 1 : 0)
                if enabled {
                    XCTAssertEqual(telemetry.events.first?.name, "transcription.completed")
                    XCTAssertEqual(telemetry.events.first?.properties, ["word_count": "2", "source": "apple_speech"])
                }
                assertConsumerPrivacy(telemetry.events)
                XCTAssertFalse(logger.messages.contains { $0.contains(FakeConsumerContent.input) })
            }
        }
    }

    func testLiveTranscriptionIsNotLoggedOrPublishedAsFinal() {
        let coordinator = LiveResultTranscriptionCoordinator()
        let logger = FakeTranscriptionLogger()
        let useCase = DefaultTranscriptionUseCase(coordinator: coordinator, editing: FakeEditingUseCase(), logger: logger)
        var snapshots: [String] = []
        var live: [String] = []
        let snapshotSubscription = useCase.snapshotPublisher.sink { snapshots.append($0) }
        let liveSubscription = useCase.liveTextPublisher.sink { live.append($0) }
        defer { snapshotSubscription.cancel(); liveSubscription.cancel() }
        let text = "SYNTHETIC_PRIVATE_SENTINEL"
        coordinator.sendLiveText(text)
        coordinator.sendLiveText(text + " continued")
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertEqual(live.last, text + " continued")
        coordinator.sendFinalText(text)
        XCTAssertEqual(snapshots, [text])
        XCTAssertFalse(logger.messages.contains { $0.contains(text) })
        XCTAssertTrue(logger.messages.contains { $0.contains("chars=") })
    }

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

    func sendFinalText(_ text: String) {
        finalSubject.send(TranscriptionResult(text: text, type: .final, confidence: nil,
                                              timestamp: Date(), locale: Locale(identifier: "zh-Hans")))
    }
}

private final class FakeTranscriptionLogger: LokiKit.Logger {
    private let stored = Mutex<[String]>([])
    private let level = Mutex<LogLevel>(.debug)
    var minimumLevel: LogLevel {
        get { level.withLock { $0 } }
        set { level.withLock { $0 = newValue } }
    }
    var messages: [String] { stored.withLock { $0 } }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, file: String, function: String, line: Int) {
        let value = message()
        stored.withLock { $0.append(value) }
    }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, context: [String: Any], file: String, function: String, line: Int) {
        let value = message() + String(describing: context)
        stored.withLock { $0.append(value) }
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

    // MARK: - Voice Zone
    private(set) var voiceAnchorLocation: Int?
    private(set) var isVoiceZoneLocked: Bool = false
    func setVoiceAnchor(_ location: Int) { voiceAnchorLocation = location }
    func clearVoiceAnchor() { voiceAnchorLocation = nil }
    func setVoiceZoneLocked(_ locked: Bool) { isVoiceZoneLocked = locked }
    func replaceVoiceZone(with text: String) throws { currentTextSubject.send(text) }
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
