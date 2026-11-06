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

public enum WorkflowNodeValue: Sendable, Equatable {
    case json(JSONValue)
    case text(String)
    case transcription(TranscriptionResult)
    case response(RefinementResponse)
    case none

    var jsonValue: JSONValue {
        switch self {
        case .json(let value): return value
        case .text(let value): return .string(value)
        case .transcription(let value): return .string(value.text)
        case .response(let value): return .string(value.refinedText)
        case .none: return .null
        }
    }
}

public enum WorkflowRuntimeError: Error, Sendable, Equatable, LocalizedError {
    case nodeFailed

    public var errorDescription: String? { "workflow runtime failed: nodeFailed" }
}

public struct WorkflowNodeContext: Sendable {
    public let node: NodeSpec
    public let inputs: [JSONValue]

    public init(node: NodeSpec, inputs: [JSONValue]) {
        self.node = node
        self.inputs = inputs
    }
}

public extension WorkflowNodeHandler {
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue { .none }
}
