import XCTest
@testable import VoxRefine

final class RefinementTests: XCTestCase {
    func testRefinementTypeIsAvailable() {
        XCTAssertFalse(RefinementType.allCases.isEmpty)
    }
}
