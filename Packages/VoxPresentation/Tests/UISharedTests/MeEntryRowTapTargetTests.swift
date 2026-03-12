import XCTest
@testable import UIShared

@MainActor
final class MeEntryRowTapTargetTests: XCTestCase {
    func testMeEntryRowUsesContentShapeForFullWidthHitTesting() {
        let bodyType = String(reflecting: type(of: MeEntryRow().body))

        XCTAssertTrue(
            bodyType.contains("ContentShapeModifier"),
            "MeEntryRow 应该使用 contentShape 扩展按钮命中区域，确保中间空白区可点击"
        )
    }
}
