import Combine
import Foundation
import XCTest
@testable import TranscriptionKit

final class LoadingFallbackTranscriptionCoordinatorTests: XCTestCase {
    func testIdlePrimaryStartsPreloadAndUsesFallbackForCurrentSession() async throws {
        let primary = FakeLoadingCoordinator(
            providerType: .whisper,
            initialLoadingState: .idle
        )
        let fallback = FakeLoadingCoordinator(
            providerType: .apple,
            initialLoadingState: .ready
        )
        let sut = LoadingFallbackTranscriptionCoordinator(primary: primary, fallback: fallback)

        try await sut.start(language: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(primary.preloadStartCount, 1)
        XCTAssertEqual(primary.modelLoadingState, .loading)
        XCTAssertEqual(primary.startCallCount, 0)
        XCTAssertEqual(fallback.startCallCount, 1)
        XCTAssertEqual(sut.speechRecognitionService.providerType, .apple)
    }

    func testFailedPrimaryStateFallsBackToFallback() async throws {
        let primary = FakeLoadingCoordinator(
            providerType: .whisper,
            initialLoadingState: .failed("load failed")
        )
        let fallback = FakeLoadingCoordinator(
            providerType: .apple,
            initialLoadingState: .ready
        )
        let sut = LoadingFallbackTranscriptionCoordinator(primary: primary, fallback: fallback)

        try await sut.start(language: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(primary.startCallCount, 0)
        XCTAssertEqual(fallback.startCallCount, 1)
        XCTAssertEqual(sut.speechRecognitionService.providerType, .apple)
    }
}

private final class FakeLoadingCoordinator: TranscriptionCoordinator, ModelLoadingObservable, ModelPreloadControlling, @unchecked Sendable {
    let audioCaptureService: AudioCaptureService
    let speechRecognitionService: SpeechRecognitionService

    let finalResultPublisher: AnyPublisher<TranscriptionResult, Error>
    let liveResultPublisher: AnyPublisher<TranscriptionResult, Error>
    let audioLevelPublisher: AnyPublisher<Float, Never>

    var isTranscribing: Bool { startCallCount > stopCallCount }

    private let loadingStateSubject: CurrentValueSubject<ModelLoadingState, Never>
    private(set) var preloadStartCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(
        providerType: ASRProviderType,
        initialLoadingState: ModelLoadingState
    ) {
        self.audioCaptureService = FakeAudioCaptureService()
        self.speechRecognitionService = FakeSpeechRecognitionService(providerType: providerType)
        self.finalResultPublisher = Empty(completeImmediately: false).eraseToAnyPublisher()
        self.liveResultPublisher = Empty(completeImmediately: false).eraseToAnyPublisher()
        self.audioLevelPublisher = Just(0).eraseToAnyPublisher()
        self.loadingStateSubject = CurrentValueSubject(initialLoadingState)
    }

    var modelLoadingState: ModelLoadingState {
        loadingStateSubject.value
    }

    var modelLoadingStatePublisher: AnyPublisher<ModelLoadingState, Never> {
        loadingStateSubject.eraseToAnyPublisher()
    }

    func startModelPreloadIfNeeded() {
        preloadStartCount += 1
        if case .idle = loadingStateSubject.value {
            loadingStateSubject.send(.loading)
        }
    }

    func start(language: Locale) async throws {
        _ = language
        startCallCount += 1
    }

    func stop() async {
        stopCallCount += 1
    }

    func pause() {}
    func resume() {}
}

private final class FakeAudioCaptureService: AudioCaptureService, @unchecked Sendable {
    var state: AudioCaptureState = .idle
    var statePublisher: AnyPublisher<AudioCaptureState, Never> { Just(.idle).eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { Just(0).eraseToAnyPublisher() }
    func startCapture() async throws {}
    func stopCapture() async {}
    func pauseCapture() {}
    func resumeCapture() {}
    func requestPermission() async -> Bool { true }
    var hasPermission: Bool { true }
}

private final class FakeSpeechRecognitionService: SpeechRecognitionService, @unchecked Sendable {
    let providerType: ASRProviderType

    init(providerType: ASRProviderType) {
        self.providerType = providerType
    }

    var resultPublisher: AnyPublisher<TranscriptionResult, Error> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    func startRecognition(language: Locale) async throws {
        _ = language
    }

    func stopRecognition() async {}
    func checkAvailability() async -> Bool { true }
    func requestPermission() async -> Bool { true }
    var supportedLanguages: [Locale] { [Locale(identifier: "zh-Hans")] }
}
