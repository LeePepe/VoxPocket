import Foundation
import Testing
import VoxCore
import VoxLLM
import VoxRefine
import VoxSpeech
@testable import VoxWorkflow

@Test func testEntryPointsSpeechAndRefine() async throws {
    let calls = WorkflowCalls()
    let runtime = WorkflowRuntime(configuration: workflowConfiguration(calls: calls))
    let speech = try await runtime.execute(Preset.appleSpeech.speech)
    #expect(speech.contains { if case .final(let result) = $0 { result.text == "speech.apple" } else { false } })
    let request = RefinementRequest(text: "synthetic input", customPrompt: "custom instruction", options: ["example": "kept"],
        transcriptionMetadata: TranscriptionMetadata(type: .final, confidence: 0.8, locale: Locale(identifier: "en")))
    let response = try await runtime.refine(request, preset: .appleSpeech)
    #expect(response.originalText == request.text)
    #expect(response.refinedText == "refined")
    #expect(response.missingAnalysisSteps.isEmpty)
    #expect(response.intentAnalysis.entities == ["entity"])
    #expect(response.intentAnalysis.tags == ["tag"])
    #expect(response.intentAnalysis.params.targetLanguage == "en")
    #expect(calls.values.contains("appleIntelligence:complete:custom instruction\n\n原文：synthetic input"))
    for step in AnalysisStep.allCases { #expect(calls.values.contains("appleIntelligence:\(step.rawValue):synthetic input:kept:en")) }
    let chunks = try await Array(runtime.refineStreaming(request, preset: .appleSpeech))
    #expect(chunks == ["re", "fined"])
}

@Test func testDSLJSONAndPresetDefinitionsAreEqualAndRoundTripLosslessly() throws {
    let dsl = WorkflowDefinition(entry: .speech) {
        NodeSpec(id: "capture", kind: .captureMicrophone)
        NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
        NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "apple", port: "text")])
    }
    let json = Data(#"{"version":1,"entry":"speech","nodes":[{"id":"capture","kind":"capture.microphone","inputs":[],"params":{},"onFailure":{"kind":"fail"}},{"id":"apple","kind":"speech.apple","inputs":[{"nodeID":"capture","port":"audio"}],"params":{},"onFailure":{"kind":"fail"}},{"id":"output","kind":"output.text","inputs":[{"nodeID":"apple","port":"text"}],"params":{},"onFailure":{"kind":"fail"}}]}"#.utf8)
    let decoded = try JSONDecoder().decode(WorkflowDefinition.self, from: json)
    #expect(dsl == decoded)
    #expect(decoded == Preset.default.overriding(["speech": "appleSpeech"]).speech)
    #expect(try JSONDecoder().decode(WorkflowDefinition.self, from: JSONEncoder().encode(decoded)) == decoded)
}

@Test func testExportedPipelineUsesLatestProviderForRepeatedAnalysisKinds() throws {
    let original = Preset.appleSpeech
    let repeatedIntent = NodeSpec(id: "secondIntent", kind: .analyzeIntent,
        inputs: [PortRef(nodeID: "input", port: "text")],
        params: ["analysis.intent.provider": .string("azureFoundry")])
    let preset = Preset(id: "repeated.intent", speech: original.speech,
        refine: WorkflowDefinition(entry: .refine, nodes: original.refine.nodes + [repeatedIntent]))
    try preset.refine.validate()
    #expect(preset.refine.nodes.filter { $0.kind == .analyzeIntent }.count == 2)
    var expectedAnalysis = original.exportedPipeline().analysis
    expectedAnalysis["intent"] = "azureFoundry"
    #expect(preset.exportedPipeline().analysis == expectedAnalysis)
}

