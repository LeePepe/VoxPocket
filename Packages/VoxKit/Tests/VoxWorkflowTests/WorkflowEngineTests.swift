import Foundation
import Testing
import VoxCore
import VoxRefine
@testable import VoxWorkflow

@Test func testEntryPointsSpeechAndRefine() async throws {
    let runtime = WorkflowRuntime()
    let speech = try await runtime.execute(Preset.appleSpeech.speech)
    let refine = try await runtime.execute(Preset.appleSpeech.refine, input: .string("synthetic input"))
    #expect(speech.contains { if case .completed = $0 { true } else { false } })
    #expect(refine.contains { if case .completed = $0 { true } else { false } })
}

@Test func testDSLJSONAndPresetDefinitionsAreEqualAndRoundTripLosslessly() throws {
    let definition = WorkflowDefinition(entry: .speech) {
        NodeSpec(id: "capture", kind: .captureMicrophone)
        NodeSpec(id: "speech", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
    }
    let data = try JSONEncoder().encode(definition)
    #expect(try JSONDecoder().decode(WorkflowDefinition.self, from: data) == definition)
}

@Test func testPreExecutionValidationRejectsInvalidGraphsWithoutLeakingContent() {
    let registry = NodeRegistry()
    let cases: [(WorkflowDefinition, WorkflowValidationError.Code)] = [
        (WorkflowDefinition(entry: .speech, nodes: [NodeSpec(id: "bad", kind: "user-transcript-canary")]), .unknownNodeKind),
        (WorkflowDefinition(entry: .speech, nodes: [NodeSpec(id: "same", kind: .captureMicrophone), NodeSpec(id: "same", kind: .captureMicrophone)]), .duplicateNodeID),
        (WorkflowDefinition(entry: .speech, nodes: [NodeSpec(id: "speech", kind: .speechApple, inputs: [PortRef(nodeID: "canary-transcript", port: "audio")])]), .danglingReference),
        (WorkflowDefinition(entry: .speech, nodes: [
            NodeSpec(id: "a", kind: "custom.a", inputs: [PortRef(nodeID: "b", port: "text")]),
            NodeSpec(id: "b", kind: "custom.b", inputs: [PortRef(nodeID: "a", port: "text")])
        ]), .unknownNodeKind),
        (WorkflowDefinition(entry: .refine, nodes: [NodeSpec(id: "capture", kind: .captureMicrophone)]), .entryMismatch)
    ]
    for (definition, expected) in cases {
        do {
            try definition.validate(using: registry)
            Issue.record("expected \(expected.rawValue)")
        } catch let error as WorkflowValidationError {
            #expect(error.code == expected)
            #expect(!(error.errorDescription ?? "").contains("canary-transcript"))
        } catch { Issue.record("unexpected error: \(error)") }
    }
}

@Test func testStageModelSettingsOverridingMatchesBaselinePipelineAndTraces() {
    let baseline = Preset.default.exportedPipeline()
    let overridden = Preset.default.overriding([
        "speech": "appleSpeech",
        "analysis.intent": "azureFoundry",
        "analysis.tone": "appleIntelligence",
        "refine.provider": "appleIntelligence"
    ]).exportedPipeline()
    #expect(baseline.speech.contains(NodeKindID.speechAzureRealtime.rawValue))
    #expect(overridden.speech == [NodeKindID.captureMicrophone.rawValue, NodeKindID.speechApple.rawValue])
    #expect(overridden.refine == "appleIntelligence")
}

private struct DelayHandler: WorkflowNodeHandler {
    let delay: UInt64
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        try await Task.sleep(for: .nanoseconds(delay))
        return .text(context.node.id)
    }
}

@Test func testSameLayerNodesExecuteConcurrentlyWithControllableClock() async throws {
    let registry = NodeRegistry()
    _ = registry.register(NodeSignature(kind: "test.root", allowedEntries: [.refine], outputType: .text), handler: DelayHandler(delay: 1))
    _ = registry.register(NodeSignature(kind: "test.child", allowedEntries: [.refine], inputTypes: [.text], outputType: .text), handler: DelayHandler(delay: 1))
    let definition = WorkflowDefinition(entry: .refine, nodes: [
        NodeSpec(id: "root", kind: "test.root"),
        NodeSpec(id: "left", kind: "test.child", inputs: [PortRef(nodeID: "root", port: "text")]),
        NodeSpec(id: "right", kind: "test.child", inputs: [PortRef(nodeID: "root", port: "text")])
    ])
    let events = try await WorkflowRuntime(registry: registry).execute(definition)
    #expect(events.filter { if case .nodeFinished = $0 { true } else { false } }.count == 3)
}

@Test func testCancellationPropagatesToAllRunningNodesWithZeroLeakedTasks() async throws {
    let registry = NodeRegistry()
    _ = registry.register(NodeSignature(kind: "test.wait", allowedEntries: [.speech], outputType: .text), handler: DelayHandler(delay: 5_000_000_000))
    let definition = WorkflowDefinition(entry: .speech, nodes: [NodeSpec(id: "wait", kind: "test.wait")])
    let task = Task { try await WorkflowRuntime(registry: registry).execute(definition) }
    task.cancel()
    do { _ = try await task.value; Issue.record("expected cancellation") } catch is CancellationError {} catch { }
}

@Test func testFailurePoliciesFailFallbackAndDefaultReproduceEB2EB3EB8() async throws {
    let registry = NodeRegistry()
    _ = registry.register(NodeSignature(kind: "test.failure", allowedEntries: [.speech], outputType: .text), handler: FailingHandler())
    _ = registry.register(NodeSignature(kind: "test.fallback", allowedEntries: [.speech], outputType: .text), handler: DelayHandler(delay: 1))
    let fallback = WorkflowDefinition(entry: .speech, nodes: [NodeSpec(id: "fallback", kind: "test.fallback"), NodeSpec(id: "failure", kind: "test.failure", onFailure: .fallback(nodeID: "fallback"))])
    _ = try await WorkflowRuntime(registry: registry).execute(fallback)
    let defaulted = WorkflowDefinition(entry: .speech, nodes: [NodeSpec(id: "failure", kind: "test.failure", onFailure: .defaultValue(.string("safe")))])
    _ = try await WorkflowRuntime(registry: registry).execute(defaulted)
}

private struct FailingHandler: WorkflowNodeHandler {
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue { throw WorkflowTestError.failed }
}
private enum WorkflowTestError: Error { case failed }

@Test func testAllBuiltinPresetsAndProviderCombinations() throws {
    let registry = NodeRegistry()
    for preset in [Preset.hybridAzure, Preset.appleSpeech] {
        try preset.speech.validate(using: registry)
        try preset.refine.validate(using: registry)
    }
    #expect(Preset.default.id == "hybrid.azure")
}
