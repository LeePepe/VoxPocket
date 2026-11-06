import VoxCore
import VoxLLM
import VoxRefine
import VoxWorkflow
import Foundation
import Synchronization
import XCTest

final class LLMGoldenTraceTests: XCTestCase {
    func testWorkflowPresetRefineParity() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden_a_llm", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try GoldenFixtureCodec.decode(Data(contentsOf: url))
        let traces = try XCTUnwrap(fixture["traces"] as? [[String: Any]])
        for expected in traces where expected["mode"] as? String != "merge" {
            let routing = try XCTUnwrap(expected["scenario"] as? String)
            let outcome = try XCTUnwrap(expected["outcome"] as? String)
            let calls = GoldenProviderCalls()
            let failed: Set<AnalysisStep> = outcome == "singleStepFailure" ? [.tone] : []
            var providers: [LLMProviderType: any LLMProvider] = [
                .appleIntelligence: GoldenProvider(type: .appleIntelligence, calls: calls, failedSteps: failed),
                .azureFoundry: GoldenProvider(type: .azureFoundry, calls: calls, failedSteps: failed)]
            let missing: LLMProviderType = routing == "allAzure" ? .azureFoundry : .appleIntelligence
            if outcome == "providerMissing" { providers.removeValue(forKey: missing) }
            let refine = outcome == "providerMissing" && missing == .azureFoundry ? "appleIntelligence" : "azureFoundry"
            var overrides = options(routing).reduce(into: [String: String]()) { result, item in
                result[String(item.key.dropLast(".provider".count))] = item.value
            }
            overrides["analysis.skip"] = String(routing == "skip")
            overrides["refine.provider"] = refine
            let preset = Preset.default.overriding(overrides)
            let logger = GoldenLogger()
            let runtime = WorkflowRuntime(configuration: WorkflowExecutionConfiguration(providers: providers, logger: logger))
            let request = RefinementRequest(text: "synthetic input", customPrompt: "Keep the synthetic meaning.")
            if expected["mode"] as? String == "refine" {
                let response = try await runtime.refine(request, preset: preset)
                XCTAssertEqual(responseTrace(response) as NSDictionary, try XCTUnwrap(expected["response"] as? NSDictionary))
            } else {
                let chunks = try await Array(runtime.refineStreaming(request, preset: preset))
                XCTAssertEqual(chunks, expected["chunks"] as? [String])
                XCTAssertEqual(chunks.joined(), expected["refinedText"] as? String)
            }
            XCTAssertEqual(normalizedStepCalls(calls.values.map(\.json)), normalizedStepCalls(try XCTUnwrap(expected["calls"] as? [[String: Any]])))
            XCTAssertEqual(logger.messages, expected["logs"] as? [String])
            XCTAssertEqual(logger.contextKeys, expected["logContextKeys"] as? [[String]])
            let completions = calls.values.filter { $0.method != "analyze" }
            XCTAssertEqual(completions.count, 1)
            XCTAssertEqual(completions.first?.provider, refine)
            if let completion = calls.values.firstIndex(where: { $0.method != "analyze" }) {
                XCTAssertTrue(calls.values[completion...].allSatisfy { $0.method != "analyze" })
            }
        }
        for expected in traces where expected["mode"] as? String == "merge" { try await workflowMergerParity(expected) }
    }

    private func normalizedStepCalls(_ calls: [[String: Any]]) -> [String] {
        calls.flatMap { call -> [String] in
            let steps = call["steps"] as? [String] ?? []
            let prefix = "\(call["provider"] ?? "")|\(call["method"] ?? "")|\(call["input"] ?? "")|"
            return steps.isEmpty ? [prefix] : steps.map { prefix + $0 }
        }.sorted()
    }

    private func workflowMergerParity(_ expected: [String: Any]) async throws {
        let scenario = try XCTUnwrap(expected["scenario"] as? String)
        let calls = GoldenProviderCalls()
        let provider = GoldenProvider(type: .azureFoundry, calls: calls,
            output: scenario == "outputTooLong" ? String(repeating: "x", count: 40) : "merged",
            throwsCompletion: scenario == "providerThrows")
        let registry = NodeRegistry()
        registry.register(NodeSignature(kind: "golden.input", allowedEntries: [.speech], outputType: .text), handler: GoldenInputHandler())
        let definition = WorkflowDefinition(entry: .speech, nodes: [
            NodeSpec(id: "apple", kind: "golden.input", params: ["text": .string(try XCTUnwrap(expected["apple"] as? String))]),
            NodeSpec(id: "cloud", kind: "golden.input", params: ["text": .string("whisper")]),
            NodeSpec(id: "merge", kind: .mergeLLM, inputs: [.init(nodeID: "apple", port: "text"), .init(nodeID: "cloud", port: "text")]),
            NodeSpec(id: "output", kind: .outputText, inputs: [.init(nodeID: "merge", port: "text")])])
        let events = try await WorkflowRuntime(registry: registry,
            configuration: WorkflowExecutionConfiguration(providers: [.azureFoundry: provider])).execute(definition)
        let final = events.compactMap { event -> String? in if case .final(let value) = event { value.text } else { nil } }
        XCTAssertEqual(final, [try XCTUnwrap(expected["output"] as? String)])
        XCTAssertEqual(normalizedStepCalls(calls.values.map(\.json)), normalizedStepCalls(try XCTUnwrap(expected["calls"] as? [[String: Any]])))
    }

    func testAnalysisAndMergerGolden() async throws {
        var traces: [[String: Any]] = []
        for routing in ["skip", "allApple", "allAzure", "intentApple_toneAzure", "intentAzure_toneApple"] {
            for outcome in ["success", "singleStepFailure", "providerMissing"] {
                for mode in ["refine", "refineStreaming"] {
                    traces.append(try await analysisTrace(routing: routing, outcome: outcome, mode: mode))
                }
            }
        }
        for scenario in ["success", "providerThrows", "outputTooLong", "identicalInputs", "emptyAppleText"] {
            traces.append(try await mergerTrace(scenario))
        }
        XCTAssertEqual(traces.count, 35)
        try assertGolden(["schema": "golden-trace/v1", "kind": "llm", "traces": traces], name: "golden_a_llm")
    }

    private func analysisTrace(routing: String, outcome: String, mode: String) async throws -> [String: Any] {
        let calls = GoldenProviderCalls()
        let failedSteps: Set<AnalysisStep> = outcome == "singleStepFailure" ? [.tone] : []
        let apple = GoldenProvider(type: .appleIntelligence, calls: calls, failedSteps: failedSteps)
        let azure = GoldenProvider(type: .azureFoundry, calls: calls, failedSteps: failedSteps)
        var providers: [LLMProviderType: any LLMProvider] = [.appleIntelligence: apple, .azureFoundry: azure]
        let missing: LLMProviderType = routing == "allAzure" ? .azureFoundry : .appleIntelligence
        if outcome == "providerMissing" { providers.removeValue(forKey: missing) }
        let refine: LLMProviderType = outcome == "providerMissing" && missing == .azureFoundry ? .appleIntelligence : .azureFoundry
        let logger = GoldenLogger()
        let service = DefaultLLMService(providers: providers, logger: logger)
        try service.setProvider(.init(providerType: refine, modelIdentifier: "golden", options: options(routing)))
        service.setSkipContentAnalysis(routing == "skip")
        let request = RefinementRequest(text: "synthetic input", customPrompt: "Keep the synthetic meaning.")
        var trace: [String: Any] = ["scenario": routing, "outcome": outcome, "mode": mode,
                                    "routing": service.resolvedAnalysisRouting.reduce(into: [String: String]()) {
                                        $0[$1.key.rawValue] = $1.value.rawValue
                                    }]
        if mode == "refine" {
            let response = try await service.refine(request)
            trace["response"] = responseTrace(response)
            if routing != "skip" && outcome == "success" { XCTAssertTrue(response.missingAnalysisSteps.isEmpty) }
            if routing != "skip" && outcome == "singleStepFailure" { XCTAssertEqual(response.missingAnalysisSteps, Set([AnalysisStep.tone])) }
        } else {
            var chunks: [String] = []
            for try await chunk in try await service.refineStreaming(request) { chunks.append(chunk) }
            trace["chunks"] = chunks
            trace["refinedText"] = chunks.joined()
        }
        assertIntraProviderOrder(calls.values)
        trace["calls"] = calls.normalized.map(\.json)
        trace["logs"] = logger.messages
        trace["logContextKeys"] = logger.contextKeys
        trace["telemetry"] = [String]()
        return trace
    }

    private func options(_ routing: String) -> [String: String] {
        let intent: LLMProviderType = ["allApple", "intentApple_toneAzure"].contains(routing) ? .appleIntelligence : .azureFoundry
        let tone: LLMProviderType = ["allApple", "intentAzure_toneApple"].contains(routing) ? .appleIntelligence : .azureFoundry
        return Dictionary(uniqueKeysWithValues: AnalysisStep.allCases.map { step in
            ("analysis.\(step.rawValue).provider", (step == .tone ? tone : intent).rawValue)
        })
    }

    private func responseTrace(_ response: RefinementResponse) -> [String: Any] {
        ["originalText": response.originalText, "refinedText": response.refinedText,
         "missingAnalysisSteps": response.missingAnalysisSteps.map(\.rawValue).sorted(),
         "intentAnalysis": ["intent": response.intentAnalysis.intent.rawValue,
                            "confidence": response.intentAnalysis.confidence,
                            "entities": response.intentAnalysis.entities, "tags": response.intentAnalysis.tags,
                            "targetLanguage": response.intentAnalysis.params.targetLanguage as Any? ?? NSNull()],
         "toneAnalysis": ["tone": response.toneAnalysis.tone.rawValue, "confidence": response.toneAnalysis.confidence],
         "tokenUsage": response.tokenUsage.map { ["promptTokens": $0.promptTokens, "completionTokens": $0.completionTokens] } as Any? ?? NSNull()]
    }

    private func assertIntraProviderOrder(_ calls: [GoldenProviderCall]) {
        for provider in [LLMProviderType.appleIntelligence, .azureFoundry] {
            let steps = calls.filter { $0.provider == provider.rawValue && $0.method == "analyze" }.map(\.steps)
            if let tone = steps.firstIndex(of: ["tone"]), let intent = steps.firstIndex(where: { $0.contains("intent") }) {
                XCTAssertLessThan(intent, tone)
            }
        }
        if let completion = calls.firstIndex(where: { $0.method != "analyze" }) {
            XCTAssertTrue(calls[completion...].allSatisfy { $0.method != "analyze" })
        }
    }

    private func mergerTrace(_ scenario: String) async throws -> [String: Any] {
        let calls = GoldenProviderCalls()
        let logger = GoldenLogger()
        let provider = GoldenProvider(type: .azureFoundry, calls: calls,
                                      output: scenario == "outputTooLong" ? String(repeating: "x", count: 40) : "merged",
                                      throwsCompletion: scenario == "providerThrows")
        let service = DefaultLLMService(providers: [.azureFoundry: provider], logger: logger)
        try service.setProvider(.init(providerType: .azureFoundry, modelIdentifier: "golden"))
        let apple = scenario == "emptyAppleText" ? "" : scenario == "identicalInputs" ? "whisper" : "apple"
        let output = await mergedTranscription(appleSpeech: apple, whisper: "whisper",
                                              merger: LLMTranscriptionMerger(llmService: service, logger: logger))
        XCTAssertEqual(output, scenario == "success" ? "merged" : "whisper")
        XCTAssertEqual(calls.values.count, ["identicalInputs", "emptyAppleText"].contains(scenario) ? 0 : 1)
        return ["scenario": scenario, "mode": "merge", "apple": apple, "whisper": "whisper", "output": output,
                "calls": calls.values.map(\.json), "logs": logger.messages, "logContextKeys": logger.contextKeys, "telemetry": [String]()]
    }
}

