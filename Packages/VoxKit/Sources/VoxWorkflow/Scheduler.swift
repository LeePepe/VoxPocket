import Foundation
import Synchronization
import VoxCore
import VoxLLM
import VoxRefine

public final class WorkflowRuntime: Sendable {
    private let registry: NodeRegistry
    private let logger: any VoxLogger
    private let telemetry: any VoxTelemetry
    private let state = Mutex(State())

    private struct State: Sendable { var cancelled = false }

    public init(
        registry: NodeRegistry = .builtIn,
        logger: any VoxLogger = NoopVoxLogger(),
        telemetry: any VoxTelemetry = NoopVoxTelemetry()
    ) {
        self.registry = registry
        self.logger = logger
        self.telemetry = telemetry
    }

    public func validate(_ definition: WorkflowDefinition) throws {
        try definition.validate(using: registry)
    }

    public func cancel() { state.withLock { $0.cancelled = true } }

    public func resetCancellation() { state.withLock { $0.cancelled = false } }

    public func execute(_ definition: WorkflowDefinition, input: JSONValue? = nil) async throws -> [WorkflowEvent] {
        resetCancellation()
        try validate(definition)
        let layers = try topologicalLayers(definition)
        var outputs: [String: JSONValue] = [:]
        var events: [WorkflowEvent] = []
        if let input { outputs["input"] = input }

        for layer in layers {
            try Task.checkCancellation()
            guard !state.withLock({ $0.cancelled }) else { throw CancellationError() }
            let labels = layer.compactMap { registry.label(for: $0.kind) }
            events.append(contentsOf: labels.map { .nodeStarted(label: $0) })
            let results = try await withThrowingTaskGroup(of: (String, WorkflowNodeValue, VoxLabel, Bool).self,
                                                           returning: [(String, WorkflowNodeValue, VoxLabel, Bool)].self) { group in
                for node in layer {
                    group.addTask { [registry, outputs] in
                        let label = registry.label(for: node.kind) ?? .custom(index: -1)
                        let values = node.inputs.map { outputs[$0.nodeID] ?? .null }
                        guard let handler = registry.handler(for: node.kind) else {
                            throw WorkflowValidationError(code: .unknownNodeKind, nodeID: node.id)
                        }
                        do {
                            let result = try await handler.execute(context: WorkflowNodeContext(node: node, inputs: values))
                            return (node.id, result, label, false)
                        } catch {
                            if Task.isCancelled { throw CancellationError() }
                            switch node.onFailure {
                            case .fail: throw error
                            case .fallback(let fallbackID):
                                guard let fallback = definition.nodes.first(where: { $0.id == fallbackID }),
                                      let fallbackHandler = registry.handler(for: fallback.kind) else { throw error }
                                let result = try await fallbackHandler.execute(context: WorkflowNodeContext(node: fallback, inputs: values))
                                return (node.id, result, label, true)
                            case .defaultValue(let value): return (node.id, .json(value), label, true)
                            }
                        }
                    }
                }
                var values: [(String, WorkflowNodeValue, VoxLabel, Bool)] = []
                for try await value in group { values.append(value) }
                return values.sorted { $0.0 < $1.0 }
            }
            for (id, value, label, recovered) in results {
                outputs[id] = value.jsonValue
                if recovered { events.append(.nodeFailed(label: label, reason: .reason("node_failure"))) }
                events.append(.nodeFinished(label: label))
                telemetry.record(VoxTelemetryEvent(name: "workflow.node.completed", fields: [.label("node", label)]))
            }
        }
        events.append(.completed(nil))
        logger.info("workflow.completed", fields: [.int("node_count", definition.nodes.count)])
        return events
    }

    public func events(for definition: WorkflowDefinition, input: JSONValue? = nil) -> AsyncThrowingStream<WorkflowEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for event in try await execute(definition, input: input) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func makeSpeechSource(preset: Preset, source: any SpeechSessionSource) -> WorkflowSpeechSessionSource {
        WorkflowSpeechSessionSource(source: source, preset: preset)
    }

    public func refine(_ request: RefinementRequest, service: any LLMService) async throws -> RefinementResponse {
        try Task.checkCancellation()
        let response = try await service.refine(request)
        telemetry.record(VoxTelemetryEvent(name: "workflow.refine.completed", fields: [.int("text_length", request.text.count)]))
        return response
    }

    public func refineStreaming(_ request: RefinementRequest, service: any LLMService) async throws -> AsyncThrowingStream<String, Error> {
        try Task.checkCancellation()
        return try await service.refineStreaming(request)
    }

    private func topologicalLayers(_ definition: WorkflowDefinition) throws -> [[NodeSpec]] {
        var pending = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
        var completed = Set<String>()
        var layers: [[NodeSpec]] = []
        while !pending.isEmpty {
            let layer = pending.values.filter { node in node.inputs.allSatisfy { completed.contains($0.nodeID) } }
                .sorted { $0.id < $1.id }
            guard !layer.isEmpty else { throw WorkflowValidationError(code: .cycleDetected) }
            layers.append(layer)
            for node in layer { pending.removeValue(forKey: node.id); completed.insert(node.id) }
        }
        return layers
    }
}

public final class WorkflowSpeechSessionSource: SpeechSessionSource, MultiRecognizerSpeechSource, Sendable {
    private let source: any SpeechSessionSource
    public let preset: Preset

    public init(source: any SpeechSessionSource, preset: Preset) {
        self.source = source
        self.preset = preset
    }

    public var merger: (any TranscriptionMerger)? { (source as? any MultiRecognizerSpeechSource)?.merger }
    public var supportedLanguages: [Locale] { source.supportedLanguages }
    public var providerKind: ASRProviderType { source.providerKind }
    public var isActive: Bool { source.isActive }
    public func requestMicrophonePermission() async -> Bool { await source.requestMicrophonePermission() }
    public func requestSpeechPermission() async -> Bool { await source.requestSpeechPermission() }
    public var hasMicrophonePermission: Bool { source.hasMicrophonePermission }
    public var hasSpeechPermission: Bool { source.hasSpeechPermission }
    public func captureStates() -> AsyncStream<AudioCaptureState> { source.captureStates() }
    public func audioLevels() -> AsyncStream<Float> { source.audioLevels() }
    public func startSession(language: Locale) async throws -> any SpeechSession { try await source.startSession(language: language) }
}

