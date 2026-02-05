import Foundation

public enum AnalysisStep: String, CaseIterable, Sendable, Hashable {
    case intent
    case tone
    case entities
    case tags
    case params
}

public struct AnalysisRequest: Sendable {
    public let text: String
    public let options: [String: String]
    public let transcriptionMetadata: TranscriptionMetadata?

    public init(
        text: String,
        options: [String: String] = [:],
        transcriptionMetadata: TranscriptionMetadata? = nil
    ) {
        self.text = text
        self.options = options
        self.transcriptionMetadata = transcriptionMetadata
    }
}

public struct PartialAnalysis: Sendable, Equatable {
    public var intent: IntentAnalysis?
    public var tone: ToneAnalysis?
    public var entities: [String]?
    public var tags: [String]?
    public var params: IntentParams?

    public init(
        intent: IntentAnalysis? = nil,
        tone: ToneAnalysis? = nil,
        entities: [String]? = nil,
        tags: [String]? = nil,
        params: IntentParams? = nil
    ) {
        self.intent = intent
        self.tone = tone
        self.entities = entities
        self.tags = tags
        self.params = params
    }
}
