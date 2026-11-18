import Foundation
import Preferences

public enum LLMProviderSelection: String, CaseIterable, Codable, Sendable {
    case appleIntelligence
    case azureFoundry

    public var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .azureFoundry:
            return "Azure Foundry"
        }
    }
}

@MainActor
public final class LLMProviderSettingsViewModel: ObservableObject {
    @Published public var selectedProvider: LLMProviderSelection = .azureFoundry
    @Published public var skipContentAnalysis: Bool = false
    @Published public private(set) var speechModel: SpeechModelSelection = .realtime
    @Published public private(set) var intentModel: TextModelSelection = .appleIntelligence
    @Published public private(set) var toneModel: TextModelSelection = .appleIntelligence
    @Published public private(set) var realtimeStreamModel: RealtimeStreamModelKind = .gptRealtime
    @Published public var realtimeDeploymentDraft = ""
    @Published public var gptRealtimeDeploymentDraft = ""
    @Published public var maiRealtimeDeploymentDraft = ""
    @Published public private(set) var deploymentMessage: String?
    public let availability: ModelSettingsAvailability
    private var savedRealtimeDeployment = ""
    private var savedGPTRealtimeDeployment = ""
    private var savedMAIRealtimeDeployment = ""

    private let preferences: UserDefaultsPreferencesStore

    public init(preferences: UserDefaultsPreferencesStore = .shared,
                availability: ModelSettingsAvailability = .init()) {
        self.preferences = preferences
        self.availability = availability
    }

    public func load() async {
        let stored: String = await preferences.getValue(
            for: .llmProvider,
            default: LLMProviderSelection.azureFoundry.rawValue
        )
        selectedProvider = LLMProviderSelection(rawValue: stored) ?? .azureFoundry
        skipContentAnalysis = await preferences.getValue(for: .llmSkipContentAnalysis, default: false)
        let stages = await StageModelSettings.load(from: preferences)
        speechModel = stages.speech
        intentModel = stages.intent
        toneModel = stages.tone
        let storedStreamModel: String? = await preferences.getValue(for: .realtimeStreamModel)
        let editingLegacy = realtimeDeploymentDraft != savedRealtimeDeployment
        let editingGPT = gptRealtimeDeploymentDraft != savedGPTRealtimeDeployment
        let editingMAI = maiRealtimeDeploymentDraft != savedMAIRealtimeDeployment
        savedRealtimeDeployment = stages.realtimeDeployment
        savedGPTRealtimeDeployment = stages.gptRealtimeDeployment
        savedMAIRealtimeDeployment = stages.maiRealtimeDeployment
        if !editingLegacy { realtimeDeploymentDraft = stages.realtimeDeployment }
        if !editingGPT { gptRealtimeDeploymentDraft = stages.gptRealtimeDeployment }
        if !editingMAI { maiRealtimeDeploymentDraft = stages.maiRealtimeDeployment }
        if storedStreamModel == nil && stages.gptRealtimeDeployment.isEmpty && stages.maiRealtimeDeployment.isEmpty,
           !availability.maiRealtimeDeployment.isEmpty && availability.gptRealtimeDeployment.isEmpty {
            realtimeStreamModel = .maiTranscribe2
        } else {
            realtimeStreamModel = stages.realtimeStreamModel
        }
    }

    public var cloudModelLabel: String {
        availability.textModelName.isEmpty ? "Azure · 未配置模型" : "\(availability.textModelName) · Azure"
    }

    public var activeRealtimeDeployment: String {
        StageModelSettings(
            speech: speechModel, intent: intentModel, tone: toneModel,
            refinement: selectedProvider == .appleIntelligence ? .appleIntelligence : .azureFoundry,
            skipAnalysis: skipContentAnalysis,
            realtimeDeployment: savedRealtimeDeployment,
            realtimeStreamModel: realtimeStreamModel,
            gptRealtimeDeployment: savedGPTRealtimeDeployment,
            maiRealtimeDeployment: savedMAIRealtimeDeployment
        ).resolvedRealtimeDeployment(
            gptDefault: availability.gptRealtimeDeployment,
            maiDefault: availability.maiRealtimeDeployment,
            legacyDefault: availability.realtimeDeployment
        )
    }

