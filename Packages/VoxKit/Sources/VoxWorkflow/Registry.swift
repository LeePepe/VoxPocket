import Foundation
import Synchronization
import VoxCore

public protocol WorkflowNodeHandler: Sendable {
    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue
}

public struct NodeSignature: Sendable, Equatable {
    public let kind: NodeKindID
    public let allowedEntries: Set<WorkflowEntry>
    public let inputTypes: [PortType]
    public let outputType: PortType
    public let defaultConcurrency: Int?

    public init(
        kind: NodeKindID,
        allowedEntries: Set<WorkflowEntry>,
        inputTypes: [PortType] = [],
        outputType: PortType,
        defaultConcurrency: Int? = nil
    ) {
        self.kind = kind
        self.allowedEntries = allowedEntries
        self.inputTypes = inputTypes
        self.outputType = outputType
        self.defaultConcurrency = defaultConcurrency
    }
}

public final class NodeRegistry: Sendable {
    private struct Registration: Sendable {
        let signature: NodeSignature
        let handler: any WorkflowNodeHandler
        let label: VoxLabel
    }

    private struct State: Sendable {
        var registrations: [NodeKindID: Registration]
        var customIndex: Int
    }

    private let state: Mutex<State>

    public init(registerBuiltIns shouldRegisterBuiltIns: Bool = true) {
        state = Mutex(State(registrations: [:], customIndex: 0))
        if shouldRegisterBuiltIns { registerBuiltIns() }
    }

    public static var builtIn: NodeRegistry { NodeRegistry() }

    @discardableResult
    public func register(_ signature: NodeSignature, handler: any WorkflowNodeHandler) -> VoxLabel {
        state.withLock { state in
            if let existing = state.registrations[signature.kind] {
                state.registrations[signature.kind] = Registration(
                    signature: signature, handler: handler, label: existing.label)
                return existing.label
            }
            let label: VoxLabel
            if let builtInLabel = Self.builtInLabel(for: signature.kind) {
                label = builtInLabel
            } else {
                label = .custom(index: state.customIndex)
                state.customIndex += 1
            }
            state.registrations[signature.kind] = Registration(
                signature: signature, handler: handler, label: label)
            return label
        }
    }

    public func signature(for kind: NodeKindID) -> NodeSignature? {
        state.withLock { $0.registrations[kind]?.signature }
    }

    public func label(for kind: NodeKindID) -> VoxLabel? {
        state.withLock { $0.registrations[kind]?.label }
    }

    func handler(for kind: NodeKindID) -> (any WorkflowNodeHandler)? {
        state.withLock { $0.registrations[kind]?.handler }
    }

    public func contains(_ kind: NodeKindID) -> Bool {
        state.withLock { $0.registrations[kind] != nil }
    }

    public var registeredKinds: [NodeKindID] {
        state.withLock { $0.registrations.keys.sorted { $0.rawValue < $1.rawValue } }
    }

    private func registerBuiltIns() {
        let speech: Set<WorkflowEntry> = [.speech]
        let refine: Set<WorkflowEntry> = [.refine]
        let both: Set<WorkflowEntry> = [.speech, .refine]
        let builtIns: [NodeSignature] = [
            .init(kind: .captureMicrophone, allowedEntries: speech, outputType: .audio),
            .init(kind: .speechApple, allowedEntries: speech, inputTypes: [.audio], outputType: .text),
            .init(kind: .speechAzureBatch, allowedEntries: speech, inputTypes: [.audio], outputType: .text),
            .init(kind: .speechAzureRealtime, allowedEntries: speech, inputTypes: [.audio], outputType: .text),
            .init(kind: .speechWhisperKitLocal, allowedEntries: speech, inputTypes: [.audio], outputType: .text),
            .init(kind: .mergeLLM, allowedEntries: speech, inputTypes: [.text, .text], outputType: .text),
            .init(kind: .analyzeIntent, allowedEntries: refine, inputTypes: [.text], outputType: .analysis),
            .init(kind: .analyzeTone, allowedEntries: refine, inputTypes: [.text], outputType: .analysis),
            .init(kind: .refinePrompt, allowedEntries: refine, inputTypes: [.text, .analysis], outputType: .prompt),
            .init(kind: .llmApple, allowedEntries: refine, inputTypes: [.prompt], outputType: .text),
            .init(kind: .llmAzure, allowedEntries: refine, inputTypes: [.prompt], outputType: .text),
            .init(kind: .outputText, allowedEntries: both, inputTypes: [.text], outputType: .text),
            .init(kind: .refineInput, allowedEntries: refine, outputType: .text),
        ]
        let handler = BuiltInWorkflowNodeHandler()
        for signature in builtIns { _ = register(signature, handler: handler) }
    }

