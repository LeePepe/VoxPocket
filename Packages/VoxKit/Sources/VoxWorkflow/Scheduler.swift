import Foundation
import Synchronization
import VoxCore
import VoxLLM
import VoxRefine

public final class WorkflowRuntime: Sendable {
    private let registry: NodeRegistry
    private let configuration: WorkflowExecutionConfiguration
    private let executions = Mutex<[UUID: Task<Void, Never>]>([:])

    public init(registry: NodeRegistry = .builtIn,
                configuration: WorkflowExecutionConfiguration = WorkflowExecutionConfiguration()) {
        self.registry = registry
        self.configuration = configuration
    }

    public convenience init(registry: NodeRegistry = .builtIn, logger: any VoxLogger,
                            telemetry: any VoxTelemetry = NoopVoxTelemetry()) {
        self.init(registry: registry, configuration: WorkflowExecutionConfiguration(logger: logger, telemetry: telemetry))
    }

    public func validate(_ definition: WorkflowDefinition) throws { try definition.validate(using: registry) }
    public func cancel() { executions.withLock { tasks in tasks.values.forEach { $0.cancel() } } }

    public func execute(_ definition: WorkflowDefinition, input: WorkflowNodeValue = .none) async throws -> [WorkflowEvent] {
        let (stream, task) = start(definition, input: input)
        return try await withTaskCancellationHandler {
            do {
                var events: [WorkflowEvent] = []
                for try await event in stream { events.append(event) }
                await task.value
                try Task.checkCancellation()
                return events
            } catch {
                task.cancel()
                await task.value
                throw error
            }
        } onCancel: { task.cancel() }
    }

    public func events(for definition: WorkflowDefinition, input: WorkflowNodeValue = .none) -> AsyncThrowingStream<WorkflowEvent, Error> {
        start(definition, input: input).0
    }

