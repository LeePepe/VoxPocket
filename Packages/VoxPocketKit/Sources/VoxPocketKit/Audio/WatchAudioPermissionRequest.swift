import Foundation
import Synchronization

final class WatchAudioPermissionRequest: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Bool, Never>?
        var result: Bool?
    }
    private let state = Mutex(State())
    func value(timeout: Duration = .seconds(30), request: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void) async -> Bool {
        let timer = Task { [self] in
            do { try await Task.sleep(for: timeout); finish(false) } catch {}
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let result = state.withLock { value -> Bool? in
                    if let result = value.result { return result }
                    value.continuation = continuation; return nil
                }
                if let result { continuation.resume(returning: result); return }
                guard !Task.isCancelled else { finish(false); return }
                request { [self] in finish($0) }
            }
        } onCancel: { [self] in finish(false) }
    }
    private func finish(_ result: Bool) {
        let continuation = state.withLock { value -> CheckedContinuation<Bool, Never>? in
            guard value.result == nil else { return nil }
            value.result = result; let continuation = value.continuation; value.continuation = nil
            return continuation
        }
        continuation?.resume(returning: result)
    }
}
