import Foundation
import Synchronization
import VoxCore
import XCTest
@testable import VoxSpeech

let testStorageLocations = VoxStorageLocations(
    temporaryAudio: FileManager.default.temporaryDirectory.appendingPathComponent("example-audio", isDirectory: true),
    modelCache: FileManager.default.temporaryDirectory.appendingPathComponent("example-models", isDirectory: true))

final class AsyncTestCoordinator: Sendable {
    private struct State {
        var session: (any SpeechSession)?
        var startup: Task<any SpeechSession, Error>?
        var pump: Task<Void, Never>?
        var observers: [Task<Void, Never>] = []
        var starting = false
        var pendingStates: [AudioCaptureState] = []
        var capture: AudioCaptureState = .idle
        var continuations: [UUID: AsyncStream<TranscriptionEvent>.Continuation] = [:]
    }
    let core: any SpeechSessionSource
    private let state = Mutex(State())
    var isTranscribing: Bool { core.isActive }
    var captureState: AudioCaptureState { state.withLock { $0.capture } }
    var modelLoadingState: ModelLoadingState { (core as? any ModelLoadingStateProviding)?.modelLoadingState ?? .ready }
    init(core: any SpeechSessionSource) {
        self.core = core
        let states = core.captureStates()
        let levels = core.audioLevels()
        let captureTask = Task { [weak self] in
            var initial = true
            for await value in states {
                if initial { initial = false; if value == .idle { continue } }
                guard let self else { return }
                let forward = state.withLock { state in
                    if state.starting { state.pendingStates.append(value); return false }
                    return state.session == nil
                }
                if forward { receive(.state(value)) }
            }
        }
        let levelTask = Task { [weak self] in
            var initial = true
            for await value in levels {
                if initial { initial = false; if value == 0 { continue } }
                guard let self else { return }
                if state.withLock({ !$0.starting && $0.session == nil }) { receive(.level(value)) }
            }
        }
        var observers = [captureTask, levelTask]
        if let loading = core as? any ModelLoadingStateProviding {
            let states = loading.modelLoadingStates()
            observers.append(Task { for await _ in states { if Task.isCancelled { return } } })
        }
        state.withLock { $0.observers = observers }
    }
    deinit {
        let snapshot = state.withLock { ($0.startup, $0.pump, $0.observers, Array($0.continuations.values)) }
        snapshot.0?.cancel(); snapshot.1?.cancel()
        snapshot.2.forEach { $0.cancel() }
        snapshot.3.forEach { $0.finish() }
    }
    static func wrap(_ core: any SpeechSessionSource) -> AsyncTestCoordinator { AsyncTestCoordinator(core: core) }
    func events() -> AsyncStream<TranscriptionEvent> {
        let id = UUID()
        let pair = AsyncStream<TranscriptionEvent>.makeStream()
        pair.continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.continuations.removeValue(forKey: id) }
        }
        state.withLock { $0.continuations[id] = pair.continuation }
        return pair.stream
    }
    func observeFinals(_ handler: @escaping @Sendable (TranscriptionResult) -> Void) -> Task<Void, Never> {
        let stream = events()
        return Task { for await event in stream { if case .final(let result) = event { handler(result) } } }
    }
    func observePartials(_ handler: @escaping @Sendable (TranscriptionResult) -> Void) -> Task<Void, Never> {
        let stream = events()
        return Task { for await event in stream { if case .partial(let result) = event { handler(result) } } }
    }
    private func receive(_ event: TranscriptionEvent) {
        let continuations = state.withLock { state in
            if case .state(let capture) = event { state.capture = capture }
            return Array(state.continuations.values)
        }
        continuations.forEach { $0.yield(event) }
    }
    func start(language: Locale) async throws {
        state.withLock { $0.pump?.cancel(); $0.starting = true; $0.pendingStates = [] }
        let startup = Task { [core] in try await core.startSession(language: language) }
        state.withLock { $0.startup = startup }
        do {
            let session = try await withTaskCancellationHandler { try await startup.value } onCancel: { startup.cancel() }
            let events = session.events()
            let pump = Task { [weak self] in
                do {
                    for try await event in events {
                        guard !Task.isCancelled else { return }
                        self?.receive(event)
                    }
                } catch { self?.receive(.state(.error("语音识别失败，请重试。"))) }
            }
            state.withLock { $0.session = session; $0.pump = pump; $0.startup = nil; $0.starting = false; $0.pendingStates = [] }
        } catch {
            let pending = state.withLock { state in
                state.startup = nil; state.session = nil; state.starting = false
                defer { state.pendingStates = [] }
                return state.pendingStates
            }
            pending.forEach { receive(.state($0)) }
            throw error
        }
    }
    func stop() async {
        let pending = state.withLock { ($0.startup, $0.session) }
        if let startup = pending.0 {
            startup.cancel()
            if case .success(let session) = await startup.result { await session.stop() }
        } else { await pending.1?.stop() }
    }
    func pause() async { await state.withLock { $0.session }?.pause() }
    func resume() async { await state.withLock { $0.session }?.resume() }
    func prepareQuickRecording() throws { try quickSource().prepareQuickRecording() }
    func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot { try quickSource().freezeQuickRecordingRelease() }
    func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        try await quickSource().completeQuickRecordingRelease(snapshot)
    }
    private func quickSource() throws -> any QuickRecordingReleaseControlling {
        guard let source = core as? any QuickRecordingReleaseControlling else { throw QuickRecordingReleaseError.unsupported }
        return source
    }
}

struct TestSpeechFactory: SpeechSessionFactory {
    let factory: @Sendable () async throws -> any SpeechSessionSource
    func makeSource() async throws -> any SpeechSessionSource { let source = try await factory(); return (source as? AsyncTestCoordinator)?.core ?? source }
}
func makeSelectableCoordinator(permissionCoordinator: any SpeechSessionSource,
    factory: @escaping @Sendable () async throws -> any SpeechSessionSource) -> AsyncTestCoordinator {
    .wrap(DefaultSelectableTranscriptionCoordinator(permissionCoordinator: permissionCoordinator,
        factory: TestSpeechFactory(factory: factory)))
}
func assertEventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertTrue(predicate(), "Expected async event delivery", file: file, line: line)
}

extension AsyncTestCoordinator: SpeechSessionSource {
    var supportedLanguages: [Locale] { core.supportedLanguages }
    var providerKind: ASRProviderType { core.providerKind }
    var isActive: Bool { core.isActive }
    var hasMicrophonePermission: Bool { core.hasMicrophonePermission }
    var hasSpeechPermission: Bool { core.hasSpeechPermission }
    func requestMicrophonePermission() async -> Bool { await core.requestMicrophonePermission() }
    func requestSpeechPermission() async -> Bool { await core.requestSpeechPermission() }
    func captureStates() -> AsyncStream<AudioCaptureState> { core.captureStates() }
    func audioLevels() -> AsyncStream<Float> { core.audioLevels() }
    func startSession(language: Locale) async throws -> any SpeechSession { try await core.startSession(language: language) }
}
