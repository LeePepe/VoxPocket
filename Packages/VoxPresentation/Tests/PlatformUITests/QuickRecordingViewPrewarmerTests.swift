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
        prewarmer.prepare()
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
        let host = NSHostingView(rootView: QuickRecordingIslandView(status: .listening, transcript: ""))
        let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 480, height: 148),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { heartbeat.cancel(); panel.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        print("Cold presentation maximum main-thread gap: \(maximumGap)ms")
        XCTAssertLessThan(maximumGap, 50)
    }

    func testPreparingEmptyViewDoesNotPresentAWindowOrChangeFocus() {
        let prewarmer = QuickRecordingViewPrewarmer()
        let visible = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        let key = NSApp.keyWindow
        XCTAssertFalse(prewarmer.isPrepared)
        prewarmer.prepare()
        XCTAssertTrue(prewarmer.isPrepared)
        prewarmer.prepare()
        XCTAssertEqual(Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber)), visible)
        XCTAssertTrue(NSApp.keyWindow === key)
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
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertTrue(prewarmer.isPrepared)
        XCTAssertFalse(prewarmer.isScheduled)
        prewarmer.schedule()
        XCTAssertFalse(prewarmer.isScheduled)
    }
}
#endif
