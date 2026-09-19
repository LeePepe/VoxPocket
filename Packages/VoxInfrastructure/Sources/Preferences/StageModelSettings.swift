import Foundation

public enum SpeechModelSelection: String, Codable, CaseIterable, Sendable {
    case realtime, batch, appleSpeech
}

public enum TextModelSelection: String, Codable, CaseIterable, Sendable {
    case appleIntelligence, azureFoundry
}

/// 只包含非敏感选择；模型端点和凭据仍由运行时私密配置提供。
public struct StageModelSettings: Equatable, Sendable {
    public var speech: SpeechModelSelection
    public var intent: TextModelSelection
    public var tone: TextModelSelection
    public var refinement: TextModelSelection
    public var skipAnalysis: Bool
    public var realtimeDeployment: String

    public init(speech: SpeechModelSelection = .realtime, intent: TextModelSelection = .appleIntelligence,
                tone: TextModelSelection = .appleIntelligence, refinement: TextModelSelection = .azureFoundry,
                skipAnalysis: Bool = false, realtimeDeployment: String = "") {
        self.speech = speech; self.intent = intent; self.tone = tone
        self.refinement = refinement; self.skipAnalysis = skipAnalysis
        self.realtimeDeployment = realtimeDeployment
    }

    public static func load(from store: any PreferencesStore) async -> Self {
        let speech: String? = await store.getValue(for: .speechModel)
        let intent: String? = await store.getValue(for: .intentModel)
        let tone: String? = await store.getValue(for: .toneModel)
        let refinement: String? = await store.getValue(for: .llmProvider)
        let skip: Bool? = await store.getValue(for: .llmSkipContentAnalysis)
        let deployment: String? = await store.getValue(for: .realtimeDeployment)
        return Self(speech: speech.flatMap(SpeechModelSelection.init(rawValue:)) ?? .realtime,
                    intent: intent.flatMap(TextModelSelection.init(rawValue:)) ?? .appleIntelligence,
                    tone: tone.flatMap(TextModelSelection.init(rawValue:)) ?? .appleIntelligence,
                    refinement: refinement.flatMap(TextModelSelection.init(rawValue:)) ?? .azureFoundry,
                    skipAnalysis: skip ?? false,
                    realtimeDeployment: validDeploymentOverride(deployment ?? "") ? deployment ?? "" : "")
    }

    public static func validDeploymentOverride(_ value: String) -> Bool {
        value.isEmpty || (value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil
                         && !value.contains("\n") && !value.contains("\r"))
    }
}

/// 设置页只接收非敏感的能力与展示信息，不接触运行时凭据。
public struct ModelSettingsAvailability: Equatable, Sendable {
    public let batchConfigured: Bool
    public let realtimeCredentialsConfigured: Bool
    public let realtimeDeployment: String
    public let textConfigured: Bool
    public let textModelName: String

    public init(batchConfigured: Bool = false, realtimeCredentialsConfigured: Bool = false,
                realtimeDeployment: String = "", textConfigured: Bool = false, textModelName: String = "") {
        self.batchConfigured = batchConfigured
        self.realtimeCredentialsConfigured = realtimeCredentialsConfigured
        self.realtimeDeployment = realtimeDeployment
        self.textConfigured = textConfigured
        self.textModelName = textModelName
    }
}
