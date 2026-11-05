import XCTest

final class GoldenRoutingTests: XCTestCase {
    func testGoldenRoutingContractIsVersioned() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appendingPathComponent("scripts/tests/golden/golden_b_ios.json")
        let data = try Data(contentsOf: fixture)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schema"] as? String, "golden-trace/v1")
        XCTAssertTrue(object["traces"] is [Any])
    }
}
