import Foundation
import Synchronization

nonisolated final class WatchRecognitionOnce<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Error>?
        var result: Result<Value, Error>?
    }
    private let state = Mutex(State())
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let result = state.withLock { value -> Result<Value, Error>? in
            if let result = value.result { return result }
            value.continuation = continuation; return nil
        }
        if let result { continuation.resume(with: result) }
    }
    func finish(_ result: Result<Value, Error>) {
        let continuation = state.withLock { value -> CheckedContinuation<Value, Error>? in
            guard value.result == nil else { return nil }
            value.result = result; let continuation = value.continuation; value.continuation = nil; return continuation
        }
        continuation?.resume(with: result)
    }
}
