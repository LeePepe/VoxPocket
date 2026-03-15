import Testing
@testable import VoxPocket

struct QuickRecordingWindowLifecycleTests {
    @MainActor
    @Test func quickRecordingWindowIsRecreatedAfterHide() {
        let windowManager = WindowManager.shared

        windowManager.closeWindow(.quickRecording)
        defer {
            windowManager.closeWindow(.quickRecording)
        }

        windowManager.showWindow(.quickRecording)
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