@Test func testPreExecutionValidationRejectsInvalidGraphsWithoutLeakingContent() {
    let registry = NodeRegistry()
    let cases: [(WorkflowDefinition, WorkflowValidationError.Code)] = [
        (.init(entry: .speech, nodes: [.init(id: "bad", kind: "user-transcript-canary")]), .unknownNodeKind),
        (.init(entry: .speech, nodes: [.init(id: "same", kind: .captureMicrophone), .init(id: "same", kind: .captureMicrophone)]), .duplicateNodeID),
        (.init(entry: .speech, nodes: [.init(id: "speech", kind: .speechApple, inputs: [.init(nodeID: "canary-transcript", port: "audio")])]), .danglingReference),
        (.init(entry: .speech, nodes: [.init(id: "capture", kind: .captureMicrophone),
            .init(id: "speech", kind: .speechApple, inputs: [.init(nodeID: "capture", port: "does-not-exist")])]), .portTypeMismatch),
        (.init(entry: .speech, nodes: [.init(id: "capture", kind: .captureMicrophone),
            .init(id: "output", kind: .outputText, inputs: [.init(nodeID: "capture", port: "audio")])]), .portTypeMismatch),
        (.init(entry: .refine, nodes: [.init(id: "capture", kind: .captureMicrophone)]), .entryMismatch),
        (.init(entry: .speech, nodes: [.init(id: "left", kind: .outputText, inputs: [.init(nodeID: "right", port: "text")]),
            .init(id: "right", kind: .outputText, inputs: [.init(nodeID: "left", port: "text")])]), .cycleDetected)
    ]
    for (definition, expected) in cases {
        do { try definition.validate(using: registry); Issue.record("expected \(expected)") }
        catch let error as WorkflowValidationError {
            #expect(error.code == expected)
            #expect(!(error.errorDescription ?? "").contains("canary-transcript"))
        } catch { Issue.record("unexpected error") }
    }
    registry.register(NodeSignature(kind: "test.named", allowedEntries: [.speech], outputType: .text,
        outputPorts: ["audio": .text]), handler: EchoHandler())
    let mismatched = WorkflowDefinition(entry: .speech, nodes: [.init(id: "source", kind: "test.named"),
        .init(id: "speech", kind: .speechApple, inputs: [.init(nodeID: "source", port: "audio")])])
    #expect(throws: WorkflowValidationError(code: .portTypeMismatch, nodeID: "speech")) { try mismatched.validate(using: registry) }
}

@Test func testStageModelSettingsOverridingMatchesBaselinePipelineAndTraces() async throws {
    var count = 0
    for speech in ["appleSpeech", "batch", "realtime", "hybridAzure", "localWhisperKit", "hybridLocalWhisper"] {
        for routing in ["apple", "azure", "mixed", "inverseMixed"] {
            for skip in [false, true] {
                count += 1
                let intent = ["azure", "inverseMixed"].contains(routing) ? "azureFoundry" : "appleIntelligence"
                let tone = ["apple", "inverseMixed"].contains(routing) ? "appleIntelligence" : "azureFoundry"
                for refinement in ["appleIntelligence", "azureFoundry"] {
                    let options = ["speech": speech, "analysis.intent": intent, "analysis.entities": intent,
                        "analysis.tags": intent, "analysis.params": intent, "analysis.tone": tone,
                        "analysis.skip": String(skip), "refine.provider": refinement]
                    let preset = Preset.default.overriding(options)
                    let snapshot = preset.exportedPipeline()
                    #expect(snapshot.refine == refinement)
                    #expect(snapshot.analysis == ["intent": skip ? "skipped" : intent, "entities": skip ? "skipped" : intent,
                        "tags": skip ? "skipped" : intent, "params": skip ? "skipped" : intent, "tone": skip ? "skipped" : tone])
                    try preset.speech.validate()
                    try preset.refine.validate()
                    let calls = WorkflowCalls()
                    let runtime = WorkflowRuntime(configuration: workflowConfiguration(calls: calls))
                    let response = try await runtime.refine(RefinementRequest(text: "matrix"), preset: preset)
                    #expect(response.missingAnalysisSteps == (skip ? Set(AnalysisStep.allCases) : []))
                    #expect(calls.values.filter { !$0.contains(":complete:") }.count == (skip ? 0 : 5))
                    for step in AnalysisStep.allCases where !skip {
                        #expect(calls.values.contains("\(step == .tone ? tone : intent):\(step.rawValue):matrix::"))
                    }
                    let speechEvents = try await runtime.execute(preset.speech)
                    let speechText: String
                    switch speech {
                    case "appleSpeech": speechText = "speech.apple"
                    case "batch": speechText = "speech.azure.batch"
                    case "localWhisperKit": speechText = "speech.whisperkit.local"
                    default: speechText = "merged"
                    }
                    #expect(speechEvents.contains { if case .final(let value) = $0 { value.text == speechText } else { false } })
                    for missing in ["none", "batch", "realtime", "text"] {
                        let failure = preset.exportedPipeline(batchConfigured: missing != "batch", realtimeConfigured: missing != "realtime", azureTextConfigured: missing != "text").configFailure
                        let expected: String
                        if missing == "text", refinement == "azureFoundry" { expected = "textModelUnavailable" }
                        else if missing == "batch", preset.speech.nodes.contains(where: { $0.kind == .speechAzureBatch }) { expected = "batch" }
                        else if missing == "realtime", preset.speech.nodes.contains(where: { $0.kind == .speechAzureRealtime }) { expected = "realtime" }
                        else { expected = "none" }
                        #expect(failure == expected)
                    }
                }
            }
        }
    }
    #expect(count == 48)
}

