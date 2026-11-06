import Foundation

public extension Preset {
    static let hybridAzure = Preset(
        id: "hybrid.azure",
        speech: WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "azureBatch", kind: .speechAzureBatch, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "azureRealtime", kind: .speechAzureRealtime, inputs: [PortRef(nodeID: "capture", port: "audio")],
                     onFailure: .fallback(nodeID: "azureBatch"))
            NodeSpec(id: "merge", kind: .mergeLLM,
                     inputs: [PortRef(nodeID: "apple", port: "text"), PortRef(nodeID: "azureRealtime", port: "text")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "merge", port: "text")])
        },
        refine: Preset.refineDefinition(provider: .llmAzure)
    )

    static let `default` = hybridAzure

    static let appleSpeech = Preset(
        id: "apple.speech",
        speech: WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "apple", port: "text")])
        },
        refine: Preset.refineDefinition(provider: .llmApple)
    )

    private static func refineDefinition(provider: NodeKindID) -> WorkflowDefinition {
        let steps = ["intent", "entities", "tags", "params", "tone"]
        let analysis = steps.map { step in
            NodeSpec(id: step, kind: NodeKindID(rawValue: "analyze.\(step)"),
                     inputs: [PortRef(nodeID: "input", port: "text")],
                     params: ["analysis.\(step).provider": .string("appleIntelligence")],
                     onFailure: .defaultValue(.null))
        }
        return WorkflowDefinition(entry: .refine, nodes: [NodeSpec(id: "input", kind: .refineInput)] + analysis + [
            NodeSpec(id: "prompt", kind: .refinePrompt,
                     inputs: [PortRef(nodeID: "input", port: "text")] + steps.map { PortRef(nodeID: $0, port: "analysis") }),
            NodeSpec(id: "llm", kind: provider, inputs: [PortRef(nodeID: "prompt", port: "prompt")]),
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "llm", port: "text")])
        ])
    }
}

public extension NodeKindID {
    static let refineInput: Self = "refine.input"
    static let analyzeEntities: Self = "analyze.entities"
    static let analyzeTags: Self = "analyze.tags"
    static let analyzeParams: Self = "analyze.params"
}