    private static func builtInLabel(for kind: NodeKindID) -> VoxLabel? {
        switch kind {
        case .captureMicrophone: return .node("capture.microphone")
        case .speechApple: return .node("speech.apple")
        case .speechAzureBatch: return .node("speech.azure.batch")
        case .speechAzureRealtime: return .node("speech.azure.realtime")
        case .speechWhisperKitLocal: return .node("speech.whisperkit.local")
        case .mergeLLM: return .node("merge.llm")
        case .analyzeIntent: return .node("analyze.intent")
        case .analyzeTone: return .node("analyze.tone")
        case .refinePrompt: return .node("refine.prompt")
        case .llmApple: return .node("llm.apple")
        case .llmAzure: return .node("llm.azure")
        case .outputText: return .node("output.text")
        default: return nil
        }
    }
}

private struct BuiltInWorkflowNodeHandler: WorkflowNodeHandler {}

public extension WorkflowDefinition {
    func validate(using registry: NodeRegistry = .builtIn) throws {
        guard !nodes.isEmpty else { throw WorkflowValidationError(code: .emptyWorkflow) }
        var byID: [String: NodeSpec] = [:]
        for node in nodes {
            guard byID[node.id] == nil else {
                throw WorkflowValidationError(code: .duplicateNodeID, nodeID: node.id)
            }
            byID[node.id] = node
            guard let signature = registry.signature(for: node.kind) else {
                throw WorkflowValidationError(code: .unknownNodeKind, nodeID: node.id)
            }
            guard signature.allowedEntries.contains(entry) else {
                throw WorkflowValidationError(code: .entryMismatch, nodeID: node.id)
            }
            guard node.inputs.count == signature.inputTypes.count else {
                throw WorkflowValidationError(code: .portTypeMismatch, nodeID: node.id)
            }
        }

        for node in nodes {
            guard let signature = registry.signature(for: node.kind) else { continue }
            for (index, input) in node.inputs.enumerated() {
                guard let producer = byID[input.nodeID], let producerSignature = registry.signature(for: producer.kind) else {
                    throw WorkflowValidationError(code: .danglingReference, nodeID: node.id)
                }
                guard producerSignature.outputType == signature.inputTypes[index] else {
                    throw WorkflowValidationError(code: .portTypeMismatch, nodeID: node.id)
                }
            }
            if case .fallback(let fallbackID) = node.onFailure {
                guard let fallback = byID[fallbackID], let fallbackSignature = registry.signature(for: fallback.kind) else {
                    throw WorkflowValidationError(code: .danglingReference, nodeID: node.id)
                }
                guard fallbackSignature.outputType == signature.outputType else {
                    throw WorkflowValidationError(code: .portTypeMismatch, nodeID: node.id)
                }
            }
        }

        var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        var edges = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, [String]()) })
        for node in nodes {
            for input in node.inputs where byID[input.nodeID] != nil {
                edges[input.nodeID, default: []].append(node.id)
                indegree[node.id, default: 0] += 1
            }
        }
        var queue = indegree.filter { $0.value == 0 }.map(\.key).sorted()
        var visited = 0
        while !queue.isEmpty {
            let id = queue.removeFirst()
            visited += 1
            for child in edges[id, default: []].sorted() {
                indegree[child, default: 0] -= 1
                if indegree[child] == 0 { queue.append(child) }
            }
        }
        guard visited == nodes.count else {
            throw WorkflowValidationError(code: .cycleDetected, nodeID: nodes.first { indegree[$0.id] ?? 0 > 0 }?.id)
        }
    }
}
