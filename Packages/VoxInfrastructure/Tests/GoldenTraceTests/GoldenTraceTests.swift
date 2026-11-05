import XCTest
@testable import TranscriptionKit

final class GoldenTraceTests: XCTestCase {
    func testGoldenTraceFixturesArePresent() throws {
        let bundle = Bundle.module
        for name in ["golden_a_llm", "golden_c_speech"] {
            XCTAssertNotNil(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        }
    }
}
