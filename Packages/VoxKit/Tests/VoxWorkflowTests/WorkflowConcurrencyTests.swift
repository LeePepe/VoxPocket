import Foundation
import Testing
import VoxCore
import VoxRefine
import VoxWorkflow

private actor WorkflowBarrier {
    var entered: [String] = []
    var active = 0
    var maximum = 0
    var cancelled = 0
    var gates: [String: CheckedContinuation<Void, Error>] = [:]
    var cancelledIDs = Set<String>()
    var releasedIDs = Set<String>()
    var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func enter(_ id: String) {
        entered.append(id); active += 1; maximum = max(maximum, active)
        let ready = observers.filter { entered.count >= $0.0 }
        observers.removeAll { entered.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
    func waitForEntries(_ count: Int) async {
        if entered.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func hold(_ id: String) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled || cancelledIDs.contains(id) { continuation.resume(throwing: CancellationError()) }
                else if releasedIDs.contains(id) { continuation.resume() }
                else { gates[id] = continuation }
            }
        } onCancel: { Task { await self.cancelGate(id) } }
    }
    func cancelGate(_ id: String) {
        cancelledIDs.insert(id)
        gates.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
    func release(_ id: String) { releasedIDs.insert(id); gates.removeValue(forKey: id)?.resume() }
    func leave(wasCancelled: Bool) { active -= 1; if wasCancelled { cancelled += 1 } }
}

private struct BarrierHandler: WorkflowNodeHandler {
    let barrier: WorkflowBarrier
    let analysis: Bool
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        let id = context.node.id + (context.workflowInput.jsonText ?? "")
        await barrier.enter(id)
        context.emit(.refinedChunk("first"))
        do {
            try await barrier.hold(id)
            try Task.checkCancellation()
            await barrier.leave(wasCancelled: false)
            if analysis { return .analysis(PartialAnalysis(intent: IntentAnalysis(), tone: ToneAnalysis())) }
            return .text("stable")
        } catch { await barrier.leave(wasCancelled: true); throw error }
    }
}

private extension WorkflowNodeValue {
    var jsonText: String? { if case .string(let value) = self { value } else { nil } }
}

@Test(.timeLimit(.minutes(1))) func testSameLayerNodesExecuteConcurrentlyWithControllableClock() async throws {
    var responses: [RefinementResponse] = []
    for serial in [false, true] {
        let barrier = WorkflowBarrier()
        let registry = NodeRegistry()
        for kind in [NodeKindID.analyzeIntent, .analyzeTone] {
            registry.register(NodeSignature(kind: kind, allowedEntries: [.refine], inputTypes: [.text], outputType: .analysis),
                handler: BarrierHandler(barrier: barrier, analysis: true))
        }
        let preset = Preset.appleSpeech
        let nodes = preset.refine.nodes.map { node in
            var params = node.params
            if serial, [.analyzeIntent, .analyzeTone].contains(node.kind) { params["concurrency.key"] = .string("analysis") }
            return NodeSpec(id: node.id, kind: node.kind, inputs: node.inputs, params: params, onFailure: node.onFailure,
                concurrency: serial && [.analyzeIntent, .analyzeTone].contains(node.kind) ? 1 : nil)
        }
        let runtime = WorkflowRuntime(registry: registry, configuration: workflowConfiguration(calls: WorkflowCalls()))
        let task = Task { try await runtime.execute(WorkflowDefinition(entry: .refine, nodes: nodes), input: .refinementRequest(RefinementRequest(text: "input"))) }
        await barrier.waitForEntries(serial ? 1 : 2)
        #expect(await barrier.active == (serial ? 1 : 2))
        for id in await barrier.entered { await barrier.release(id) }
        if serial {
            await barrier.waitForEntries(2)
            for id in await barrier.entered { await barrier.release(id) }
        }
        let events = try await task.value
        #expect(await barrier.maximum == (serial ? 1 : 2))
        #expect(await barrier.active == 0)
        if case .completed(let response?) = events.last { responses.append(response) }
    }
    #expect(responses.count == 2)
    #expect(responses[0].refinedText == responses[1].refinedText)
    #expect(responses[0].intentAnalysis == responses[1].intentAnalysis)
    #expect(responses[0].toneAnalysis == responses[1].toneAnalysis)
    #expect(responses[0].missingAnalysisSteps == responses[1].missingAnalysisSteps)
}

