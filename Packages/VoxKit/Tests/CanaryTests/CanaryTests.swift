import Foundation
import Synchronization
import Testing
import VoxCore
import VoxLLM
import VoxRefine
import VoxSpeech
import VoxWorkflow
import VoxWorkflowWhisperKit

@Test func allBuiltInWorkflowPresetsDoNotLeakCanaryContent() async throws {
    let canary = "workflow-transcript-canary"
    let logger = CanaryLogger()
    let telemetry = CanaryTelemetry()
    let calls = Mutex<[String]>([])
    for mode in ["success", "realtimeFailure", "failure"] {
        let provider = CanaryProvider(canary: canary, fails: mode == "failure")
        let factories = Dictionary(uniqueKeysWithValues: [NodeKindID.speechApple, .speechAzureBatch, .speechAzureRealtime, .speechWhisperKitLocal].map { kind in
            (kind, CanaryFactory(source: CanarySource(text: canary + kind.rawValue,
                fails: mode == "failure" || (mode == "realtimeFailure" && kind == .speechAzureRealtime))) as any SpeechSessionFactory)
        })
        let registry = NodeRegistry()
        WorkflowWhisperKit.registerNodes(in: registry)
        let config = WorkflowExecutionConfiguration(providers: [.appleIntelligence: provider, .azureFoundry: provider],
            speechFactories: factories, logger: logger, telemetry: telemetry)
        let runtime = WorkflowRuntime(registry: registry, configuration: config)
        for preset in [Preset.hybridAzure, Preset.appleSpeech, Preset.localWhisperKit, Preset.hybridLocal] {
            var errors: [any Error] = []
            do {
                let events = try await runtime.execute(preset.speech, input: .string(canary))
                #expect(events.contains { if case .partial(let result) = $0 { result.text.contains(canary) } else { false } })
                #expect(events.contains { if case .final(let result) = $0 { result.text.contains(canary) } else { false } })
            } catch { errors.append(error) }
            let request = RefinementRequest(text: canary, customPrompt: canary, options: ["example": canary],
                transcriptionMetadata: TranscriptionMetadata(type: .final, confidence: 1, locale: Locale(identifier: "zh-Hans")))
            do {
                let response = try await runtime.refine(request, preset: preset)
                #expect(response.originalText == canary)
                #expect(response.refinedText == canary)
                let chunks = try await Array(runtime.refineStreaming(request, preset: preset))
                #expect(chunks.joined() == canary)
            } catch { errors.append(error) }
            if mode == "failure" { #expect(errors.count == 2) }
            else { #expect(errors.isEmpty) }
            for error in errors {
                calls.withLock { $0.append(error.localizedDescription) }
                #expect(logger.assertNoCanaryLeak(canaryStrings: [canary], error: error))
                #expect(telemetry.assertNoCanaryLeak(canaryStrings: [canary], error: error))
            }
            #expect(logger.assertNoCanaryLeak(canaryStrings: [canary]))
            #expect(telemetry.assertNoCanaryLeak(canaryStrings: [canary]))
        }
        #expect(provider.analysisCount.withLock { $0 } > 0)
    }
    #expect(calls.withLock { !$0.isEmpty })
}

private struct CanaryFailure: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

private final class CanaryProvider: LLMProvider, Sendable {
    let canary: String
    let fails: Bool
    let analysisCount = Mutex(0)
    init(canary: String, fails: Bool) { self.canary = canary; self.fails = fails }
    var providerType: LLMProviderType { .appleIntelligence }
    var config: LLMProviderConfig { .init(providerType: providerType, modelIdentifier: "example-model") }
    var isAvailable: Bool { true }
    func complete(prompt: String) async throws -> String {
        #expect(prompt.contains(canary))
        if fails { throw CanaryFailure(text: canary) }
        return canary
    }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        let text = try await complete(prompt: prompt)
        return AsyncThrowingStream { $0.yield(text); $0.finish() }
    }
    func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis {
        #expect(request.text == canary)
        #expect(request.options["example"] == canary)
        #expect(request.transcriptionMetadata?.confidence == 1)
        analysisCount.withLock { $0 += 1 }
        if fails { throw CanaryFailure(text: canary) }
        return PartialAnalysis(intent: IntentAnalysis(), tone: ToneAnalysis(), entities: [canary], tags: [canary], params: IntentParams())
    }
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        RefinementResponse(originalText: request.text, refinedText: try await complete(prompt: request.text))
    }
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> { try await completeStreaming(prompt: request.text) }
    func validate() async throws {}
    func cancel() {}
}

private struct CanaryFactory: SpeechSessionFactory {
    let source: CanarySource
    func makeSource() async throws -> any SpeechSessionSource { source }
}
private final class CanarySource: SpeechSessionSource, Sendable {
    let text: String
    let fails: Bool
    init(text: String, fails: Bool) { self.text = text; self.fails = fails }
    var supportedLanguages: [Locale] { [] }
    var providerKind: ASRProviderType { .custom }
    var isActive: Bool { false }
    var hasMicrophonePermission: Bool { true }
    var hasSpeechPermission: Bool { true }
    func requestMicrophonePermission() async -> Bool { true }
    func requestSpeechPermission() async -> Bool { true }
    func captureStates() -> AsyncStream<AudioCaptureState> { AsyncStream { $0.finish() } }
    func audioLevels() -> AsyncStream<Float> { AsyncStream { $0.finish() } }
    func startSession(language: Locale) async throws -> any SpeechSession { CanarySession(text: text, fails: fails) }
}
private struct CanarySession: SpeechSession {
    let text: String
    let fails: Bool
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream {
            $0.yield(.state(.recording)); $0.yield(.level(0.5))
            $0.yield(.partial(TranscriptionResult(text: text, type: .partial)))
            if fails { $0.finish(throwing: CanaryFailure(text: text)) }
            else { $0.yield(.final(TranscriptionResult(text: text, type: .final))); $0.finish() }
        }
    }
    func pause() async {}
    func resume() async {}
    func stop() async {}
    func cancel() async {}
}
