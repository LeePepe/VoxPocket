import Foundation
import XCTest
@testable import TranscriptionKit

final class WhisperKitConfigTests: XCTestCase {
    func testDefaultModelIsLargeV3Turbo() {
        let config = LocalWhisperKitConfig.default
        XCTAssertEqual(config.model, "openai/whisper-large-v3-turbo")
    }

    func testLocaleMapsToChineseLanguageHint() {
        XCTAssertEqual(
            LocalWhisperKitConfig.default.languageHint(for: Locale(identifier: "zh-Hans")),
            "zh"
        )
    }
}
