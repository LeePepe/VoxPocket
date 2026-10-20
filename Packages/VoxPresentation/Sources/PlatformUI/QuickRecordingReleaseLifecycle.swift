#if os(macOS)
import Foundation

/// 只管理 release 后的视觉生命周期；不取消识别或提前释放后台所有权。
@MainActor
public final class QuickRecordingReleaseLifecycle {
    public static let recognitionTimeout: Duration = .seconds(15)
    private let timeout: Duration
    private var releasedAt: ContinuousClock.Instant?
    private var hidden = false
    private var watchdog: Task<Void, Never>?

    public var isReleased: Bool { releasedAt != nil }

    public init(timeout: Duration = recognitionTimeout) { self.timeout = timeout }

    public func release(at instant: ContinuousClock.Instant = .now) {
        guard releasedAt == nil else { return }
        releasedAt = instant
    }

    public func armWatchdog(onDeadline: @escaping @MainActor () -> Void) {
        guard let releasedAt, !hidden, watchdog == nil else { return }
        let deadline = releasedAt.advanced(by: timeout)
        watchdog = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            guard let self, !self.hidden else { return }
            onDeadline()
        }
    }

    /// 返回实际 hide 的 release 耗时；重复、未 release 或已经不可见时不记关闭事件。
    public func hide(dismiss: () -> Bool) -> Double? {
        guard let releasedAt, !hidden else { return nil }
        hidden = true
        cancel()
        guard dismiss() else { return nil }
        let elapsed = releasedAt.duration(to: .now).components
        return max(0, Double(elapsed.seconds) * 1_000
            + Double(elapsed.attoseconds) / 1_000_000_000_000_000)
    }

    public func cancel() {
        watchdog?.cancel()
        watchdog = nil
    }
}
#endif
