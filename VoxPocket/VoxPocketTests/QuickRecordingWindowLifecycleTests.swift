#if os(macOS)
import Testing
import AppKit
import PlatformUI
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
