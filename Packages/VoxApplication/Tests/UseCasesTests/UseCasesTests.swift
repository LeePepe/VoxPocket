import XCTest
import Combine
@testable import UseCases
import TranscriptionKit

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
