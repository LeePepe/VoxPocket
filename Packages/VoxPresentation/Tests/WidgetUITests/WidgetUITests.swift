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
    #endif
}
