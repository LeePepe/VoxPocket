import XCTest
@testable import WidgetUI

final class WidgetUITests: XCTestCase {
    @MainActor
    func test_quick_record_widget_kind_constant() {
        let widget = QuickRecordWidget()
        XCTAssertEqual(widget.kind, "com.tianpli.VoxPocket.QuickRecord")
    }
}
