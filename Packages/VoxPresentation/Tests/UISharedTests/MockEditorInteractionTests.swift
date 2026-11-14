import XCTest
@testable import UIShared

@MainActor
final class MockEditorInteractionTests: XCTestCase {
    func testStopRefinesReleaseDrivenPodcastCopy() async {
        let editor = MockEditorViewModel()
        await editor.startRecording()
        await Task.yield()
        XCTAssertTrue(editor.isRecording)
        await editor.stopRecording()
        XCTAssertFalse(editor.isRecording)
        XCTAssertFalse(editor.isRefining)
        XCTAssertTrue(editor.text.contains("播客开场灵感"))
    }
}
