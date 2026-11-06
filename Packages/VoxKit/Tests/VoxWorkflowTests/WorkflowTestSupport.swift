import Foundation
import Synchronization
import VoxCore
import VoxLLM
import VoxRefine
import VoxSpeech
import VoxWorkflow

final class WorkflowCalls: Sendable {
    private let storage = Mutex<[String]>([])
    func append(_ value: String) { storage.withLock { $0.append(value) } }
    var values: [String] { storage.withLock { $0 } }
}

final class WorkflowProvider: LLMProvider, Sendable {
    let providerType: LLMProviderType
    let calls: WorkflowCalls
    let failedSteps: Set<AnalysisStep>
    var config: LLMProviderConfig { .init(providerType: providerType, modelIdentifier: "example-model") }
    var isAvailable: Bool { true }
    init(_ type: LLMProviderType, calls: WorkflowCalls, failedSteps: Set<AnalysisStep> = []) {
        providerType = type; self.calls = calls; self.failedSteps = failedSteps
    }
    func complete(prompt: String) async throws -> String {
        calls.append("\(providerType.rawValue):complete:\(prompt)")
        return "refined"
    }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        calls.append("\(providerType.rawValue):stream:\(prompt)")
        return AsyncThrowingStream { $0.yield("re"); $0.yield("fined"); $0.finish() }
    }
    func analyze(_ request: AnalysisRequest, steps: Set<AnalysisStep>) async throws -> PartialAnalysis {
        for step in steps {
            calls.append("\(providerType.rawValue):\(step.rawValue):\(request.text):\(request.options["example"] ?? ""):\(request.transcriptionMetadata?.locale?.identifier ?? "")")
        }
        if !failedSteps.isDisjoint(with: steps) { throw WorkflowProbeError.failed }
        return PartialAnalysis(intent: steps.contains(.intent) ? IntentAnalysis(intent: .polish, confidence: 0.75) : nil,
            tone: steps.contains(.tone) ? ToneAnalysis(tone: .formal, confidence: 0.5) : nil,
            entities: steps.contains(.entities) ? ["entity"] : nil, tags: steps.contains(.tags) ? ["tag"] : nil,
            params: steps.contains(.params) ? IntentParams(targetLanguage: "en") : nil)
    }
    func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        RefinementResponse(originalText: request.text, refinedText: try await complete(prompt: request.text))
    }
    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        try await completeStreaming(prompt: request.text)
    }
    func validate() async throws {}
    func cancel() {}
}

struct WorkflowSession: SpeechSession {
    let text: String
    let fails: Bool
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream {
            $0.yield(.state(.recording)); $0.yield(.level(0.5))
            $0.yield(.partial(TranscriptionResult(text: text, type: .partial)))
            if fails { $0.finish(throwing: WorkflowProbeError.failed) }
            else { $0.yield(.final(TranscriptionResult(text: text, type: .final))); $0.finish() }
        }
    }
    func pause() async {}
    func resume() async {}
    func stop() async {}
    func cancel() async {}
}

final class WorkflowSource: SpeechSessionSource, Sendable {
    let text: String
    let fails: Bool
    let calls: WorkflowCalls
    let name: String
    init(_ name: String, text: String, fails: Bool, calls: WorkflowCalls) {
        self.name = name; self.text = text; self.fails = fails; self.calls = calls
    }
    var supportedLanguages: [Locale] { [] }
    var providerKind: ASRProviderType { .apple }
    var isActive: Bool { false }
    func requestMicrophonePermission() async -> Bool { true }
    func requestSpeechPermission() async -> Bool { true }
    var hasMicrophonePermission: Bool { true }
    var hasSpeechPermission: Bool { true }
    func captureStates() -> AsyncStream<AudioCaptureState> { AsyncStream { $0.finish() } }
    func audioLevels() -> AsyncStream<Float> { AsyncStream { $0.finish() } }
    func startSession(language: Locale) async throws -> any SpeechSession {
        calls.append(name)
        return WorkflowSession(text: text, fails: fails)
    }
}

struct WorkflowFactory: SpeechSessionFactory {
    let source: WorkflowSource
    func makeSource() async throws -> any SpeechSessionSource { source }
}

struct WorkflowMerger: TranscriptionMerger {
    let fails: Bool
    let calls: WorkflowCalls
    func merge(appleSpeech: String, whisper: String) async throws -> String {
        calls.append("merge:\(appleSpeech):\(whisper)")
        if fails { throw WorkflowProbeError.failed }
        return "merged"
    }
}

enum WorkflowProbeError: Error { case failed }

func workflowConfiguration(calls: WorkflowCalls, realtimeFails: Bool = false, mergeFails: Bool = false,
                           failedSteps: Set<AnalysisStep> = []) -> WorkflowExecutionConfiguration {
    let factories = Dictionary(uniqueKeysWithValues: [NodeKindID.speechApple, .speechAzureBatch, .speechAzureRealtime, .speechWhisperKitLocal].map {
        ($0, WorkflowFactory(source: WorkflowSource($0.rawValue, text: $0.rawValue, fails: $0 == .speechAzureRealtime && realtimeFails, calls: calls)) as any SpeechSessionFactory)
    })
    return WorkflowExecutionConfiguration(providers: [
        .appleIntelligence: WorkflowProvider(.appleIntelligence, calls: calls, failedSteps: failedSteps),
        .azureFoundry: WorkflowProvider(.azureFoundry, calls: calls, failedSteps: failedSteps)
    ], merger: WorkflowMerger(fails: mergeFails, calls: calls), speechFactories: factories)
}
