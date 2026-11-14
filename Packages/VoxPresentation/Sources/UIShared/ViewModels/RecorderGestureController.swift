import Foundation

@MainActor
public final class RecorderGestureController {
    public enum Action: Equatable { case start, stop, none }
    private var startedAt: Date?
    private var ownsCapture = false
    private let holdDuration: TimeInterval

    public init(holdDuration: TimeInterval = 0.28) { self.holdDuration = holdDuration }

    public func begin(isRecording: Bool, now: Date = Date()) -> Action {
        guard startedAt == nil else { return .none }
        startedAt = now
        ownsCapture = !isRecording
        return ownsCapture ? .start : .none
    }

    public func end(now: Date = Date()) -> Action {
        defer { startedAt = nil; ownsCapture = false }
        guard ownsCapture, let startedAt, now.timeIntervalSince(startedAt) + 0.000_001 >= holdDuration else { return .none }
        return .stop
    }

    public func activate(isRecording: Bool) -> Action { isRecording ? .stop : .start }
    public func cancel() { startedAt = nil; ownsCapture = false }
}
