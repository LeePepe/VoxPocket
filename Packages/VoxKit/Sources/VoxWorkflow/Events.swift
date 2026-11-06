import Foundation
import VoxCore
import VoxRefine

public enum WorkflowEvent: Sendable, Equatable {
    case partial(TranscriptionResult)
    case final(TranscriptionResult)
    case level(Float)
    case state(AudioCaptureState)
    case nodeStarted(label: VoxLabel)
    case nodeFinished(label: VoxLabel)
    case nodeFailed(label: VoxLabel, reason: VoxLabel)
    case refinedChunk(String)
    case completed(RefinementResponse?)
}

public enum WorkflowNodeValue: Sendable {
    case json(JSONValue)
    case text(String)
    case transcription(TranscriptionResult)
    case response(RefinementResponse)
    case string(String)
    case refinementRequest(RefinementRequest)
    case speechSession(any SpeechSession)
    case audio(WorkflowAudioCapture)
    case transcriptionResult(TranscriptionResult)
    case analysis(PartialAnalysis)
    case prompt(WorkflowPrompt)
    case none

    var jsonValue: JSONValue {
        switch self {
        case .json(let value): return value
        case .text(let value), .string(let value): return .string(value)
        case .transcription(let value), .transcriptionResult(let value): return .string(value.text)
        case .response(let value): return .string(value.refinedText)
        case .refinementRequest(let value): return .string(value.text)
        case .speechSession, .audio, .analysis, .prompt, .none: return .null
        }
    }
}

public struct WorkflowPrompt: Sendable {
    public let request: RefinementRequest
    public let text: String
    public let analysis: PartialAnalysis
    public let missingSteps: Set<AnalysisStep>

    public init(request: RefinementRequest, text: String, analysis: PartialAnalysis, missingSteps: Set<AnalysisStep>) {
        self.request = request
        self.text = text
        self.analysis = analysis
        self.missingSteps = missingSteps
    }
}

public enum WorkflowRuntimeError: Error, Sendable, Equatable, LocalizedError {
    case nodeFailed

    public var errorDescription: String? { "workflow runtime failed: nodeFailed" }
}

public struct WorkflowNodeContext: Sendable {
    public let node: NodeSpec
    public let inputs: [WorkflowNodeValue]
    public let workflowInput: WorkflowNodeValue
    public let configuration: WorkflowExecutionConfiguration
    public let speechNodeKinds: [NodeKindID]
    private let continuation: AsyncThrowingStream<WorkflowEvent, Error>.Continuation?

    public init(node: NodeSpec, inputs: [WorkflowNodeValue], workflowInput: WorkflowNodeValue = .none,
                configuration: WorkflowExecutionConfiguration = WorkflowExecutionConfiguration(),
                speechNodeKinds: [NodeKindID] = [],
                continuation: AsyncThrowingStream<WorkflowEvent, Error>.Continuation? = nil) {
        self.node = node
        self.inputs = inputs
        self.workflowInput = workflowInput
        self.configuration = configuration
        self.speechNodeKinds = speechNodeKinds
        self.continuation = continuation
    }

    public func emit(_ event: WorkflowEvent) { continuation?.yield(event) }
}
