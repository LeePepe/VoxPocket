import Foundation
import XCTest
@testable import TranscriptionKit

final class WhisperKitConfigTests: XCTestCase {
    func testDefaultModelMatchesPlatform() {
        let config = LocalWhisperKitConfig.default
#if os(iOS)
        XCTAssertEqual(config.model, "openai/whisper-base")
#else
        XCTAssertEqual(config.model, "openai/whisper-large-v3-turbo")
#endif
    }

    func testLocaleMapsToChineseLanguageHint() {
        XCTAssertEqual(
            LocalWhisperKitConfig.default.languageHint(for: Locale(identifier: "zh-Hans")),
            "zh"
        )
    }

    func testOpenAIAliasResolvesToWhisperKitVariant() {
        let config = LocalWhisperKitConfig(model: "openai/whisper-large-v3-turbo", preloadOnStart: false)
        XCTAssertEqual(config.resolvedModelVariant, "openai_whisper-large-v3_turbo")
    }

    func testOpenAIBaseAliasResolvesToWhisperKitVariant() {
        let config = LocalWhisperKitConfig(model: "openai/whisper-base", preloadOnStart: false)
        XCTAssertEqual(config.resolvedModelVariant, "openai_whisper-base")
    }

    func testDistilAliasResolvesToWhisperKitVariant() {
        let config = LocalWhisperKitConfig(model: "distil-whisper/distil-large-v3", preloadOnStart: false)
        XCTAssertEqual(config.resolvedModelVariant, "distil-whisper_distil-large-v3")
    }
}
