import Foundation

@resultBuilder
public enum WorkflowBuilder {
    public static func buildBlock(_ components: NodeSpec...) -> [NodeSpec] { components }
    public static func buildOptional(_ component: [NodeSpec]?) -> [NodeSpec] { component ?? [] }
    public static func buildEither(first component: [NodeSpec]) -> [NodeSpec] { component }
    public static func buildEither(second component: [NodeSpec]) -> [NodeSpec] { component }
    public static func buildArray(_ components: [[NodeSpec]]) -> [NodeSpec] { components.flatMap { $0 } }
}

public extension WorkflowDefinition {
    init(version: Int = 1, entry: WorkflowEntry, @WorkflowBuilder nodes: () -> [NodeSpec]) {
        self.init(entry: entry, nodes: nodes(), version: version)
    }
}

public struct WorkflowPipelineSnapshot: Sendable, Equatable, Codable {
    public let speech: [String]
    public let realtime: Bool
    public let merger: Bool
    public let analysis: [String: String]
    public let refine: String
    public let configFailure: String

    public init(
        speech: [String],
        realtime: Bool,
        merger: Bool,
        analysis: [String: String],
        refine: String,
        configFailure: String = "none"
    ) {
        self.speech = speech
        self.realtime = realtime
        self.merger = merger
        self.analysis = analysis
        self.refine = refine
        self.configFailure = configFailure
    }
}

public struct Preset: Sendable, Equatable, Codable {
    public let id: String
    public let speech: WorkflowDefinition
    public let refine: WorkflowDefinition

    public init(id: String, speech: WorkflowDefinition, refine: WorkflowDefinition) {
        self.id = id
        self.speech = speech
        self.refine = refine
    }

    public func overriding(_ overrides: [String: String]) -> Preset {
        let speechDefinition = overrides["speech"].map(Self.speechDefinition(for:)) ?? speech
        let analysisProviderKeys = ["analysis.intent", "analysis.entities", "analysis.tags", "analysis.params", "analysis.tone"]
        let refinedNodes = refine.nodes.map { node in
            var params = node.params
            for key in analysisProviderKeys {
                if let value = overrides[key] { params["\(key).provider"] = .string(value) }
            }
            if let value = overrides["analysis.skip"] { params["analysis.skip"] = .string(value) }
            if let value = overrides["refine.provider"] { params["refine.provider"] = .string(value) }
            let kind: NodeKindID
            if [.llmApple, .llmAzure].contains(node.kind), let provider = overrides["refine.provider"] {
                kind = provider == "azureFoundry" ? .llmAzure : .llmApple
            } else { kind = node.kind }
            return NodeSpec(id: node.id, kind: kind, inputs: node.inputs, params: params,
                            onFailure: node.onFailure, concurrency: node.concurrency)
        }
        return Preset(id: id, speech: speechDefinition,
                      refine: WorkflowDefinition(entry: refine.entry, nodes: refinedNodes, version: refine.version))
    }

    public func exportedPipeline(
        batchConfigured: Bool = true,
        realtimeConfigured: Bool = true,
        azureTextConfigured: Bool = true
    ) -> WorkflowPipelineSnapshot {
        let speechNodes = speech.nodes
            .filter { $0.kind == .captureMicrophone || [.speechApple, .speechAzureBatch, .speechAzureRealtime, .speechWhisperKitLocal].contains($0.kind) }
            .map { $0.kind.rawValue }
        let hasRealtime = speech.nodes.contains { $0.kind == .speechAzureRealtime }
        let hasMerger = speech.nodes.contains { $0.kind == .mergeLLM }
        let analysis = Dictionary(refine.nodes.compactMap { node -> (String, String)? in
            guard node.kind.rawValue.hasPrefix("analyze.") else { return nil }
            let key = String(node.kind.rawValue.dropFirst("analyze.".count))
            if node.params["analysis.skip"] == .string("true") { return (key, "skipped") }
            guard let provider = node.params["analysis.\(key).provider"].flatMap(Self.stringValue) else { return nil }
            return (key, provider)
        }, uniquingKeysWith: { _, latest in latest })
        let refineProvider = refine.nodes.first { $0.kind == .llmAzure || $0.kind == .llmApple }?.params["refine.provider"].flatMap(Self.stringValue)
            ?? (refine.nodes.contains { $0.kind == .llmAzure } ? "azureFoundry" : "appleIntelligence")
        var failure = "none"
        if speech.nodes.contains(where: { $0.kind == .speechAzureBatch }) && !batchConfigured { failure = "batch" }
        if hasRealtime && !realtimeConfigured { failure = "realtime" }
        if refineProvider == "azureFoundry" && !azureTextConfigured { failure = "textModelUnavailable" }
        return WorkflowPipelineSnapshot(speech: speechNodes, realtime: hasRealtime, merger: hasMerger,
                                        analysis: analysis, refine: refineProvider, configFailure: failure)
    }

    private static func stringValue(_ value: JSONValue) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }

    private static func speechDefinition(for choice: String) -> WorkflowDefinition {
        switch choice {
        case "appleSpeech": return Preset.appleSpeech.speech
        case "localWhisperKit": return WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "local", kind: .speechWhisperKitLocal, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "local", port: "text")])
        }
        case "hybridLocalWhisper": return WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "local", kind: .speechWhisperKitLocal, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "merge", kind: .mergeLLM, inputs: [PortRef(nodeID: "apple", port: "text"), PortRef(nodeID: "local", port: "text")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "merge", port: "text")])
        }
        case "batch": return WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "batch", kind: .speechAzureBatch, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "batch", port: "text")])
        }
        case "realtime": return Preset.hybridAzure.speech
        default: return Preset.default.speech
        }
    }
}
