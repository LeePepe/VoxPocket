import Foundation
import XCTest
import Synchronization
import LokiKit
@testable import LLMKit

final class LLMGoldenTraceTests: XCTestCase {
    func testAnalysisRoutingMatrixAndStreamingAreDeterministic() async throws {
        let apple = GoldenProvider(type: .appleIntelligence)
        let azure = GoldenProvider(type: .azureFoundry)
        let service = DefaultLLMService(providers: [.appleIntelligence: apple, .azureFoundry: azure])
        let cases: [[String: String]] = [
            [:],
            ["analysis.intent.provider": "appleIntelligence", "analysis.tone.provider": "azureFoundry"],
            ["analysis.intent.provider": "azureFoundry", "analysis.tone.provider": "appleIntelligence"]
        ]
        var traces: [[String: Any]] = []
        for options in cases {
            try service.setProvider(.init(providerType: .azureFoundry, modelIdentifier: "golden", options: options))
            _ = try await service.refine(.init(text: "synthetic input"))
            var stream = try await service.refineStreaming(.init(text: "synthetic input"))
            var output = ""
            for try await chunk in stream { output += chunk }
            traces.append(["routing": service.resolvedAnalysisRouting.mapValues(\.rawValue), "stream": output])
        }
        XCTAssertEqual(traces.count, 3)
        XCTAssertTrue(traces.allSatisfy { ($0["stream"] as? String) == "azureFoundry" })
    }

    func testMergerFallbackMatrix() async throws {
        let provider = GoldenProvider(type: .azureFoundry)
        let service = DefaultLLMService(providers: [.azureFoundry: provider])
        try service.setProvider(.init(providerType: .azureFoundry, modelIdentifier: "golden"))
        let merger = LLMTranscriptionMerger(llmService: service)
        let merged = try await merger.merge(appleSpeech: "apple", whisper: "whisper")
        let emptyApple = try await merger.merge(appleSpeech: "", whisper: "whisper")
        XCTAssertEqual(merged, "whisper")
        XCTAssertEqual(emptyApple, "whisper")
    }
}

private final class GoldenProvider: LLMProvider, Sendable {
    let config: LLMProviderConfig
    var providerType: LLMProviderType { config.providerType }
    var isAvailable: Bool { true }
    init(type: LLMProviderType) { config = .init(providerType: type, modelIdentifier: "golden") }
    func complete(prompt: String) async throws -> String { providerType.rawValue }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in continuation.yield(providerType.rawValue); continuation.finish() }
    }
    func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis {
        PartialAnalysis(entities: [], tags: [])
    }
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        .init(originalText: request.text, refinedText: providerType.rawValue)
    }
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await completeStreaming(prompt: request.text)
    }
    func validate() async throws {}
    func cancel() {}
}
