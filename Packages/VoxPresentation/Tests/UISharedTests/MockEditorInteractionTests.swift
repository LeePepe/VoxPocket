import XCTest
@testable import UIShared

@MainActor
final class MockEditorInteractionTests: XCTestCase {
    func testStopRefinesReleaseDrivenPodcastCopy() async {
        let editor = MockEditorViewModel(refinementStep: {})
        await editor.startRecording()
        await Task.yield()
        XCTAssertTrue(editor.isRecording)
        await editor.stopRecording()
        XCTAssertFalse(editor.isRecording)
        XCTAssertFalse(editor.isRefining)
        XCTAssertTrue(editor.text.contains("播客开场灵感"))
    }

    func testNewerTextInvalidatesPausedRefinement() async {
        let gate = RecorderTestGate()
        let editor = MockEditorViewModel(refinementStep: { await gate.suspend() })
        let refinement = Task { await editor.refine() }
        await gate.waitForEntries()
        editor.updateText("Newer synthetic session text", range: NSRange(location: 0, length: 0))
        await gate.releaseNext()
        await refinement.value
        XCTAssertEqual(editor.text, "Newer synthetic session text")
        XCTAssertTrue(editor.streamingRefinedText.isEmpty)
        XCTAssertFalse(editor.isRefining)
    }

    func testCancelledRefinementCannotAppendOrOverwriteNewSession() async {
        let gate = RecorderTestGate()
        let editor = MockEditorViewModel(refinementStep: { await gate.suspend() })
        await editor.startRecording()
        let oldStop = Task { await editor.stopRecording() }
        await gate.waitForEntries()
        editor.cancelRefinement()
        await editor.startNewSession()
        XCTAssertTrue(editor.isRecording)
        XCTAssertTrue(editor.text.isEmpty)
        await gate.releaseNext()
        await oldStop.value
        XCTAssertTrue(editor.streamingRefinedText.isEmpty)
        XCTAssertTrue(editor.text.isEmpty)
        XCTAssertTrue(editor.isRecording)
        XCTAssertFalse(editor.isRefining)
    }
}
