import Foundation

public enum SpeechModelSelection: String, Codable, CaseIterable, Sendable {
    case realtime, batch, appleSpeech
}

public enum TextModelSelection: String, Codable, CaseIterable, Sendable {
    case appleIntelligence, azureFoundry
}

public enum RealtimeStreamModelKind: String, Codable, CaseIterable, Sendable {
    case gptRealtime
    case maiTranscribe2

    public var displayName: String {
        switch self {
        case .gptRealtime: return "GPT 流式转写 (gpt-live-transcribe)"
        case .maiTranscribe2: return "MAI-Transcribe-2 流式转写"
        }
    }
}

/// 只包含非敏感选择；模型端点和凭据仍由运行时私密配置提供。
public struct StageModelSettings: Equatable, Sendable {
    public var speech: SpeechModelSelection
    public var intent: TextModelSelection
    public var tone: TextModelSelection
    public var refinement: TextModelSelection
    public var skipAnalysis: Bool
    public var realtimeDeployment: String
    public var realtimeStreamModel: RealtimeStreamModelKind
    public var hasExplicitRealtimeStreamModel: Bool
    public var gptRealtimeDeployment: String
    public var maiRealtimeDeployment: String

    public init(speech: SpeechModelSelection = .realtime, intent: TextModelSelection = .appleIntelligence,
                tone: TextModelSelection = .appleIntelligence, refinement: TextModelSelection = .azureFoundry,
                skipAnalysis: Bool = false, realtimeDeployment: String = "",
                realtimeStreamModel: RealtimeStreamModelKind? = nil,
                hasExplicitRealtimeStreamModel: Bool = false,
                gptRealtimeDeployment: String = "", maiRealtimeDeployment: String = "") {
        self.speech = speech; self.intent = intent; self.tone = tone
        self.refinement = refinement; self.skipAnalysis = skipAnalysis
        self.realtimeDeployment = Self.sanitizedDeployment(realtimeDeployment)
        self.gptRealtimeDeployment = Self.sanitizedDeployment(gptRealtimeDeployment)
        self.maiRealtimeDeployment = Self.sanitizedDeployment(maiRealtimeDeployment)
        self.hasExplicitRealtimeStreamModel = hasExplicitRealtimeStreamModel || realtimeStreamModel != nil
        self.realtimeStreamModel = realtimeStreamModel
            ?? (self.gptRealtimeDeployment.isEmpty && !self.maiRealtimeDeployment.isEmpty ? .maiTranscribe2 : .gptRealtime)
    }

    public static func load(from store: any PreferencesStore) async -> Self {
        let speech: String? = await store.getValue(for: .speechModel)
        let intent: String? = await store.getValue(for: .intentModel)
        let tone: String? = await store.getValue(for: .toneModel)
        let refinement: String? = await store.getValue(for: .llmProvider)
        let skip: Bool? = await store.getValue(for: .llmSkipContentAnalysis)
        let deployment: String? = await store.getValue(for: .realtimeDeployment)
        let gptDeployment: String? = await store.getValue(for: .gptRealtimeDeployment)
        let maiDeployment: String? = await store.getValue(for: .maiRealtimeDeployment)
        let storedStreamModel: String? = await store.getValue(for: .realtimeStreamModel)
        let gpt = sanitizedDeployment(gptDeployment ?? "")
        let mai = sanitizedDeployment(maiDeployment ?? "")
        let streamModel = storedStreamModel.flatMap(RealtimeStreamModelKind.init(rawValue:))
        return Self(speech: speech.flatMap(SpeechModelSelection.init(rawValue:)) ?? .realtime,
                    intent: intent.flatMap(TextModelSelection.init(rawValue:)) ?? .appleIntelligence,
                    tone: tone.flatMap(TextModelSelection.init(rawValue:)) ?? .appleIntelligence,
                    refinement: refinement.flatMap(TextModelSelection.init(rawValue:)) ?? .azureFoundry,
                    skipAnalysis: skip ?? false,
                    realtimeDeployment: sanitizedDeployment(deployment ?? ""),
                    realtimeStreamModel: streamModel,
                    gptRealtimeDeployment: gpt,
                    maiRealtimeDeployment: mai)
    }

    public func effectiveRealtimeStreamModel(gptDefault: String = "", maiDefault: String = "") -> RealtimeStreamModelKind {
        if hasExplicitRealtimeStreamModel { return realtimeStreamModel }
        let gpt = !gptRealtimeDeployment.isEmpty ? gptRealtimeDeployment : Self.sanitizedDeployment(gptDefault)
        let mai = !maiRealtimeDeployment.isEmpty ? maiRealtimeDeployment : Self.sanitizedDeployment(maiDefault)
        if gpt.isEmpty && !mai.isEmpty { return .maiTranscribe2 }
        return realtimeStreamModel
    }

    public func resolvedRealtimeDeployment(gptDefault: String = "", maiDefault: String = "",
                                           legacyDefault: String = "") -> String {
        let candidates: [String]
        switch effectiveRealtimeStreamModel(gptDefault: gptDefault, maiDefault: maiDefault) {
        case .maiTranscribe2:
            candidates = [maiRealtimeDeployment, maiDefault, realtimeDeployment, legacyDefault]
        case .gptRealtime:
            candidates = [gptRealtimeDeployment, gptDefault, realtimeDeployment, legacyDefault]
        }
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, Self.validDeploymentOverride(trimmed) { return trimmed }
        }
        return ""
    }

    public static func validDeploymentOverride(_ value: String) -> Bool {
        value.isEmpty || (value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil
                         && !value.contains("\n") && !value.contains("\r"))
    }

    private static func sanitizedDeployment(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return validDeploymentOverride(trimmed) ? trimmed : ""
    }
}

/// 设置页只接收非敏感的能力与展示信息，不接触运行时凭据。
public struct ModelSettingsAvailability: Equatable, Sendable {
    public let batchConfigured: Bool
    public let realtimeCredentialsConfigured: Bool
    public let realtimeDeployment: String
    public let gptRealtimeDeployment: String
    public let maiRealtimeDeployment: String
    public let textConfigured: Bool
    public let textModelName: String

    public init(batchConfigured: Bool = false, realtimeCredentialsConfigured: Bool = false,
                realtimeDeployment: String = "", textConfigured: Bool = false, textModelName: String = "",
                gptRealtimeDeployment: String = "", maiRealtimeDeployment: String = "") {
        self.batchConfigured = batchConfigured
        self.realtimeCredentialsConfigured = realtimeCredentialsConfigured
        self.realtimeDeployment = realtimeDeployment
        self.gptRealtimeDeployment = gptRealtimeDeployment
        self.maiRealtimeDeployment = maiRealtimeDeployment
        self.textConfigured = textConfigured
        self.textModelName = textModelName
    }
}
