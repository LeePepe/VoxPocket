import XCTest

final class GoldenRoutingTests: XCTestCase {
    func testGoldenRoutingRowsMatchFixture() throws {
        for resource in ["golden_b_ios", "golden_b_macos"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: "json"))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(object["schema"] as? String, "golden-trace/v1")
            let rows = try XCTUnwrap(object["traces"] as? [[String: Any]])
            XCTAssertFalse(rows.isEmpty)
            for row in rows {
                XCTAssertEqual(row["routing"] as? [String: String], [
                    "intent": "azureFoundry", "tone": "azureFoundry",
                    "entities": "azureFoundry", "tags": "azureFoundry", "params": "azureFoundry"
                ])
            }
        }
    }
}
