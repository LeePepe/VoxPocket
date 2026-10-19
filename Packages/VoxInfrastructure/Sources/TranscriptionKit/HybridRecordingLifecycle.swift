import Foundation
import Synchronization

/// 将启动取消与录音收尾分开；停止等待旧启动清理完毕，才允许下一次会话。
final class HybridRecordingLifecycle: Sendable {
    struct Session: Sendable {
        let id: UUID
        var locale: Locale
        var appleText = ""
        var cloudText = ""
        var realtime: RealtimeAudioPipeline?
        var cancelRealtime: (@Sendable () async -> Void)?
        var isQuick = false
        var hasRecognizedSpeech = false
        var release: QuickRecordingReleaseSnapshot?
        var releaseClaimed = false

        var shouldFinalize: Bool { realtime?.hasMinimumAudio == true || !appleText.isEmpty || !cloudText.isEmpty }
    }
    enum StopAction: Sendable {
        case none
        case cancelStart(Session)
        case finish(Session)
        case discard(Session)
    }
    private struct State {
        enum Phase { case idle, prepared, starting, cancelling, recording, finishing }
        var phase: Phase = .idle
        var session: Session?
        var cleanupWaiters: [CheckedContinuation<Void, Never>] = []
        var startupWaiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())

    var isRecording: Bool { state.withLock { $0.phase == .recording } }

    func prepareQuickRecording() throws {
        try state.withLock { state in
            guard state.phase == .idle else { throw RealtimeTranscriptionError.protocolRejected }
            state.session = Session(id: UUID(), locale: Locale(identifier: "zh-Hans"), isQuick: true)
            state.phase = .prepared
        }
    }

    func begin(locale: Locale) throws -> UUID {
        try state.withLock { state in
            if state.phase == .prepared, let session = state.session {
                guard session.release?.hasRecognizedSpeech != false else { throw CancellationError() }
                state.session?.locale = locale
                state.phase = .starting
                return session.id
            }
            guard state.phase == .idle else { throw RealtimeTranscriptionError.protocolRejected }
            let id = UUID()
            state.session = Session(id: id, locale: locale)
            state.phase = .starting
            return id
        }
    }

    func isStarting(_ id: UUID) -> Bool {
        state.withLock {
            $0.session?.id == id && $0.phase == .starting && $0.session?.release?.hasRecognizedSpeech != false
        }
    }

    func attach(_ pipeline: RealtimeAudioPipeline?, id: UUID,
                cancelRealtime: (@Sendable () async -> Void)? = nil) throws {
        try state.withLock { state in
            guard state.session?.id == id, state.phase == .starting,
                  state.session?.release?.hasRecognizedSpeech != false else { throw CancellationError() }
            state.session?.realtime = pipeline
            state.session?.cancelRealtime = cancelRealtime
        }
    }

    func didStart(_ id: UUID) throws {
        let waiters = try state.withLock { state in
            guard state.session?.id == id, state.phase == .starting,
                  state.session?.release?.hasRecognizedSpeech != false else { throw CancellationError() }
            state.phase = .recording
            let waiters = state.startupWaiters
            state.startupWaiters = []
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    func receiveApple(_ text: String, id: UUID, retainText: Bool = true) -> Bool {
        state.withLock { state in
            guard state.session?.id == id, state.phase == .starting || state.phase == .recording,
                  state.session?.release?.hasRecognizedSpeech != false else { return false }
            if retainText, !text.isEmpty { state.session?.appleText = text }
            if state.session?.release == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.session?.hasRecognizedSpeech = true
            }
            return state.session?.cloudText.isEmpty == true
        }
    }

    func receiveCloud(_ text: String, id: UUID) -> Bool {
        state.withLock { state in
            guard state.session?.id == id, state.phase == .recording || state.phase == .finishing,
                  state.session?.release?.hasRecognizedSpeech != false else { return false }
            state.session?.cloudText = text
            return true
        }
    }

    func restoreApplePreview(_ id: UUID) -> String? {
        state.withLock { state in
            guard state.session?.id == id, state.phase == .recording,
                  state.session?.release?.hasRecognizedSpeech != false else { return nil }
            state.session?.cloudText = ""
            return state.session?.appleText
        }
    }

    func requestStop() -> StopAction {
        state.withLock { state in
            guard let session = state.session else { return .none }
            switch state.phase {
            case .prepared:
                state.phase = .finishing
                return .discard(session)
            case .starting, .cancelling:
                state.phase = .cancelling
                return .cancelStart(session)
            case .recording:
                state.phase = .finishing
                return .finish(session)
            case .idle, .finishing: return .none
            }
        }
    }

    func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        try state.withLock { state in
            guard let session = state.session, session.isQuick else {
                throw QuickRecordingReleaseError.noPreparedSession
            }
            if let frozen = session.release { return frozen }
            let frozen = QuickRecordingReleaseSnapshot(sessionID: session.id,
                                                       hasRecognizedSpeech: session.hasRecognizedSpeech)
            state.session?.release = frozen
            return frozen
        }
    }

    func claimQuickRelease(_ snapshot: QuickRecordingReleaseSnapshot) -> StopAction {
        state.withLock { state in
            guard let session = state.session, session.id == snapshot.sessionID,
                  let frozen = session.release, !session.releaseClaimed,
                  !snapshot.hasRecognizedSpeech || frozen.hasRecognizedSpeech else { return .none }
            var claimed = session
            claimed.release = snapshot
            claimed.releaseClaimed = true
            state.session = claimed
            if !snapshot.hasRecognizedSpeech, state.phase == .starting || state.phase == .cancelling {
                state.phase = .cancelling
                return .cancelStart(claimed)
            }
            state.phase = .finishing
            return snapshot.hasRecognizedSpeech ? .finish(claimed) : .discard(claimed)
        }
    }

    func acceptsAppleResult(_ id: UUID) -> Bool {
        state.withLock {
            $0.session?.id == id && $0.phase != .cancelling &&
                $0.session?.release?.hasRecognizedSpeech != false
        }
    }

    func session(_ id: UUID) -> Session? {
        state.withLock { $0.session?.id == id ? $0.session : nil }
    }

    func waitForStartup(_ id: UUID) async {
        await withCheckedContinuation { continuation in
            let finished = state.withLock { state in
                guard state.session?.id == id, state.phase == .starting else { return true }
                state.startupWaiters.append(continuation)
                return false
            }
            if finished { continuation.resume() }
        }
    }

    func waitForCleanup(_ id: UUID) async {
        await withCheckedContinuation { continuation in
            let alreadyClean = state.withLock { state in
                guard state.session?.id == id else { return true }
                state.cleanupWaiters.append(continuation)
                return false
            }
            if alreadyClean { continuation.resume() }
        }
    }

    func complete(_ id: UUID, keepResults: Bool = false) {
        let waiters = state.withLock { state in
            guard state.session?.id == id else { return [CheckedContinuation<Void, Never>]() }
            let waiters = state.cleanupWaiters + state.startupWaiters
            let session = state.session
            state = State()
            if keepResults { state.session = session }
            return waiters
        }
        waiters.forEach { $0.resume() }
    }
}
