#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import PlatformUI

@MainActor
final class QuickRecordingViewPrewarmerTests: XCTestCase {
    /// 性能阈值只在显式诊断时启用，避免共享 CI 的负载让功能测试不稳定。
    func testColdPresentationBudgetWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["VOX_COLD_RENDER_CHECK"] == "1" else { return }
        let prewarmer = QuickRecordingViewPrewarmer()
        var maximumGap = 0.0
        let start = ProcessInfo.processInfo.systemUptime
        let heartbeat = Task { @MainActor in
            var previous = start
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(4)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                maximumGap = max(maximumGap, (now - previous) * 1000)
                previous = now
            }
        }
        await Task.yield()
        try await prewarmer.prepare()
        try await Task.sleep(for: .milliseconds(16))
        let prewarmingGap = maximumGap
        maximumGap = 0
        let host = NSHostingView(rootView: QuickRecordingIslandView(status: .listening, transcript: ""))
        let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 480, height: 148),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { heartbeat.cancel(); panel.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        print("Prewarming maximum main-thread gap: \(prewarmingGap)ms; first presentation: \(maximumGap)ms")
        XCTAssertLessThan(prewarmingGap, 50, "预热不能把首次 Fn 的卡顿转移到启动后")
        XCTAssertLessThan(maximumGap, 50)
    }

    func testPreparingEmptyViewDoesNotPresentAWindowOrChangeFocus() async throws {
        let prewarmer = QuickRecordingViewPrewarmer()
        let visible = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        let key = NSApp.keyWindow
        XCTAssertFalse(prewarmer.isPrepared)
        try await prewarmer.prepare()
        XCTAssertTrue(prewarmer.isPrepared)
        try await prewarmer.prepare()
        XCTAssertEqual(Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber)), visible)
        XCTAssertTrue(NSApp.keyWindow === key)
    }

    func testCancelledPreparationCanBeRetriedWithoutMarkingItPrepared() async throws {
        let prewarmer = QuickRecordingViewPrewarmer()
        let preparation = Task { @MainActor in try await prewarmer.prepare() }
        preparation.cancel()
        do {
            try await preparation.value
            XCTFail("已取消的预热不应继续")
        } catch is CancellationError {
            XCTAssertFalse(prewarmer.isPrepared)
        }
        try await prewarmer.prepare()
        XCTAssertTrue(prewarmer.isPrepared)
    }

    func testCancelBeforeFirstPressPreventsDeferredWork() async throws {
        let prewarmer = QuickRecordingViewPrewarmer()
        prewarmer.schedule()
        prewarmer.schedule()
        XCTAssertTrue(prewarmer.isScheduled)
        prewarmer.cancelPending()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(prewarmer.isPrepared)
        XCTAssertFalse(prewarmer.isScheduled)
    }

    func testScheduledWarmupCompletesOnceAndCanBeRescheduledAfterCancellation() async throws {
        let prewarmer = QuickRecordingViewPrewarmer()
        prewarmer.schedule()
        prewarmer.cancelPending()
        prewarmer.schedule()
        // 等待实际完成状态，而不是假定低优先级任务在固定墙钟时刻已获得执行权。
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (!prewarmer.isPrepared || prewarmer.isScheduled) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(prewarmer.isPrepared)
        XCTAssertFalse(prewarmer.isScheduled)
        prewarmer.schedule()
        XCTAssertFalse(prewarmer.isScheduled)
    }
}
#endif
