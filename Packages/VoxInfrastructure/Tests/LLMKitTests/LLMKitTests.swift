import XCTest
import LLMKit

final class LLMKitTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
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
