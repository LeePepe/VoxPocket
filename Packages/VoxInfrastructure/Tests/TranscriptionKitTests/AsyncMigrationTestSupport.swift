import XCTest
import Combine
import Foundation
import Synchronization
import VoxCore
import TranscriptionKitCombine
@testable import TranscriptionKit

let testStorageLocations = VoxStorageLocations(
    temporaryAudio: FileManager.default.temporaryDirectory.appendingPathComponent("example-audio", isDirectory: true),
    modelCache: FileManager.default.temporaryDirectory.appendingPathComponent("example-models", isDirectory: true))

struct TestSpeechFactory: SpeechSessionFactory {
    let factory: @Sendable () async throws -> any TranscriptionCoordinator
    func makeSource() async throws -> any SpeechSessionSource { testSource(try await factory()) }
}

func testSource(_ source: any TranscriptionCoordinator) -> any SpeechSessionSource {
    if let wrapper = source as? CombineTranscriptionCoordinator { return wrapper.core }
    return TestLegacySource(source: source)
}

func makeSelectableCoordinator(permissionCoordinator: any TranscriptionCoordinator,
    factory: @escaping @Sendable () async throws -> any TranscriptionCoordinator) -> CombineTranscriptionCoordinator {
    CombineTranscriptionCoordinator.wrap(DefaultSelectableTranscriptionCoordinator(
        permissionCoordinator: testSource(permissionCoordinator), factory: TestSpeechFactory(factory: factory)))
}

// Sendable: Combine subscriptions are retained under Mutex and subjects serialize callbacks.
private final class TestLegacySource: SpeechSessionSource, ModelLoadingStateProviding, ModelPreloadControlling, @unchecked Sendable {
    let source: any TranscriptionCoordinator
    init(source: any TranscriptionCoordinator) { self.source = source }
    var providerKind: ASRProviderType { source.speechRecognitionService.providerType }
    var supportedLanguages: [Locale] { source.speechRecognitionService.supportedLanguages }
    var hasMicrophonePermission: Bool { source.audioCaptureService.hasPermission }
    var hasSpeechPermission: Bool { true }
    var isActive: Bool { source.isTranscribing }
    func requestMicrophonePermission() async -> Bool { await source.audioCaptureService.requestPermission() }
    func requestSpeechPermission() async -> Bool { await source.speechRecognitionService.requestPermission() }
    func captureStates() -> AsyncStream<AudioCaptureState> { testStream(source.audioCaptureService.statePublisher) }
    func audioLevels() -> AsyncStream<Float> { testStream(source.audioLevelPublisher) }
    var modelLoadingState: ModelLoadingState { (source as? any ModelLoadingObservable)?.modelLoadingState ?? .ready }
    func modelLoadingStates() -> AsyncStream<ModelLoadingState> {
        if let source = source as? any ModelLoadingObservable { return testStream(source.modelLoadingStatePublisher) }
        return AsyncStream { $0.yield(.ready); $0.finish() }
    }
    func startModelPreloadIfNeeded() { (source as? any ModelPreloadControlling)?.startModelPreloadIfNeeded() }
    func startSession(language: Locale) async throws -> any SpeechSession {
        let session = TestLegacySession(source: source)
        try await source.start(language: language)
        return session
    }
}

// Sendable: retained Combine tokens are never exposed and cancelled at session teardown.
private final class TestLegacySession: SpeechSession, @unchecked Sendable {
    let source: any TranscriptionCoordinator
    let stream: AsyncThrowingStream<TranscriptionEvent, Error>
    let tokens: [AnyCancellable]
    init(source: any TranscriptionCoordinator) {
        self.source = source
        let pair = AsyncThrowingStream<TranscriptionEvent, Error>.makeStream()
        stream = pair.stream
        let completion: @Sendable (Subscribers.Completion<Error>) -> Void = {
            if case .failure(let error) = $0 { pair.continuation.finish(throwing: error) }
        }
        tokens = [
            source.liveResultPublisher.sink(receiveCompletion: completion) { pair.continuation.yield(.partial($0)) },
            source.finalResultPublisher.sink(receiveCompletion: completion) { pair.continuation.yield(.final($0)) }
        ]
    }
    deinit { tokens.forEach { $0.cancel() } }
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error> { stream }
    func stop() async { await source.stop() }
    func cancel() async { await source.stop() }
    func pause() async { source.pause() }
    func resume() async { source.resume() }
}

// Sendable: the token's only operation is thread-safe cancellation.
private final class TestSubscription: @unchecked Sendable {
    let value: AnyCancellable
    init(_ value: AnyCancellable) { self.value = value }
}
private func testStream<Value: Sendable>(_ publisher: AnyPublisher<Value, Never>) -> AsyncStream<Value> {
    AsyncStream { continuation in
        let token = TestSubscription(publisher.sink { continuation.yield($0) })
        continuation.onTermination = { _ in token.value.cancel() }
    }
}

func assertEventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertTrue(predicate(), "Expected async event delivery", file: file, line: line)
}