@Test func testEveryAnalysisStepCanSelectItsProviderIndependently() async throws {
    let steps = AnalysisStep.allCases
    for mask in 0..<(1 << steps.count) {
        var overrides: [String: String] = [:]
        for (index, step) in steps.enumerated() {
            overrides["analysis.\(step.rawValue)"] = mask & (1 << index) == 0 ? "appleIntelligence" : "azureFoundry"
        }
        let calls = WorkflowCalls()
        let preset = Preset.appleSpeech.overriding(overrides)
        let response = try await WorkflowRuntime(configuration: workflowConfiguration(calls: calls)).refine(RefinementRequest(text: "independent"), preset: preset)
        #expect(response.missingAnalysisSteps.isEmpty)
        for step in steps {
            let provider = try #require(overrides["analysis.\(step.rawValue)"])
            #expect(preset.exportedPipeline().analysis[step.rawValue] == provider)
            #expect(calls.values.contains("\(provider):\(step.rawValue):independent::"))
        }
    }
}

@Test func testFailurePoliciesFailFallbackAndDefaultReproduceEB2EB3EB8() async throws {
    for failing in [false, true] {
        let calls = WorkflowCalls()
        let configured = workflowConfiguration(calls: calls, realtimeFails: failing)
        var factories = configured.speechFactories
        if !failing { factories.removeValue(forKey: .speechAzureBatch) }
        let configuration = WorkflowExecutionConfiguration(providers: configured.providers, merger: configured.merger,
            speechFactories: factories)
        let events = try await WorkflowRuntime(configuration: configuration).execute(Preset.hybridAzure.speech)
        #expect(calls.values.filter { $0 == "speech.azure.batch" }.count == (failing ? 1 : 0))
        let batchEvents = events.filter {
            switch $0 {
            case .nodeStarted(let label), .nodeFinished(let label), .nodeFailed(let label, _): label == .node("speech.azure.batch")
            default: false
            }
        }
        #expect(batchEvents == (failing ? [.nodeStarted(label: .node("speech.azure.batch")), .nodeFinished(label: .node("speech.azure.batch"))] : []))
        #expect(calls.values.filter { $0 == "speech.azure.realtime" }.count == 1)
        #expect(calls.values.contains("merge:speech.apple:\(failing ? "speech.azure.batch" : "speech.azure.realtime")"))
        #expect(events.contains { if case .final(let value) = $0 { value.text == "merged" } else { false } })
        #expect(events.contains(.nodeFailed(label: .node("speech.azure.realtime"), reason: .reason("node_failure"))) == failing)
    }
    let calls = WorkflowCalls()
    let events = try await WorkflowRuntime(configuration: workflowConfiguration(calls: calls, mergeFails: true)).execute(Preset.hybridAzure.speech)
    #expect(events.contains { if case .final(let value) = $0 { value.text == "speech.azure.realtime" } else { false } })
    #expect(calls.values.filter { $0.hasPrefix("merge:") }.count == 1)
    let response = try await WorkflowRuntime(configuration: workflowConfiguration(calls: WorkflowCalls(), failedSteps: [.tone])).refine(RefinementRequest(text: "input"))
    #expect(response.missingAnalysisSteps == [.tone])
    #expect(response.toneAnalysis == ToneAnalysis())
    #expect(response.intentAnalysis.intent == .polish)
    let registry = NodeRegistry()
    registry.register(NodeSignature(kind: "test.failure", allowedEntries: [.speech], outputType: .text), handler: FailingHandler())
    registry.register(NodeSignature(kind: "test.echo", allowedEntries: [.speech], inputTypes: [.text], outputType: .text), handler: RecordingHandler(calls: calls))
    let defaulted = WorkflowDefinition(entry: .speech, nodes: [.init(id: "failure", kind: "test.failure", onFailure: .defaultValue(.string("safe"))),
        .init(id: "result", kind: "test.echo", inputs: [.init(nodeID: "failure", port: "text")])])
    _ = try await WorkflowRuntime(registry: registry).execute(defaulted)
    #expect(calls.values.contains("safe"))
    var observed: [WorkflowEvent] = []
    do {
        for try await event in WorkflowRuntime(registry: registry).events(for: .init(entry: .speech, nodes: [.init(id: "fail", kind: "test.failure")])) { observed.append(event) }
        Issue.record("expected failure")
    } catch { #expect(error is WorkflowRuntimeError) }
    #expect(observed.count == 2)
    #expect(observed.contains { if case .nodeStarted = $0 { true } else { false } })
    #expect(observed.contains { if case .nodeFailed = $0 { true } else { false } })
}

@Test func testFallbackUsesItsOwnInputsAndCachesRecoveredOutput() async throws {
    let calls = WorkflowCalls()
    let registry = NodeRegistry()
    registry.register(NodeSignature(kind: "test.root", allowedEntries: [.speech], outputType: .text), handler: EchoHandler())
    registry.register(NodeSignature(kind: "test.failure", allowedEntries: [.speech], inputTypes: [.text], outputType: .text), handler: FailingHandler())
    registry.register(NodeSignature(kind: "test.record", allowedEntries: [.speech], inputTypes: [.text], outputType: .text), handler: RecordingHandler(calls: calls))
    let definition = WorkflowDefinition(entry: .speech, nodes: [
        .init(id: "primaryInput", kind: "test.root", params: ["value": .string("primary")]),
        .init(id: "fallbackInput", kind: "test.root", params: ["value": .string("fallback")]),
        .init(id: "recovery", kind: "test.record", inputs: [.init(nodeID: "fallbackInput", port: "text")]),
        .init(id: "primary", kind: "test.failure", inputs: [.init(nodeID: "primaryInput", port: "text")], onFailure: .fallback(nodeID: "recovery")),
        .init(id: "output", kind: "test.record", inputs: [.init(nodeID: "primary", port: "text")])])
    _ = try await WorkflowRuntime(registry: registry).execute(definition)
    #expect(calls.values == ["fallback", "fallback"])
}

private struct EchoHandler: WorkflowNodeHandler {
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue { .json(context.node.params["value"] ?? .string("root")) }
}
private struct RecordingHandler: WorkflowNodeHandler {
    let calls: WorkflowCalls
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        let value = context.inputs.first ?? .none
        calls.append(value.jsonValue.stringValue ?? "missing")
        return value
    }
}
private struct FailingHandler: WorkflowNodeHandler {
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue { throw WorkflowProbeError.failed }
}

@Test func testAllBuiltinPresetsAndProviderCombinations() throws {
    for preset in [Preset.hybridAzure, Preset.appleSpeech] { try preset.speech.validate(); try preset.refine.validate() }
    #expect(Preset.default.id == "hybrid.azure")
}