    private func start(_ definition: WorkflowDefinition, input: WorkflowNodeValue)
        -> (AsyncThrowingStream<WorkflowEvent, Error>, Task<Void, Never>) {
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<WorkflowEvent, Error>.makeStream()
        let task = executions.withLock { tasks in
            let task = Task { [self] in
                do {
                    try validate(definition)
                    let execution = WorkflowExecution(definition: definition, input: input, registry: registry,
                                                      configuration: configuration, continuation: continuation)
                    try await execution.run()
                    continuation.finish()
                } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
                catch let error as WorkflowValidationError { continuation.finish(throwing: error) }
                catch { continuation.finish(throwing: WorkflowRuntimeError.nodeFailed) }
                _ = executions.withLock { $0.removeValue(forKey: id) }
            }
            tasks[id] = task
            return task
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
        return (stream, task)
    }

    public func refine(_ request: RefinementRequest, preset: Preset = .default) async throws -> RefinementResponse {
        configuration.logger.info("开始文本优化", fields: [.int("text_length", request.text.count)])
        let events = try await execute(preset.refine, input: .refinementRequest(request))
        for event in events.reversed() {
            if case .completed(let response?) = event {
                configuration.logger.info("文本优化完成", fields: [.int("original_length", request.text.count), .int("refined_length", response.refinedText.count)])
                return response
            }
        }
        throw WorkflowRuntimeError.nodeFailed
    }

    public func refineStreaming(_ request: RefinementRequest, preset: Preset = .default) async throws -> AsyncThrowingStream<String, Error> {
        configuration.logger.info("开始流式文本优化", fields: [.int("text_length", request.text.count)])
        let nodes = preset.refine.nodes.map { node in
            var params = node.params
            if [.llmApple, .llmAzure].contains(node.kind) { params["streaming"] = .bool(true) }
            return NodeSpec(id: node.id, kind: node.kind, inputs: node.inputs, params: params,
                            onFailure: node.onFailure, concurrency: node.concurrency)
        }
        let events = events(for: WorkflowDefinition(entry: .refine, nodes: nodes), input: .refinementRequest(request))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if case .refinedChunk(let chunk) = event { continuation.yield(chunk) }
                    }
                    configuration.logger.info("流式文本优化完成")
                    continuation.finish()
                } catch {
                    configuration.logger.error("流式文本优化失败")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func makeSpeechSource(preset: Preset, source: any SpeechSessionSource) -> WorkflowSpeechSessionSource {
        WorkflowSpeechSessionSource(source: source, preset: preset)
    }
}

private actor WorkflowExecution {
    let definition: WorkflowDefinition
    let input: WorkflowNodeValue
    let registry: NodeRegistry
    let configuration: WorkflowExecutionConfiguration
    let continuation: AsyncThrowingStream<WorkflowEvent, Error>.Continuation
    let limiter = WorkflowConcurrencyLimiter()
    let eventState = WorkflowEventState()
    var outputs: [String: WorkflowNodeValue] = [:]
    var tasks: [String: Task<WorkflowNodeValue, Error>] = [:]

    init(definition: WorkflowDefinition, input: WorkflowNodeValue, registry: NodeRegistry,
         configuration: WorkflowExecutionConfiguration, continuation: AsyncThrowingStream<WorkflowEvent, Error>.Continuation) {
        self.definition = definition
        self.input = input
        self.registry = registry
        self.configuration = configuration
        self.continuation = continuation
    }

    func run() async throws {
        do { try await runGraph(); await finishCaptures(cancelled: false) }
        catch { await finishCaptures(cancelled: true); throw error }
    }

    private func finishCaptures(cancelled: Bool) async {
        for value in outputs.values {
            if case .audio(let capture) = value { await capture.finish(cancelled: cancelled) }
        }
    }

    private func runGraph() async throws {
        let terminal = definition.nodes.last { $0.kind == .outputText } ?? definition.nodes.last
        let nodesByID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
        var primaryReachableIDs = Set<String>()
        var ancestors = terminal.map { [$0.id] } ?? []
        while let id = ancestors.popLast() {
            guard primaryReachableIDs.insert(id).inserted, let node = nodesByID[id] else { continue }
            ancestors.append(contentsOf: node.inputs.map(\.nodeID))
        }
        let fallbackTargetIDs = Set(definition.nodes.compactMap { node -> String? in
            if case .fallback(let id) = node.onFailure { return id }; return nil
        })
        let fallbackOnlyIDs = fallbackTargetIDs.subtracting(primaryReachableIDs)
        var pending = definition.nodes.filter { primaryReachableIDs.contains($0.id) && !fallbackOnlyIDs.contains($0.id) }
        var completed = Set<String>()
        while !pending.isEmpty {
            try Task.checkCancellation()
            let layer = pending.filter { node in node.inputs.allSatisfy { completed.contains($0.nodeID) } }
            guard !layer.isEmpty else { throw WorkflowValidationError(code: .cycleDetected) }
            try await withThrowingTaskGroup(of: Void.self) { group in
                for node in layer { group.addTask { _ = try await self.resolve(node.id) } }
                do { for try await _ in group {} }
                catch { group.cancelAll(); throw error }
            }
            completed.formUnion(layer.map(\.id))
            pending.removeAll { completed.contains($0.id) }
        }
        try Task.checkCancellation()
        if let terminal, let value = outputs[terminal.id] {
            switch value {
            case .response(let response): continuation.yield(.completed(response))
            case .transcription(let result), .transcriptionResult(let result):
                if !eventState.hasFinal { continuation.yield(.final(result)) }
                continuation.yield(.completed(nil))
            default: continuation.yield(.completed(nil))
            }
        }
        configuration.logger.info("workflow.completed", fields: [.int("node_count", definition.nodes.count)])
    }

    func resolve(_ id: String) async throws -> WorkflowNodeValue {
        try Task.checkCancellation()
        if let output = outputs[id] { return output }
        let task: Task<WorkflowNodeValue, Error>
        if let existing = tasks[id] { task = existing }
        else {
            guard let node = definition.nodes.first(where: { $0.id == id }) else { throw WorkflowRuntimeError.nodeFailed }
            task = Task { try await self.perform(node) }
            tasks[id] = task
        }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            outputs[id] = value
            return value
        } onCancel: { task.cancel() }
    }

