import XCTest
@testable import WidgetUI

final class WidgetUITests: XCTestCase {
    @MainActor
    func test_quick_record_widget_kind_constant() {
        let widget = QuickRecordWidget()
        XCTAssertEqual(widget.kind, "com.tianpli.VoxPocket.QuickRecord")
    }

    func test_vox_capture_island_phases_match_atmosphere_glass_hex_palette() {
        XCTAssertEqual(VoxCaptureIslandPhase.listening.primaryHex, "#52BDB8")
        XCTAssertEqual(VoxCaptureIslandPhase.transcribing.primaryHex, "#578FE6")
        XCTAssertEqual(VoxCaptureIslandPhase.refining.primaryHex, "#9480E6")
        XCTAssertEqual(VoxCaptureIslandPhase.completedReceipt.primaryHex, "#57BD99")
        XCTAssertEqual(VoxCaptureIslandPhase.todoFocusPinned.primaryHex, "#38BDF8")
        XCTAssertEqual(VoxCaptureIslandPhase.errorAlert.primaryHex, "#E67580")

        let subtask = VoxIslandSubtaskPayload(title: "这是一段超过二十八个字符的超长子步骤标题用于验证截断边界", isCompleted: true)
        XCTAssertLessThanOrEqual(subtask.title.count, 28)
        XCTAssertTrue(subtask.isCompleted)
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
