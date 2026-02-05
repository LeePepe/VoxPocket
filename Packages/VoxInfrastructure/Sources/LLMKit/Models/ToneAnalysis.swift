import Foundation
import FoundationModels

@Generable
public enum ToneKind: String, Sendable, Equatable {
    case neutral
    case casual
    case formal
    case urgent
    case polite
    case frustrated
}

@Generable
public struct ToneAnalysis: Sendable, Equatable {
    @Guide(description: "语气：neutral / casual / formal / urgent / polite / frustrated")
    public let tone: ToneKind
    @Guide(description: "语气置信度，0.0 到 1.0")
    public let confidence: Double

    public init(tone: ToneKind = .neutral, confidence: Double = 0.0) {
        self.tone = tone
        self.confidence = min(max(confidence, 0.0), 1.0)
    }

    public var logDescription: String {
        "语气:\(tone.rawValue) | 置信度:\(String(format: "%.2f", confidence))"
    }
}
