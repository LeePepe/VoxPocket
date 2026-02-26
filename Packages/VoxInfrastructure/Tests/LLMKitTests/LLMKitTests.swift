import XCTest
import LLMKit
import CoreModels

final class LLMKitTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }

    func testAzureFoundryProviderTypeIsSupported() {
        XCTAssertNotNil(LLMProviderType(rawValue: "azureFoundry"))
    }

    func testProviderTypesAreAppleAndAzureFoundry() {
        XCTAssertEqual(Set(LLMProviderType.allCases), Set([.appleIntelligence, .azureFoundry]))
    }

    func testAzureFoundryProviderValidateRequiresEndpointAndAPIKey() async {
        let provider = AzureFoundryProvider(
            config: LLMProviderConfig(
                providerType: .azureFoundry,
                modelIdentifier: "gpt-4.1-mini"
            )
        )

        do {
            try await provider.validate()
            XCTFail("Expected validation to fail for missing endpoint/API key")
        } catch VoxError.llmProviderNotConfigured {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIntentAndToneAnalysis() async throws {
        let provider = AppleIntelligenceProvider()
        guard provider.isAvailable else {
            throw XCTSkip("Apple Intelligence 不可用，跳过 intent/tone 测试。")
        }

        let request = AnalysisRequest(text: "今天是周六不是周日")
        let partial = try await provider.analyze(request, steps: [.intent, .tone])

        XCTAssertNotNil(partial.intent)
        XCTAssertNotNil(partial.tone)
        if let confidence = partial.intent?.confidence {
            XCTAssertGreaterThanOrEqual(confidence, 0.0)
            XCTAssertLessThanOrEqual(confidence, 1.0)
        }
        if let confidence = partial.tone?.confidence {
            XCTAssertGreaterThanOrEqual(confidence, 0.0)
            XCTAssertLessThanOrEqual(confidence, 1.0)
        }
    }
}
