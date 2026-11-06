import Foundation

public enum WorkflowEntry: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case speech
    case refine
}

public struct NodeKindID: RawRepresentable, ExpressibleByStringLiteral, Codable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let captureMicrophone: Self = "capture.microphone"
    public static let speechApple: Self = "speech.apple"
    public static let speechAzureBatch: Self = "speech.azure.batch"
    public static let speechAzureRealtime: Self = "speech.azure.realtime"
    public static let speechWhisperKitLocal: Self = "speech.whisperkit.local"
    public static let mergeLLM: Self = "merge.llm"
    public static let analyzeIntent: Self = "analyze.intent"
    public static let analyzeTone: Self = "analyze.tone"
    public static let refinePrompt: Self = "refine.prompt"
    public static let llmApple: Self = "llm.apple"
    public static let llmAzure: Self = "llm.azure"
    public static let outputText: Self = "output.text"
}

public enum PortType: String, Codable, Sendable, Equatable, Hashable {
    case audio
    case text
    case analysis
    case prompt
    case metadata
}

public struct PortRef: Codable, Sendable, Equatable, Hashable {
    public let nodeID: String
    public let port: String

    public init(nodeID: String, port: String) {
        self.nodeID = nodeID
        self.port = port
    }
}

public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        self = .array(try container.decode([JSONValue].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public enum FailurePolicy: Codable, Sendable, Equatable, Hashable {
    case fail
    case fallback(nodeID: String)
    case defaultValue(JSONValue)

    private enum CodingKeys: String, CodingKey { case kind, nodeID, value }
    private enum Kind: String, Codable { case fail, fallback, defaultValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .fail: self = .fail
        case .fallback: self = .fallback(nodeID: try container.decode(String.self, forKey: .nodeID))
        case .defaultValue: self = .defaultValue(try container.decode(JSONValue.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fail: try container.encode(Kind.fail, forKey: .kind)
        case .fallback(let nodeID):
            try container.encode(Kind.fallback, forKey: .kind)
            try container.encode(nodeID, forKey: .nodeID)
        case .defaultValue(let value):
            try container.encode(Kind.defaultValue, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct NodeSpec: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let kind: NodeKindID
    public let inputs: [PortRef]
    public let params: [String: JSONValue]
    public let onFailure: FailurePolicy
    public let concurrency: Int?

    public init(
        id: String,
        kind: NodeKindID,
        inputs: [PortRef] = [],
        params: [String: JSONValue] = [:],
        onFailure: FailurePolicy = .fail,
        concurrency: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.inputs = inputs
        self.params = params
        self.onFailure = onFailure
        self.concurrency = concurrency
    }
}

public struct WorkflowDefinition: Codable, Sendable, Equatable, Hashable {
    public let version: Int
    public let entry: WorkflowEntry
    public let nodes: [NodeSpec]

    public init(entry: WorkflowEntry, nodes: [NodeSpec], version: Int = 1) {
        self.version = version
        self.entry = entry
        self.nodes = nodes
    }
}

public struct WorkflowValidationError: Error, Sendable, Equatable, LocalizedError {
    public enum Code: String, Sendable, Equatable, Codable {
        case unknownNodeKind
        case duplicateNodeID
        case danglingReference
        case cycleDetected
        case portTypeMismatch
        case entryMismatch
        case emptyWorkflow
    }

    public let code: Code
    public let nodeID: String?

    public init(code: Code, nodeID: String? = nil) {
        self.code = code
        self.nodeID = nodeID
    }

    public var errorDescription: String? {
        if let nodeID { return "workflow validation failed: \(code.rawValue) (node: \(nodeID))" }
        return "workflow validation failed: \(code.rawValue)"
    }
}
