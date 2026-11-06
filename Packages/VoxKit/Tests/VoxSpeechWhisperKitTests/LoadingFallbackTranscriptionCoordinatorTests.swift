import VoxCore
import Foundation
import Synchronization
import XCTest
@testable import VoxSpeechWhisperKit

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
        let sut = AsyncTestCoordinator.wrap(LoadingFallbackTranscriptionCoordinator(primary: primary, fallback: fallback))

        try await sut.start(language: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(primary.preloadStartCount, 1)
        XCTAssertEqual(primary.modelLoadingState, .loading)
        XCTAssertEqual(primary.startCallCount, 0)
        XCTAssertEqual(fallback.startCallCount, 1)
        XCTAssertEqual(sut.core.providerKind, .apple)
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
        let sut = AsyncTestCoordinator.wrap(LoadingFallbackTranscriptionCoordinator(primary: primary, fallback: fallback))

        try await sut.start(language: Locale(identifier: "zh-Hans"))

        XCTAssertEqual(primary.startCallCount, 0)
        XCTAssertEqual(fallback.startCallCount, 1)
        XCTAssertEqual(sut.core.providerKind, .apple)
    }
}

private final class FakeLoadingCoordinator: SpeechSessionSource, SpeechSession, ModelLoadingStateProviding, ModelPreloadControlling {
    private struct State {
        var preload = 0
        var starts = 0
        var stops = 0
    }
    private let state = Mutex(State())
    private let loading: AsyncValueRelay<ModelLoadingState>
    let providerKind: ASRProviderType
    init(providerType: ASRProviderType, initialLoadingState: ModelLoadingState) {
        providerKind = providerType
        loading = AsyncValueRelay(initialLoadingState)
    }
    var preloadStartCount: Int { state.withLock { $0.preload } }
    var startCallCount: Int { state.withLock { $0.starts } }
    var stopCallCount: Int { state.withLock { $0.stops } }
    var modelLoadingState: ModelLoadingState { loading.value }
    func modelLoadingStates() -> AsyncStream<ModelLoadingState> { loading.stream() }
    func startModelPreloadIfNeeded() {
        state.withLock { $0.preload += 1 }
        if case .idle = loading.value { loading.send(.loading) }
    }
    var isActive: Bool { startCallCount > stopCallCount }
    var supportedLanguages: [Locale] { [Locale(identifier: "zh-Hans")] }
    var hasMicrophonePermission: Bool { true }
    var hasSpeechPermission: Bool { true }
    func requestMicrophonePermission() async -> Bool { true }
    func requestSpeechPermission() async -> Bool { true }
    func captureStates() -> AsyncStream<AudioCaptureState> { AsyncStream { $0.yield(.idle) } }
    func audioLevels() -> AsyncStream<Float> { AsyncStream { $0.yield(0) } }
    func startSession(language: Locale) async throws -> any SpeechSession {
        state.withLock { $0.starts += 1 }
        return self
    }
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error> { AsyncThrowingStream { _ in } }
    func stop() async { state.withLock { $0.stops += 1 } }
    func cancel() async { await stop() }
    func pause() async {}
    func resume() async {}
}
