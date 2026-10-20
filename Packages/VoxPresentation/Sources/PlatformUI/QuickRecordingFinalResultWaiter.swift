#if os(macOS)
import Combine
import Foundation
import Synchronization
import TranscriptionKit

/// 在停止录音前同步订阅，避免 Passthrough 终稿先于等待任务到达。
@MainActor
final class QuickRecordingFinalResultWaiter {
    /// 仅桥接 Combine 非 Sendable 取消令牌；引用不可变，跨任务访问只调用线程安全的 cancel。
    private final class Subscription: @unchecked Sendable {
        private let token: AnyCancellable
        init(_ token: AnyCancellable) { self.token = token }
        func cancel() { token.cancel() }
    }
    private final class Capture: Sendable {
        private struct State {
            var text: String?
            var subscription: Subscription?
            var terminated = false
        }
        private let state = Mutex(State())
        var text: String? { state.withLock { $0.text } }
        func receive(_ text: String) {
            state.withLock { if !$0.terminated { $0.text = text } }
        }
        func install(_ token: Subscription) {
            let rejected = state.withLock { value -> Subscription? in
                guard !value.terminated else { return token }
                value.subscription = token
                return nil
            }
            rejected?.cancel()
        }
        func cancel() {
            let token = state.withLock { value in
                value.terminated = true
                let token = value.subscription
                value.subscription = nil
                return token
            }
            token?.cancel()
        }
    }
    private let capture: Capture
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    let task: Task<String?, Never>
    private let timeout: Duration
    private var deadlineTask: Task<Void, Never>?

    var capturedText: String? { capture.text }

    init(
        publisher: AnyPublisher<TranscriptionResult, Error>,
        timeout: Duration = QuickRecordingReleaseLifecycle.recognitionTimeout,
        armImmediately: Bool = true
    ) {
        self.timeout = timeout
        let pair = AsyncThrowingStream<String, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = pair.continuation
        let capture = Capture()
        self.capture = capture
        pair.continuation.onTermination = { _ in capture.cancel() }
        let token = publisher.first().sink(receiveCompletion: { @Sendable completion in
            switch completion {
            case .finished: pair.continuation.finish()
            case .failure(let error): pair.continuation.finish(throwing: error)
            }
        }, receiveValue: { @Sendable result in
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            capture.receive(text)
            pair.continuation.yield(text)
            pair.continuation.finish()
        })
        capture.install(Subscription(token))
        task = Task {
            do {
                for try await text in pair.stream { return text.isEmpty ? nil : text }
            } catch { return nil }
            return nil
        }
        if armImmediately { armDeadline() }
    }

    /// 捕获可以早于 release；等待预算只能从 release 开始且不可重置。
    func armDeadline() {
        guard deadlineTask == nil else { return }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        deadlineTask = Task { [continuation] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            continuation.finish()
        }
    }

    func cancel() {
        deadlineTask?.cancel()
        capture.cancel()
        continuation.finish()
        task.cancel()
    }
}
#endif
