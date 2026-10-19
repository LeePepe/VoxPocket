#if os(macOS)
import Testing
import AppKit
import PlatformUI
import UIShared
@testable import VoxPocket

@Suite(.serialized)
struct QuickRecordingWindowLifecycleTests {
    @MainActor
    @Test func prewarmingDoesNotCreateRecordingSessionOrVisiblePanel() async throws {
        let windowManager = WindowManager.shared
        windowManager.closeWindow(.quickRecording)
        windowManager.scheduleQuickRecordingPrewarm()
        try await Task.sleep(for: .milliseconds(800))
        #expect(windowManager.getQuickRecordingViewModel() == nil)
        #expect(windowManager.windowVisibility[.quickRecording] == false)
        #expect(!NSApp.windows.contains { $0 is QuickRecordingPanel && $0.isVisible })
    }

    @MainActor
    @Test func releaseDismissalKeepsListeningModelUntilTerminalClose() async {
        let manager = WindowManager.shared
        manager.closeWindow(.quickRecording)
        defer { manager.closeWindow(.quickRecording) }
        manager.showWindow(.quickRecording)
        let model = requireNotNil(manager.getQuickRecordingViewModel())
        model.recorderStatus = .listening

        #expect(manager.dismissQuickRecordingWindow())
        #expect(manager.windowVisibility[.quickRecording] == false)
        #expect(!NSApp.windows.contains { $0 is QuickRecordingPanel && $0.isVisible })
        #expect(manager.getQuickRecordingViewModel() === model)
        for _ in 0..<100 { await Task.yield() }
        #expect(model.recorderStatus == .listening)
        #expect(!manager.dismissQuickRecordingWindow())

        model.recorderStatus = .idle
        manager.closeWindow(.quickRecording)
        #expect(manager.getQuickRecordingViewModel() == nil)
        manager.showWindow(.quickRecording)
        #expect(manager.getQuickRecordingViewModel() !== model)
    }

    @MainActor
    @Test func quickRecordingWindowIsRecreatedAfterHide() {
        let windowManager = WindowManager.shared

        windowManager.closeWindow(.quickRecording)
        defer {
            windowManager.closeWindow(.quickRecording)
        }

        windowManager.showWindow(.quickRecording)
        #expect(NSApp.windows.contains { $0 is QuickRecordingPanel && $0.isVisible })
        let firstViewModel = requireNotNil(windowManager.getQuickRecordingViewModel())

        windowManager.hideWindow(.quickRecording)
        windowManager.showWindow(.quickRecording)
        let secondViewModel = requireNotNil(windowManager.getQuickRecordingViewModel())

        #expect(firstViewModel as AnyObject !== secondViewModel as AnyObject)
    }
}

@MainActor
private func requireNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) -> T {
    let unwrapped = value
    #expect(unwrapped != nil, sourceLocation: sourceLocation)
    return unwrapped!
}
#endif