    private func perform(_ node: NodeSpec) async throws -> WorkflowNodeValue {
        var inputs: [WorkflowNodeValue] = []
        for reference in node.inputs { inputs.append(try await resolve(reference.nodeID)) }
        if node.inputs.isEmpty { inputs = [input] }
        let label = registry.label(for: node.kind) ?? .custom(index: -1)
        let key = node.params["concurrency.key"]?.stringValue ?? node.kind.rawValue
        let limit = definition.nodes.filter { ($0.params["concurrency.key"]?.stringValue ?? $0.kind.rawValue) == key }
            .compactMap { $0.concurrency ?? registry.signature(for: $0.kind)?.defaultConcurrency }.min()
        await limiter.acquire(key: key, limit: limit)
        do {
            try Task.checkCancellation()
            continuation.yield(.nodeStarted(label: label))
            let value = try await invoke(node, inputs: inputs, label: label)
            await limiter.release(key: key, limit: limit)
            continuation.yield(.nodeFinished(label: label))
            configuration.telemetry.record(VoxTelemetryEvent(name: "workflow.node.completed", fields: [.label("node", label)]))
            return value
        } catch {
            await limiter.release(key: key, limit: limit)
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            continuation.yield(.nodeFailed(label: label, reason: .reason("node_failure")))
            let recovered: WorkflowNodeValue
            switch node.onFailure {
            case .fail: throw WorkflowRuntimeError.nodeFailed
            case .fallback(let id): recovered = try await resolve(id)
            case .defaultValue(let value): recovered = .json(value)
            }
            continuation.yield(.nodeFinished(label: label))
            return recovered
        }
    }

    private func invoke(_ node: NodeSpec, inputs: [WorkflowNodeValue], label: VoxLabel) async throws -> WorkflowNodeValue {
        guard let handler = registry.handler(for: node.kind) else { throw WorkflowRuntimeError.nodeFailed }
        let fallbacks = Set(definition.nodes.compactMap { node -> String? in
            if case .fallback(let id) = node.onFailure { return id }; return nil
        })
        let speechKinds = definition.nodes.filter { spec in
            spec.inputs.contains { $0.nodeID == node.id } && !fallbacks.contains(spec.id) && spec.kind.rawValue.hasPrefix("speech.")
        }.map(\.kind)
        let emitsFinal = definition.nodes.contains { $0.kind == .outputText && $0.inputs.contains { $0.nodeID == node.id } }
        var context = WorkflowNodeContext(node: node, inputs: inputs, workflowInput: input,
            configuration: configuration, speechNodeKinds: speechKinds, emitsFinal: emitsFinal, continuation: continuation)
        context.eventState = eventState
        return try await handler.execute(context: context)
    }
}

private actor WorkflowConcurrencyLimiter {
    var counts: [String: Int] = [:]
    var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(key: String, limit: Int?) async {
        guard let limit else { return }
        if counts[key, default: 0] < limit { counts[key, default: 0] += 1; return }
        await withCheckedContinuation { waiters[key, default: []].append($0) }
    }

    func release(key: String, limit: Int?) {
        guard limit != nil else { return }
        if !waiters[key, default: []].isEmpty { waiters[key]?.removeFirst().resume() }
        else { counts[key, default: 0] -= 1 }
    }
}

public final class WorkflowSpeechSessionSource: SpeechSessionSource, MultiRecognizerSpeechSource, Sendable {
    private let source: any SpeechSessionSource
    public let preset: Preset
    public init(source: any SpeechSessionSource, preset: Preset) { self.source = source; self.preset = preset }
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
