import Foundation
import Synchronization

/// 将启动取消与录音收尾分开；停止等待旧启动清理完毕，才允许下一次会话。
final class HybridRecordingLifecycle: Sendable {
    struct Session: Sendable {
        let id: UUID
        let locale: Locale
        var appleText = ""
        var cloudText = ""
        var realtime: RealtimeAudioPipeline?

        var shouldFinalize: Bool { realtime != nil || !appleText.isEmpty || !cloudText.isEmpty }
    }
    enum StopAction: Sendable {
        case none
        case cancelStart(Session)
        case finish(Session)
    }
    private struct State {
        enum Phase { case idle, starting, cancelling, recording, finishing }
        var phase: Phase = .idle
        var session: Session?
        var cleanupWaiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())

    var isRecording: Bool { state.withLock { $0.phase == .recording } }

    func begin(locale: Locale) throws -> UUID {
        try state.withLock { state in
            guard state.phase == .idle else { throw RealtimeTranscriptionError.protocolRejected }
            let id = UUID()
            state.session = Session(id: id, locale: locale)
            state.phase = .starting
            return id
        }
    }

    func isStarting(_ id: UUID) -> Bool {
        state.withLock { $0.session?.id == id && $0.phase == .starting }
    }

    func attach(_ pipeline: RealtimeAudioPipeline?, id: UUID) throws {
        try state.withLock { state in
            guard state.session?.id == id, state.phase == .starting else { throw CancellationError() }
            state.session?.realtime = pipeline
        }
    }

    func didStart(_ id: UUID) throws {
        try state.withLock { state in
            guard state.session?.id == id, state.phase == .starting else { throw CancellationError() }
            state.phase = .recording
        }
    }

    func receiveApple(_ text: String, id: UUID) -> Bool {
        state.withLock { state in
            guard state.session?.id == id, state.phase == .recording else { return false }
            if !text.isEmpty { state.session?.appleText = text }
            return state.session?.cloudText.isEmpty == true
        }
    }

    func receiveCloud(_ text: String, id: UUID) -> Bool {
        state.withLock { state in
            guard state.session?.id == id, state.phase == .recording || state.phase == .finishing else { return false }
            state.session?.cloudText = text
            return true
        }
    }

    func requestStop() -> StopAction {
        state.withLock { state in
            guard let session = state.session else { return .none }
            switch state.phase {
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

    func complete(_ id: UUID) {
        let waiters = state.withLock { state in
            guard state.session?.id == id else { return [CheckedContinuation<Void, Never>]() }
            let waiters = state.cleanupWaiters
            state = State()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }
}