private struct GoldenInputHandler: WorkflowNodeHandler {
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        guard case .string(let text) = context.node.params["text"] else { throw WorkflowRuntimeError.nodeFailed }
        return .transcriptionResult(TranscriptionResult(text: text, type: .final))
    }
}

private struct GoldenProviderCall: Sendable {
    let provider: String
    let method: String
    let steps: [String]
    let input: String
    var json: [String: Any] { ["provider": provider, "method": method, "steps": steps, "input": input] }
}

private final class GoldenProviderCalls: Sendable {
    private let storage = Mutex<[GoldenProviderCall]>([])
    func append(_ call: GoldenProviderCall) { storage.withLock { $0.append(call) } }
    var values: [GoldenProviderCall] { storage.withLock { $0 } }
    var normalized: [GoldenProviderCall] {
        let calls = values
        let analysis = calls.filter { $0.method == "analyze" }
        return Set(analysis.map(\.provider)).sorted().flatMap { provider in
            analysis.filter { $0.provider == provider }
        } + calls.filter { $0.method != "analyze" }
    }
}

private final class GoldenProvider: LLMProvider, Sendable {
    let config: LLMProviderConfig
    let calls: GoldenProviderCalls
    let failedSteps: Set<AnalysisStep>
    let output: String
    let throwsCompletion: Bool
    var providerType: LLMProviderType { config.providerType }
    var isAvailable: Bool { true }
    init(type: LLMProviderType, calls: GoldenProviderCalls, failedSteps: Set<AnalysisStep> = [],
         output: String = "synthetic refined", throwsCompletion: Bool = false) {
        config = .init(providerType: type, modelIdentifier: "golden")
        self.calls = calls; self.failedSteps = failedSteps; self.output = output; self.throwsCompletion = throwsCompletion
    }
    private func record(_ method: String, input: String, steps: Set<AnalysisStep> = []) {
        calls.append(.init(provider: providerType.rawValue, method: method, steps: steps.map(\.rawValue).sorted(), input: input))
    }
    func complete(prompt: String) async throws -> String {
        record("complete", input: prompt)
        if throwsCompletion { throw NSError(domain: "GoldenProvider", code: 1) }
        return output
    }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        record("completeStreaming", input: prompt)
        if throwsCompletion { throw NSError(domain: "GoldenProvider", code: 1) }
        return AsyncThrowingStream { continuation in
            continuation.yield(String(output.prefix(4))); continuation.yield(String(output.dropFirst(4))); continuation.finish()
        }
    }
    func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis {
        record("analyze", input: request.text, steps: steps)
        if !failedSteps.isDisjoint(with: steps) { throw NSError(domain: "GoldenProvider", code: 2) }
        return PartialAnalysis(intent: steps.contains(.intent) ? .init(intent: .polish, confidence: 0.75) : nil,
                               tone: steps.contains(.tone) ? .init(tone: .formal, confidence: 0.5) : nil,
                               entities: steps.contains(.entities) ? ["example-entity"] : nil,
                               tags: steps.contains(.tags) ? ["example-tag"] : nil,
                               params: steps.contains(.params) ? .init(targetLanguage: "en") : nil)
    }
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        .init(originalText: request.text, refinedText: try await complete(prompt: request.text))
    }
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await completeStreaming(prompt: request.text)
    }
    func validate() async throws {}
    func cancel() {}
}
