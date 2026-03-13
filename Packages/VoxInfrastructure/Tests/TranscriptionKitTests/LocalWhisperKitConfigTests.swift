import Foundation
import XCTest
@testable import TranscriptionKit

final class LocalWhisperKitConfigTests: XCTestCase {
    func testDefaultModelIsUnderOneGigabyteVariant() {
        let config = LocalWhisperKitConfig.default
        XCTAssertEqual(config.model, "openai_whisper-large-v3-v20240930_turbo_632MB")
    }

    func testLocaleMapsToChineseLanguageHint() {
        XCTAssertEqual(
            LocalWhisperKitConfig.default.languageHint(for: Locale(identifier: "zh-Hans")),
            "zh"
        )
    }
}
