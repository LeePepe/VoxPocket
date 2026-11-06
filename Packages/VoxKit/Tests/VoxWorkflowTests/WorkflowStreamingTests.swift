import Foundation
import Testing
import VoxCore
import VoxLLM
import VoxRefine
import VoxWorkflow

private actor WorkflowChunkGate {
    var continuation: AsyncThrowingStream<String, Error>.Continuation?
    var finished = false
    func stream() -> AsyncThrowingStream<String, Error> {
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        continuation = pair.continuation
        pair.continuation.yield("first")
        return pair.stream
    }
    func finish() { finished = true; continuation?.yield("second"); continuation?.finish() }
}

private final class WorkflowStreamingProvider: LLMProvider, Sendable {
    let base = WorkflowProvider(.appleIntelligence, calls: WorkflowCalls())
    let gate: WorkflowChunkGate
    init(gate: WorkflowChunkGate) { self.gate = gate }
    var providerType: LLMProviderType { .appleIntelligence }
    var isAvailable: Bool { true }
    var config: LLMProviderConfig { base.config }
    func complete(prompt: String) async throws -> String { try await base.complete(prompt: prompt) }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> { await gate.stream() }
    func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis { try await base.analyze(request, steps: steps) }
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse { try await base.refine(request) }
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> { await gate.stream() }
    func validate() async throws {}
    func cancel() {}
}

@Test(.timeLimit(.minutes(1))) func testBuiltInRefinementStreamsChunksBeforeProviderCompletion() async throws {
    let gate = WorkflowChunkGate()
    let runtime = WorkflowRuntime(configuration: WorkflowExecutionConfiguration(providers: [.appleIntelligence: WorkflowStreamingProvider(gate: gate)]))
    var chunks: [String] = []
    for try await chunk in try await runtime.refineStreaming(RefinementRequest(text: "input"), preset: .appleSpeech) {
        chunks.append(chunk)
        if chunk == "first" { #expect(await !gate.finished); await gate.finish() }
    }
    #expect(chunks == ["first", "second"])
    #expect(await gate.finished)
}
