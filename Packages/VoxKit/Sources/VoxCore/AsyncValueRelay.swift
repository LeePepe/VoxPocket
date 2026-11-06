import Foundation
import Synchronization

public final class AsyncValueRelay<Value: Sendable>: Sendable {
    private struct Delivery: Sendable {
        let value: Value
        let continuations: [AsyncStream<Value>.Continuation]
    }
    private struct State: Sendable {
        var value: Value
        var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
        var pending: [Delivery] = []
        var delivering = false
    }
    private let state: Mutex<State>
    public init(_ value: Value) { state = Mutex(State(value: value)) }
    public var value: Value { state.withLock { $0.value } }
    public func send(_ value: Value) {
        let shouldDrain = state.withLock { state in
            state.value = value
            state.pending.append(Delivery(value: value, continuations: Array(state.continuations.values)))
            guard !state.delivering else { return false }
            state.delivering = true
            return true
        }
        if shouldDrain { drain() }
    }
    public func stream() -> AsyncStream<Value> {
        let id = UUID()
        let pair = AsyncStream<Value>.makeStream()
        pair.continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.continuations.removeValue(forKey: id) }
        }
        let shouldDrain = state.withLock { state in
            state.continuations[id] = pair.continuation
            state.pending.append(Delivery(value: state.value, continuations: [pair.continuation]))
            guard !state.delivering else { return false }
            state.delivering = true
            return true
        }
        if shouldDrain { drain() }
        return pair.stream
    }
    private func drain() {
        while let delivery = state.withLock({ state -> Delivery? in
            guard !state.pending.isEmpty else { state.delivering = false; return nil }
            return state.pending.removeFirst()
        }) {
            for continuation in delivery.continuations { continuation.yield(delivery.value) }
        }
    }
}
