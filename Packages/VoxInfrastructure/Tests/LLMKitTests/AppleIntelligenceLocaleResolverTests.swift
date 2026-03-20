import XCTest
@testable import LLMKit

final class AppleIntelligenceLocaleResolverTests: XCTestCase {
    func testResolveKeepsRequestedLocaleWhenSupportedByMinimalIdentifier() {
        let supportedLanguages = [
            Locale(identifier: "en-US").language,
            Locale(identifier: "zh").language
        ]
        let requested = Locale(identifier: "zh-Hans")

        let resolved = AppleIntelligenceLocaleResolver.resolve(
            requested,
            supportedLanguages: supportedLanguages
        )

        XCTAssertEqual(resolved.identifier, requested.identifier)
    }

    func testResolveFallsBackToSameLanguageWhenRegionVariantUnsupported() {
        let supportedLanguages = [
            Locale(identifier: "en-US").language,
            Locale(identifier: "zh").language
        ]
        let requested = Locale(identifier: "zh-US")

        let resolved = AppleIntelligenceLocaleResolver.resolve(
            requested,
            supportedLanguages: supportedLanguages
        )

        XCTAssertEqual(resolved.language.languageCode?.identifier, "zh")
        XCTAssertNotEqual(resolved.identifier, "en-US")
    }

    func testResolveFallsBackToEnglishWhenLanguageUnavailable() {
        let supportedLanguages = [
            Locale(identifier: "en-US").language,
            Locale(identifier: "ja").language
        ]
        let requested = Locale(identifier: "ar-EG")

        let resolved = AppleIntelligenceLocaleResolver.resolve(
            requested,
            supportedLanguages: supportedLanguages
        )

        XCTAssertEqual(resolved.identifier, "en-US")
    }

    func testResolvePrefersSameScriptForChinese() {
        let supportedLanguages = [
            Locale(identifier: "zh").language,
            Locale(identifier: "zh-TW").language,
            Locale(identifier: "en-US").language
        ]
        let requested = Locale(identifier: "zh-Hant-HK")

        let resolved = AppleIntelligenceLocaleResolver.resolve(
            requested,
            supportedLanguages: supportedLanguages
        )

        XCTAssertEqual(resolved.language.script?.identifier, "Hant")
    }
}
