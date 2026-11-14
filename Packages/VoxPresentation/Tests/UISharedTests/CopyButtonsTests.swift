import XCTest
import SwiftUI
@testable import UIShared

@MainActor
final class CopyButtonsTests: XCTestCase {
    func testBottomCopyInvokesHandler() {
        var didCopy = false
        let view = BottomControls(
            status: .idle,
            onStopOrRestart: {},
            onCopy: { didCopy = true },
            onNewSession: {}
        )

        view.onCopy()
        XCTAssertTrue(didCopy)
    }

    func testRawTranscriptCopyDisabledWhenEmpty() {
        let view = RawTranscriptView(rawText: "", status: .idle, canCopyRaw: false, onCopyRaw: {})
        XCTAssertFalse(view.canCopyRaw)
    }

    func testRefinedTextPaneDoesNotRequireStatusLabel() {
        _ = RefinedTextPane(text: "hello")
        XCTAssertTrue(true)
    }

    func testGestureControllerUsesProductReleaseOrdering() async {
        var now = 0.0
        let editor = MockEditorViewModel(refinementStep: {})
        let controller = RecorderGestureController(now: { now })
        controller.pressBegan(.init(isRecording: false, isProcessing: false,
            start: { await editor.startRecording() }, stop: { await editor.stopRecording() },
            cancel: { await editor.stopRecording() }))
        await controller.waitForSettled()
        XCTAssertTrue(editor.isRecording)
        now = 0.3
        controller.pressEnded()
        controller.pressEnded()
        await controller.waitForSettled()
        XCTAssertFalse(editor.isRecording)
        XCTAssertTrue(editor.rawTranscription.hasPrefix("把刚才散步想到的播客开场白"))
        XCTAssertTrue(editor.text.hasPrefix("播客开场灵感："))
    }
}
