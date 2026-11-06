import Foundation
import Synchronization
import VoxCore

public final class DefaultSelectableTranscriptionCoordinator: SessionDriving, QuickRecordingReleaseControlling {
    private struct Subscriptions: Sendable {
        let values: [Task<Void, Never>]
        func cancel() { values.forEach { $0.cancel() } }
    }
    private struct State {
        enum Phase { case idle, prepared, starting, recording, stopping }
        var phase: Phase = .idle
        var id = UUID()
        var active: (any SpeechSessionSource)?
        var session: (any SpeechSession)?
        var startup: Task<Void, Error>?
        var subscriptions: Subscriptions?
        var isQuick = false
        var release: QuickRecordingReleaseSnapshot?
        var sourceRelease: QuickRecordingReleaseSnapshot?
        var releaseClaimed = false
        var muted = false
    }
    private let stateLock = Mutex(State())
    private let factory: any SpeechSessionFactory
    private let permissions: any SpeechSessionSource
    let sessionRelay = SpeechSessionRelay()
    private let levels = AsyncValueRelay<Float>(0)
    private let capture = AsyncValueRelay<AudioCaptureState>(.idle)

    public init(permissionCoordinator: any SpeechSessionSource,
                factory: any SpeechSessionFactory) {
        permissions = permissionCoordinator
        self.factory = factory
    }

    public var providerKind: ASRProviderType { .custom }
    public var supportedLanguages: [Locale] { permissions.supportedLanguages }
    public var hasMicrophonePermission: Bool { permissions.hasMicrophonePermission }
    public var hasSpeechPermission: Bool { permissions.hasSpeechPermission }
    public var isActive: Bool { stateLock.withLock { $0.phase == .recording } }
    public func captureStates() -> AsyncStream<AudioCaptureState> { capture.stream() }
    public func audioLevels() -> AsyncStream<Float> { levels.stream() }
    public func requestMicrophonePermission() async -> Bool { await permissions.requestMicrophonePermission() }
    public func requestSpeechPermission() async -> Bool { await permissions.requestSpeechPermission() }

    public func start(language: Locale) async throws {
        let prepared = try stateLock.withLock { state in
            guard state.phase == .idle || state.phase == .prepared else {
                throw RealtimeTranscriptionError.protocolRejected
            }
            guard state.release?.hasRecognizedSpeech != false else { throw CancellationError() }
            // 旧订阅在锁外取消，避免 Combine 取消回调重入同一把锁。
            let old = (state.active, state.subscriptions)
            state.active = nil; state.subscriptions = nil
            state.phase = .starting
            if !state.isQuick { state.id = UUID(); state.muted = false }
            let id = state.id
            let task = Task { try await self.startSession(id: id, language: language) }
            state.startup = task
            return (task, old)
        }
        prepared.1.1?.cancel()
        let task = prepared.0
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func startSession(id: UUID, language: Locale) async throws {
        do {
            let chosen = try await factory.makeSource()
            try Task.checkCancellation()
            try attach(chosen, id: id)
            let session = try await chosen.startSession(language: language)
            let subscriptions = bind(chosen, session: session, id: id)
            stateLock.withLock { $0.subscriptions = subscriptions; $0.session = session }
            try Task.checkCancellation()
            stateLock.withLock {
                guard $0.id == id else { return }
                $0.phase = .recording; $0.startup = nil
            }
        } catch {
            if stateLock.withLock({ $0.id == id && $0.isQuick }) {
                await failQuickStartup(id: id)
            } else {
                await stateLock.withLock { $0.session }?.cancel()
                clear(id)
            }
            throw error
        }
    }

    private func attach(_ chosen: any SpeechSessionSource, id: UUID) throws {
        try stateLock.withLock { state in
            guard state.id == id, state.phase == .starting,
                  state.release?.hasRecognizedSpeech != false else { throw CancellationError() }
            if state.isQuick {
                guard let source = chosen as? any QuickRecordingReleaseControlling else {
                    throw QuickRecordingReleaseError.unsupported
                }
                try source.prepareQuickRecording()
            }
            state.active = chosen
        }
    }

    private func failQuickStartup(id: UUID) async {
        defer { clear(id) }
        let active = stateLock.withLock { state -> (any SpeechSessionSource)? in
            guard state.id == id else { return nil }
            state.startup = nil; state.phase = .stopping; state.muted = true
            return state.active
        }
        guard let source = active as? any QuickRecordingReleaseControlling,
              let frozen = try? source.freezeQuickRecordingRelease() else { return }
        let discard = QuickRecordingReleaseSnapshot(sessionID: frozen.sessionID, hasRecognizedSpeech: false)
        try? await source.completeQuickRecordingRelease(discard)
    }

    public func prepareQuickRecording() throws {
        let old = try stateLock.withLock { state in
            guard state.phase == .idle else { throw RealtimeTranscriptionError.protocolRejected }
            let old = state.subscriptions
            state = State()
            state.phase = .prepared; state.isQuick = true
            return old
        }
        old?.cancel()
    }

    public func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        try stateLock.withLock { state in
            guard state.isQuick else { throw QuickRecordingReleaseError.noPreparedSession }
            if let frozen = state.release { return frozen }
            let source = state.active as? any QuickRecordingReleaseControlling
            let sourceRelease = try source?.freezeQuickRecordingRelease()
            let frozen = QuickRecordingReleaseSnapshot(sessionID: state.id,
                                                       hasRecognizedSpeech: sourceRelease?.hasRecognizedSpeech == true)
            state.sourceRelease = sourceRelease; state.release = frozen
            state.muted = !frozen.hasRecognizedSpeech
            return frozen
        }
    }

