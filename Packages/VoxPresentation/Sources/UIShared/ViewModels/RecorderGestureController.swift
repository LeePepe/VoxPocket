import Foundation

@MainActor
public final class RecorderGestureController {
    public enum Action: Equatable { case start, stop, none }
    public typealias MonotonicNow = @MainActor () -> TimeInterval
    private let holdDuration: TimeInterval
    private let now: MonotonicNow
    private var pressStartedAt: TimeInterval?
    private var ownsCapture = false
    private var pendingStop = false

    public init(holdDuration: TimeInterval = 0.28, now: @escaping MonotonicNow = { ProcessInfo.processInfo.systemUptime }) {
        self.holdDuration = holdDuration
        self.now = now
    }

    public func begin(isRecording: Bool) -> Action {
        guard pressStartedAt == nil else { return .none }
        pressStartedAt = now()
        ownsCapture = !isRecording
        return ownsCapture ? .start : .none
    }

    public func end() -> Action {
        defer { pressStartedAt = nil; ownsCapture = false; pendingStop = false }
        guard ownsCapture, let started = pressStartedAt else { return .none }
        guard now() - started >= holdDuration else { return .none }
        pendingStop = true
        return .stop
    }

    public func activate(isRecording: Bool) -> Action { isRecording ? .stop : .start }
    public func cancel() { pressStartedAt = nil; ownsCapture = false; pendingStop = false }
    public func sceneEnded() -> Action { ownsCapture ? .stop : .none }
    public var hasPendingStop: Bool { pendingStop }
}