@Test(.timeLimit(.minutes(1))) func testNodeAndSignatureConcurrencyOneSerializeSameKind() async throws {
    for useDefault in [false, true] {
        let barrier = WorkflowBarrier()
        let registry = NodeRegistry(registerBuiltIns: false)
        registry.register(NodeSignature(kind: "test.wait", allowedEntries: [.speech], outputType: .text,
            defaultConcurrency: useDefault ? 1 : nil), handler: BarrierHandler(barrier: barrier, analysis: false))
        let definition = WorkflowDefinition(entry: .speech, nodes: ["left", "right"].map {
            NodeSpec(id: $0, kind: "test.wait", concurrency: useDefault ? nil : 1)
        })
        let task = Task { try await WorkflowRuntime(registry: registry).execute(definition) }
        await barrier.waitForEntries(1)
        await barrier.release(try #require(await barrier.entered.first))
        await barrier.waitForEntries(2)
        await barrier.release(try #require(await barrier.entered.last))
        _ = try await task.value
        #expect(await barrier.maximum == 1)
        #expect(await barrier.active == 0)
    }
}

@Test(.timeLimit(.minutes(1))) func testCancellationPropagatesToAllRunningNodesWithZeroLeakedTasks() async throws {
    for mode in ["runtime", "task", "stream"] {
        let barrier = WorkflowBarrier()
        let registry = NodeRegistry(registerBuiltIns: false)
        registry.register(NodeSignature(kind: "test.wait", allowedEntries: [.speech], outputType: .text),
            handler: BarrierHandler(barrier: barrier, analysis: false))
        let definition = WorkflowDefinition(entry: .speech, nodes: [NodeSpec(id: "left", kind: "test.wait"), NodeSpec(id: "right", kind: "test.wait")])
        let runtime = WorkflowRuntime(registry: registry)
        let first = Task { try await runtime.execute(definition, input: .string("A")) }
        await barrier.waitForEntries(2)
        if mode == "task" { first.cancel() }
        else { runtime.cancel() }
        let second = Task { try await runtime.execute(definition, input: .string("B")) }
        do { _ = try await first.value; Issue.record("expected cancellation") } catch { #expect(error is CancellationError) }
        #expect(await barrier.cancelled == 2)
        await barrier.waitForEntries(4)
        #expect(await barrier.active == 2)
        runtime.cancel()
        do { _ = try await second.value; Issue.record("expected cancellation") } catch { #expect(error is CancellationError) }
        #expect(await barrier.active == 0)
        #expect(await barrier.cancelled == 4)
        if mode == "stream" {
            let consumer = Task {
                do { for try await _ in runtime.events(for: definition, input: .string("C")) {} }
                catch { #expect(error is CancellationError) }
                #expect(await barrier.active == 0)
            }
            await barrier.waitForEntries(6)
            runtime.cancel()
            await consumer.value
            #expect(await barrier.cancelled == 6)
        }
    }
}

@Test(.timeLimit(.minutes(1))) func testEventsAreDeliveredBeforeHandlerCompletes() async throws {
    let barrier = WorkflowBarrier()
    let registry = NodeRegistry(registerBuiltIns: false)
    registry.register(NodeSignature(kind: "test.wait", allowedEntries: [.refine], outputType: .text),
        handler: BarrierHandler(barrier: barrier, analysis: false))
    var sawChunk = false
    for try await event in WorkflowRuntime(registry: registry).events(for: WorkflowDefinition(entry: .refine, nodes: [NodeSpec(id: "wait", kind: "test.wait")])) {
        if event == .refinedChunk("first") {
            #expect(await barrier.active == 1)
            sawChunk = true
            await barrier.release("wait")
        }
    }
    #expect(sawChunk)
    #expect(await barrier.active == 0)
}