    public var realtimeReady: Bool {
        availability.batchConfigured && availability.realtimeCredentialsConfigured
            && !activeRealtimeDeployment.isEmpty
            && StageModelSettings.validDeploymentOverride(activeRealtimeDeployment)
    }

    public var speechStatus: String {
        switch speechModel {
        case .appleSpeech: return "使用 Apple Speech 系统识别"
        case .batch: return availability.batchConfigured ? "松手后提交整段音频" : "云端未配置，使用 Apple Speech"
        case .realtime:
            if realtimeReady {
                let model = realtimeStreamModel == .maiTranscribe2 ? "MAI-Transcribe-2" : "GPT 流式"
                return "实时配置就绪（\(model)）· 下次录音使用"
            }
            return availability.batchConfigured ? "实时配置未完成，当前回退整段转写" : "云端未配置，当前回退 Apple Speech"
        }
    }

    public var hasSpeechWarning: Bool {
        speechModel == .realtime ? !realtimeReady : speechModel == .batch && !availability.batchConfigured
    }

    public func updateSpeechModel(_ model: SpeechModelSelection) async {
        speechModel = model
        await preferences.setValue(model.rawValue, for: .speechModel)
        notifyStages()
    }

    public func updateIntentModel(_ model: TextModelSelection) async {
        intentModel = model
        await preferences.setValue(model.rawValue, for: .intentModel)
        notifyStages()
    }

    public func updateToneModel(_ model: TextModelSelection) async {
        toneModel = model
        await preferences.setValue(model.rawValue, for: .toneModel)
        notifyStages()
    }

    public func updateRealtimeStreamModel(_ kind: RealtimeStreamModelKind) async {
        realtimeStreamModel = kind
        await preferences.setValue(kind.rawValue, for: .realtimeStreamModel)
        notifyStages()
    }

    public func saveStreamDeployments() async {
        let legacy = realtimeDeploymentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let gpt = gptRealtimeDeploymentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mai = maiRealtimeDeploymentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [legacy, gpt, mai].allSatisfy(StageModelSettings.validDeploymentOverride) else {
            deploymentMessage = "部署名只能包含字母、数字、点、横线和下划线，最多 128 个字符。"
            return
        }
        if legacy != savedRealtimeDeployment || !legacy.isEmpty {
            await preferences.setValue(legacy, for: .realtimeDeployment)
        }
        await preferences.setValue(gpt, for: .gptRealtimeDeployment)
        await preferences.setValue(mai, for: .maiRealtimeDeployment)
        savedRealtimeDeployment = legacy
        savedGPTRealtimeDeployment = gpt
        savedMAIRealtimeDeployment = mai
        realtimeDeploymentDraft = legacy
        gptRealtimeDeploymentDraft = gpt
        maiRealtimeDeploymentDraft = mai
        deploymentMessage = "已保存，下次录音生效。"
        notifyStages()
    }

    public func saveRealtimeDeployment() async {
        let value = realtimeDeploymentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StageModelSettings.validDeploymentOverride(value) else {
            deploymentMessage = "部署名只能包含字母、数字、点、横线和下划线，最多 128 个字符。"
            return
        }
        await preferences.setValue(value, for: .realtimeDeployment)
        savedRealtimeDeployment = value
        realtimeDeploymentDraft = value
        deploymentMessage = "已保存，下次录音生效。"
        notifyStages()
    }

    private func notifyStages() {
        NotificationCenter.default.post(name: PreferencesNotification.stageModelsDidChange, object: nil)
    }

    public func updateProvider(_ provider: LLMProviderSelection) async {
        selectedProvider = provider
        await preferences.setValue(provider.rawValue, for: .llmProvider)
        NotificationCenter.default.post(name: PreferencesNotification.llmProviderDidChange, object: nil)
    }

    public func updateSkipContentAnalysis(_ skip: Bool) async {
        skipContentAnalysis = skip
        await preferences.setValue(skip, for: .llmSkipContentAnalysis)
        NotificationCenter.default.post(name: PreferencesNotification.llmAnalysisSettingsDidChange, object: nil)
    }
}
