import Foundation
import Synchronization
import XCTest
import LokiKit
@testable import LLMKit

final class StageProviderSnapshotTests: XCTestCase {
    func testAnalysisEntityAndTagContentNeverEntersLogs() async throws {
        let logger = FakeStageLogger()
        let provider = FakeStageProvider(type: .appleIntelligence)
        let service = DefaultLLMService(providers: [.appleIntelligence: provider], logger: logger)
        _ = try await service.refine(.init(text: "PRIVATE_INPUT_SENTINEL"))
        XCTAssertFalse(logger.messages.withLock { $0.contains { $0.contains("PRIVATE_") } })
    }

    func testProviderChangeDuringAnalysisDoesNotChangeInFlightRefinement() async throws {
        let gate = FakeAnalysisGate()
        let apple = FakeStageProvider(type: .appleIntelligence, gate: gate)
        let azure = FakeStageProvider(type: .azureFoundry)
        let service = DefaultLLMService(providers: [.appleIntelligence: apple, .azureFoundry: azure])
        let operation = Task {
            let stream = try await service.refineStreaming(.init(text: "synthetic input"))
            var result = ""
            for try await chunk in stream { result += chunk }
            return result
        }
        await gate.entered()
        try service.setProvider(.init(providerType: .azureFoundry, modelIdentifier: "fixture"))
        await gate.release()
        let result = try await operation.value
        XCTAssertEqual(result, "appleIntelligence")
        service.setSkipContentAnalysis(true)
        let next = try await service.refine(.init(text: "synthetic input"))
        XCTAssertEqual(next.refinedText, "azureFoundry")
    }

    func testIntentAndToneUseIndependentlySelectedProviders() async throws {
        let apple = FakeStageProvider(type: .appleIntelligence)
        let azure = FakeStageProvider(type: .azureFoundry)
        let service = DefaultLLMService(providers: [.appleIntelligence: apple, .azureFoundry: azure])
        try service.setProvider(.init(providerType: .azureFoundry, modelIdentifier: "fixture", options: [
            "analysis.intent.provider": "appleIntelligence", "analysis.tone.provider": "azureFoundry"
        ]))
        _ = try await service.refine(.init(text: "synthetic input"))
        XCTAssertTrue(apple.steps.contains(.intent))
        XCTAssertFalse(apple.steps.contains(.tone))
        XCTAssertTrue(azure.steps.contains(.tone))
        XCTAssertFalse(azure.steps.contains(.intent))
    }
}

private final class FakeStageProvider: LLMProvider, Sendable {
    let config: LLMProviderConfig
    private let captured = Mutex<Set<AnalysisStep>>([])
    private let gate: FakeAnalysisGate?
    var providerType: LLMProviderType { config.providerType }
    var isAvailable: Bool { true }
    var steps: Set<AnalysisStep> { captured.withLock { $0 } }
    init(type: LLMProviderType, gate: FakeAnalysisGate? = nil) {
        config = .init(providerType: type, modelIdentifier: "fixture")
        self.gate = gate
    }
    func complete(prompt: String) async throws -> String { providerType.rawValue }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.yield(providerType.rawValue); $0.finish() }
    }
    func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis {
        captured.withLock { $0.formUnion(steps) }
        await gate?.waitOnce()
        return PartialAnalysis(entities: ["PRIVATE_ENTITY_SENTINEL"], tags: ["PRIVATE_TAG_SENTINEL"])
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

private final class FakeStageLogger: LokiKit.Logger, Sendable {
    let messages = Mutex<[String]>([])
    private let level = Mutex<LogLevel>(.debug)
    var minimumLevel: LogLevel {
        get { level.withLock { $0 } }
        set { level.withLock { $0 = newValue } }
    }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, file: String, function: String, line: Int) {
        let text = message()
        messages.withLock { $0.append(text) }
    }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, context: [String: Any], file: String, function: String, line: Int) {
        let text = message() + String(describing: context)
        messages.withLock { $0.append(text) }
    }
}

private actor FakeAnalysisGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func waitOnce() async {
        if released { return }
        await withCheckedContinuation { continuation in
            waiting = continuation
            observers.forEach { $0.resume() }; observers.removeAll()
        }
    }
    func entered() async {
        if waiting != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { released = true; waiting?.resume(); waiting = nil }
}
