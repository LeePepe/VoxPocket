import Foundation

public extension Preset {
    static let hybridAzure = Preset(
        id: "hybrid.azure",
        speech: WorkflowDefinition(entry: .speech) {
            NodeSpec(id: "capture", kind: .captureMicrophone)
            NodeSpec(id: "apple", kind: .speechApple, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "batch", kind: .speechAzureBatch, inputs: [PortRef(nodeID: "capture", port: "audio")])
            NodeSpec(id: "realtime", kind: .speechAzureRealtime, inputs: [PortRef(nodeID: "capture", port: "audio")],
                     onFailure: .fallback(nodeID: "batch"))
            NodeSpec(id: "merge", kind: .mergeLLM,
                     inputs: [PortRef(nodeID: "apple", port: "text"), PortRef(nodeID: "batch", port: "text")])
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
        WorkflowDefinition(entry: .refine) {
            NodeSpec(id: "input", kind: .refineInput)
            NodeSpec(id: "intent", kind: .analyzeIntent, inputs: [PortRef(nodeID: "input", port: "text")])
            NodeSpec(id: "tone", kind: .analyzeTone, inputs: [PortRef(nodeID: "input", port: "text")])
            NodeSpec(id: "prompt", kind: .refinePrompt,
                     inputs: [PortRef(nodeID: "input", port: "text"), PortRef(nodeID: "intent", port: "analysis")])
            NodeSpec(id: "llm", kind: provider, inputs: [PortRef(nodeID: "prompt", port: "prompt")])
            NodeSpec(id: "output", kind: .outputText, inputs: [PortRef(nodeID: "llm", port: "text")])
        }
    }
}

extension NodeKindID {
    static let refineInput: Self = "refine.input"
}
