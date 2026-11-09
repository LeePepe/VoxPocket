import XCTest
@testable import WidgetUI

final class WidgetUITests: XCTestCase {
    @MainActor
    func test_quick_record_widget_kind_constant() {
        let widget = QuickRecordWidget()
        XCTAssertEqual(widget.kind, "com.tianpli.VoxPocket.QuickRecord")
    }

    #if os(iOS)
    @MainActor
    func test_background_audio_recording_intents_do_not_open_app() {
        XCTAssertFalse(ToggleQuickCaptureIntent.openAppWhenRun)
        XCTAssertFalse(FinishCaptureIntent.openAppWhenRun)
    }

    @MainActor
    func test_background_audio_recording_intents_invoke_configured_perform_handlers() async throws {
        defer {
            ToggleQuickCaptureIntent.performHandler = nil
            FinishCaptureIntent.performHandler = nil
        }

        var toggleInvoked = false
        var finishInvoked = false
        ToggleQuickCaptureIntent.performHandler = { @MainActor in
            toggleInvoked = true
        }
        FinishCaptureIntent.performHandler = { @MainActor in
            finishInvoked = true
        }

        _ = try await ToggleQuickCaptureIntent().perform()
        _ = try await FinishCaptureIntent().perform()

        XCTAssertTrue(toggleInvoked)
        XCTAssertTrue(finishInvoked)
    }
    #endif
}