    public func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        let pending = stateLock.withLock { state -> (Bool, Task<Void, Error>?) in
            guard state.id == snapshot.sessionID, let frozen = state.release, !state.releaseClaimed,
                  !snapshot.hasRecognizedSpeech || frozen.hasRecognizedSpeech else { return (false, nil) }
            state.releaseClaimed = true; state.phase = .stopping
            state.muted = !snapshot.hasRecognizedSpeech
            return (true, state.startup)
        }
        guard pending.0 else { return }
        defer { clear(snapshot.sessionID, keepResults: snapshot.hasRecognizedSpeech) }
        if !snapshot.hasRecognizedSpeech { pending.1?.cancel() }
        if let task = pending.1 { _ = await task.result }
        let source = stateLock.withLock { state -> (any QuickRecordingReleaseControlling, QuickRecordingReleaseSnapshot)? in
            // 启动失败可能已清掉旧会话；不能把旧决定转发给随后启动的新会话。
            guard state.id == snapshot.sessionID,
                  let capability = state.active as? any QuickRecordingReleaseControlling,
                  let frozen = state.sourceRelease else { return nil }
            return (capability, frozen)
        }
        guard let (capability, frozen) = source else { return }
        try await capability.completeQuickRecordingRelease(.init(sessionID: frozen.sessionID,
                                                                 hasRecognizedSpeech: snapshot.hasRecognizedSpeech))
    }

    public func stop() async {
        let snapshot = stateLock.withLock { state -> (Task<Void, Error>?, (any SpeechSessionSource)?, UUID) in
            switch state.phase {
            case .starting: return (state.startup, nil, state.id)
            case .recording:
                state.phase = .stopping
                return (nil, state.active, state.id)
            case .prepared, .idle, .stopping: return (nil, nil, state.id)
            }
        }
        if let startup = snapshot.0 {
            startup.cancel()
            _ = await startup.result
            // start 可能恰好先完成；停止这一代，不能影响清理后新开的录音。
            let active = stateLock.withLock { state -> (any SpeechSessionSource)? in
                guard state.id == snapshot.2, state.phase == .recording else { return nil }
                state.phase = .stopping
                return state.active
            }
            if active != nil { await stateLock.withLock { $0.session }?.stop(); clear(snapshot.2, keepResults: true) }
        } else if snapshot.1 != nil {
            await stateLock.withLock { $0.session }?.stop()
            clear(snapshot.2, keepResults: true)
        }
    }

    public func pause() async { await stateLock.withLock { $0.session }?.pause() }
    public func resume() async { await stateLock.withLock { $0.session }?.resume() }

    private func isCurrent(_ id: UUID) -> Bool {
        // Apple Speech.stop 返回后才可能发出终稿；保留这一代直到下一次 start。
        stateLock.withLock { $0.id == id && $0.active != nil && !$0.muted }
    }

    private func bind(_ chosen: any SpeechSessionSource, session: any SpeechSession, id: UUID) -> Subscriptions {
        let states = chosen.captureStates()
        let audio = chosen.audioLevels()
        let events = session.events()
        return Subscriptions(values: [
            Task { [weak self] in
                do {
                    for try await event in events {
                        guard let self, self.isCurrent(id), !Task.isCancelled else { continue }
                        if case .level = event { continue }
                        self.sessionRelay.send(event)
                    }
                } catch {
                    guard let self, self.isCurrent(id) else { return }
                    self.capture.send(.error("语音识别失败，请重试。"))
                    self.sessionRelay.finish(throwing: error)
                }
            },
            Task { [weak self] in
                for await state in states {
                    guard let self, self.isCurrent(id), !Task.isCancelled else { continue }
                    self.capture.send(state)
                }
            },
            Task { [weak self] in
                for await level in audio {
                    guard let self, self.isCurrent(id), !Task.isCancelled else { continue }
                    self.levels.send(level)
                }
            }
        ])
    }

    private func clear(_ id: UUID, keepResults: Bool = false) {
        let result = stateLock.withLock { state -> (Bool, Subscriptions?, (any SpeechSessionSource)?) in
            guard state.id == id else { return (false, nil, nil) }
            state.phase = .idle; state.startup = nil; state.isQuick = false
            state.release = nil; state.sourceRelease = nil; state.releaseClaimed = false
            if keepResults { return (true, nil, nil) }
            let old = (state.subscriptions, state.active)
            state.subscriptions = nil; state.active = nil
            return (true, old.0, old.1)
        }
        guard result.0 else { return }
        result.1?.cancel()
        levels.send(0); capture.send(.idle)
    }
}
