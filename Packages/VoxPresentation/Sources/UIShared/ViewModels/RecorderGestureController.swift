import Foundation
import Combine

@MainActor
public final class RecorderGestureController: ObservableObject {
    public struct Capture {
        let isRecording: Bool
        let isProcessing: Bool
        let start: @MainActor () async -> Void
        let stop: @MainActor () async -> Void
        let cancel: @MainActor () async -> Void
    }
    private enum Release { case stop, cancel }
    public typealias MonotonicNow = @MainActor () -> TimeInterval
    private let holdDuration: TimeInterval
    private let now: MonotonicNow
    private var pressStartedAt: TimeInterval?
    private var pressStartedRecording = false
    private var ignoredPress = false
    private var isStarting = false
    private var ownsCapture = false
    private var pendingRelease: Release?
    private var capture: Capture?
    private var operation: Task<Void, Never>?
    @Published public private(set) var isBusy = false
    public var hasPress: Bool { pressStartedAt != nil }

    public init(holdDuration: TimeInterval = 0.28, now: @escaping MonotonicNow = { ProcessInfo.processInfo.systemUptime }) {
        self.holdDuration = holdDuration
        self.now = now
    }

    public func pressBegan(_ capture: Capture) {
        guard !hasPress, !ignoredPress, !isBusy, !capture.isProcessing else { return }
        self.capture = capture
        pressStartedAt = now()
        pressStartedRecording = capture.isRecording
        if !pressStartedRecording { beginStart(capture) }
    }

    public func pressEnded() {
        defer { ignoredPress = false }
        guard let started = pressStartedAt else { return }
        pressStartedAt = nil
        if pressStartedRecording || now() - started >= holdDuration { release(.stop) }
    }

    public func activate(_ capture: Capture) {
        guard !hasPress, !isBusy, !capture.isProcessing else { return }
        self.capture = capture
        pressStartedRecording = capture.isRecording
        if capture.isRecording { release(.stop) }
        else { beginStart(capture) }
    }

    public func cancel() {
        ignoredPress = hasPress
        pressStartedAt = nil
        guard ownsCapture || pressStartedRecording else { return }
        release(.cancel)
    }

    public func gestureReset() {
        if hasPress { cancel() }
        ignoredPress = false
    }

    public func waitForSettled() async {
        await operation?.value
    }

    private func beginStart(_ capture: Capture) {
        ownsCapture = true
        isBusy = true
        isStarting = true
        operation = Task {
            await capture.start()
            isStarting = false
            if let pendingRelease {
                self.pendingRelease = nil
                await finish(pendingRelease, capture: capture)
            }
            isBusy = false
        }
    }

    private func release(_ release: Release) {
        guard let capture else { return }
        if isBusy {
            guard isStarting else { return }
            // 启动完成之前保留松手／取消意图；取消优先于普通停止。
            if pendingRelease == nil || release == .cancel { pendingRelease = release }
            return
        }
        guard ownsCapture || pressStartedRecording else { return }
        isBusy = true
        operation = Task {
            await finish(release, capture: capture)
            isBusy = false
        }
    }

    private func finish(_ release: Release, capture: Capture) async {
        ownsCapture = false
        pressStartedRecording = false
        switch release {
        case .stop: await capture.stop()
        case .cancel: await capture.cancel()
        }
    }
}
