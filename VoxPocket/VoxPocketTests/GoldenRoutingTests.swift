import Foundation
import XCTest
import Preferences
import TranscriptionKit
@testable import LLMKit
@testable import VoxPocket

final class GoldenRoutingTests: XCTestCase {
    #if os(macOS)
    @MainActor func testMacOSRoutingMatrix() async throws {
        var rows: [[String: Any]] = []
        var selections = SpeechModelSelection.allCases.map { StageModelSettings(speech: $0) }
        for keyPath in [\StageModelSettings.intent, \.tone, \.refinement] {
            selections = selections.flatMap { settings in
                TextModelSelection.allCases.map { provider in
                    var next = settings
                    next[keyPath: keyPath] = provider
                    return next
                }
            }
        }
        for settings in selections {
            for skip in [false, true] {
                var selection = settings
                selection.skipAnalysis = skip
                for config in ["fullConfig", "missingBatch", "missingRealtime", "missingAzureText"] {
                    rows.append(try await macOSRow(settings: selection, config: config))
                }
            }
        }
        XCTAssertEqual(rows.count, 192)
        try assertFixture(rows, name: "golden_b_macos")
    }

    @MainActor private func macOSRow(settings: StageModelSettings, config: String) async throws -> [String: Any] {
        let environment = macOSEnvironment(config)
        let coordinator = StageModelRouting.resolveTranscriber(settings: settings, environment: environment)
        let speech = StageModelRouting.resolvedSpeechModel(settings: settings, environment: environment)
        XCTAssertEqual(coordinator is AppleSpeechTranscriber, speech == .appleSpeech)
        XCTAssertEqual(coordinator is HybridWhisperTranscriber, speech != .appleSpeech)
        let azure = LLMAppConfig.refinementAPIKey(environment: environment).flatMap { key in
            LLMAppConfig.azureEndpoint(environment: environment).map { endpoint in
                LLMProviderConfig(providerType: .azureFoundry, apiKey: key, baseURL: endpoint,
                                  modelIdentifier: LLMAppConfig.azureModelIdentifier(environment: environment))
            }
        }
        let text = DefaultStageTextModelService(azureFoundryConfig: azure, settings: settings)
        let analysis = DefaultLLMService(azureFoundryConfig: azure)
        var failure = "none"
        do { try StageModelRouting.applyTextModels(settings, to: analysis) }
        catch { XCTAssertEqual(settings.refinement, .azureFoundry); XCTAssertNil(azure) }
        if settings.refinement == .azureFoundry && azure == nil {
            do {
                _ = try await text.refine(.init(text: "synthetic input"))
                XCTFail("Unconfigured Azure must fail before invoking a provider")
            } catch DefaultStageTextModelService.ConfigurationError.unavailable { failure = "textModelUnavailable" }
            XCTAssertNil(text.currentProviderType)
        } else { XCTAssertEqual(text.currentProviderType?.rawValue, settings.refinement.rawValue) }
        let route = StageModelRouting.analysisOptions(settings: settings)
        var providers = analysis.resolvedAnalysisRouting.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue }
        if failure != "none" {
            providers = Dictionary(uniqueKeysWithValues: AnalysisStep.allCases.map { ($0.rawValue, route["analysis.\($0.rawValue).provider"]!) })
        }
        if settings.skipAnalysis { providers = providers.mapValues { _ in "skipped" } }
        var nodes = ["capture.microphone", "speech.apple"]
        if speech == .realtime { nodes.append("speech.azure.realtime") }
        if speech != .appleSpeech { nodes.append("speech.azure.batch") }
        let pipeline: [String: Any] = ["speech": nodes, "realtime": speech == .realtime,
                                      "merger": (coordinator as? any MultiRecognizerTranscriber)?.merger != nil,
                                      "analysis": providers, "refine": text.currentProviderType?.rawValue ?? settings.refinement.rawValue,
                                      "configFailure": failure]
        return ["settings": ["speech": settings.speech.rawValue, "intent": settings.intent.rawValue,
                             "tone": settings.tone.rawValue, "refinement": settings.refinement.rawValue, "skip": settings.skipAnalysis],
                "configuration": config, "pipeline": pipeline]
    }

    private func macOSEnvironment(_ config: String) -> [String: String] {
        var environment = ["AZURE_OPENAI_ENDPOINT": "https://example.invalid", "whisperkey": "fixture-speech",
                           "AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT": "example-live", "kimikey": "fixture-text",
                           "AZURE_FOUNDRY_MODEL": "example-text"]
        if config == "missingBatch" { environment["AZURE_TRANSCRIPTION_ENDPOINT"] = "invalid" }
        if config == "missingRealtime" { environment.removeValue(forKey: "AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT") }
        if config == "missingAzureText" { environment.removeValue(forKey: "kimikey") }
        return environment
    }
    #endif

    #if !VOX_ROUTING_HARNESS
    @MainActor func testIOSPreferenceAndNotificationMatrix() async throws {
        var rows: [[String: Any]] = []
        for batch in [false, true] {
            for provider in ["unset", "azureFoundry", "appleIntelligence", "invalid"] {
                for skip in [false, true] {
                    for azure in [false, true] {
                        rows += try await preferenceRows(batch: batch, provider: provider, skip: skip, azure: azure)
                    }
                }
            }
        }
        XCTAssertEqual(rows.count, 224)
        try assertFixture(rows, name: "golden_b_ios")
    }

    @MainActor private func preferenceRows(batch: Bool, provider: String, skip: Bool, azure: Bool) async throws -> [[String: Any]] {
        let preferences = GoldenPreferences()
        if provider != "unset" { await preferences.setValue(provider, for: .llmProvider) }
        await preferences.setValue(skip, for: .llmSkipContentAnalysis)
        var environment: [String: String] = [:]
        if batch { environment["AZURE_TRANSCRIPTION_ENDPOINT"] = "https://example.invalid/audio"; environment["whisperkey"] = "fixture-speech" }
        if azure { environment["AZURE_FOUNDRY_ENDPOINT"] = "https://example.invalid"; environment["kimikey"] = "fixture-text" }
        let service = DefaultLLMService(azureFoundryConfig: ServiceContainer.makeAzureFoundryConfig(environment: environment))
        let notifications = NotificationCenter()
        #if os(iOS)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GoldenRouting-\(UUID().uuidString)"))
        let telemetryPreferences = ProductTelemetryPreferences(store: UserDefaultsPreferencesStore(defaults: defaults))
        let container = ServiceContainer(productTelemetryPreferences: telemetryPreferences,
                                         processEnvironment: environment, preferencesStore: preferences,
                                         llmServiceFactory: { service }, llmNotificationCenter: notifications,
                                         productTelemetryNotificationCenter: notifications, productTelemetryHostOverride: .test)
        await container.waitForPendingLLMPreferenceChanges()
        let coordinator = container.transcriber
        #else
        let binding = LLMPreferenceBinding(service: service, environment: environment, preferences: preferences, notificationCenter: notifications)
        await binding.waitForPendingChanges()
        let coordinator = ServiceContainer.makeIOSHybridTranscriber(environment: environment)
        #endif
        XCTAssertEqual(coordinator is HybridWhisperTranscriber, batch)
        XCTAssertEqual(service.currentProviderType, provider == "appleIntelligence" ? .appleIntelligence : .azureFoundry)
        let initial: [String: Any] = ["batch": batch, "provider": provider, "skip": skip, "azureText": azure]
        var rows = [preferenceRow(service, coordinator: coordinator, initial: initial, event: "initial")]
        for name in [PreferencesNotification.llmProviderDidChange, PreferencesNotification.llmAnalysisSettingsDidChange] {
            for mutation in ["valid", "invalid", "deleted"] {
                let providerChange = name == PreferencesNotification.llmProviderDidChange
                let previousProvider = service.currentProviderType
                try await mutate(preferences, providerChange: providerChange, mutation: mutation, skip: skip)
                notifications.post(name: name, object: nil)
                #if os(iOS)
                await container.waitForPendingLLMPreferenceChanges()
                #else
                await binding.waitForPendingChanges()
                #endif
                if providerChange {
                    XCTAssertEqual(service.currentProviderType, mutation == "valid" ? .appleIntelligence : previousProvider)
                } else { XCTAssertEqual(service.isContentAnalysisSkipped, mutation == "valid" ? !skip : false) }
                rows.append(preferenceRow(service, coordinator: coordinator, initial: initial,
                                          event: "\(providerChange ? "provider" : "analysis").\(mutation)"))
            }
        }
        return rows
    }

    private func mutate(_ preferences: GoldenPreferences, providerChange: Bool, mutation: String, skip: Bool) async throws {
        let key: PreferencesKey = providerChange ? .llmProvider : .llmSkipContentAnalysis
        if mutation == "deleted" { await preferences.removeValue(for: key) }
        else if providerChange { await preferences.setValue(mutation == "valid" ? "appleIntelligence" : "invalid", for: key) }
        else if mutation == "valid" { await preferences.setValue(!skip, for: key) }
        else { await preferences.setValue("not-a-bool", for: key) }
    }

    @MainActor private func preferenceRow(_ service: DefaultLLMService, coordinator: any TranscriptionCoordinator,
                                         initial: [String: Any], event: String) -> [String: Any] {
        let routing = service.resolvedAnalysisRouting.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue }
        XCTAssertEqual(routing["intent"], "appleIntelligence"); XCTAssertEqual(routing["tone"], "appleIntelligence")
        for step in ["entities", "tags", "params"] { XCTAssertEqual(routing[step], service.currentProviderType?.rawValue) }
        let hybrid = coordinator is HybridWhisperTranscriber
        let nodes = ["capture.microphone", "speech.apple"] + (hybrid ? ["speech.azure.batch"] : [])
        let pipeline: [String: Any] = ["speech": nodes, "realtime": false, "merger": false,
                                      "analysis": routing.mapValues { service.isContentAnalysisSkipped ? "skipped" : $0 },
                                      "refine": service.currentProviderType!.rawValue,
                                      "configFailure": service.currentProviderType == .azureFoundry && service.currentProvider?.isAvailable != true
                                        ? "textModelUnavailable" : "none"]
        return ["initial": initial, "event": event, "routing": routing, "skip": service.isContentAnalysisSkipped, "pipeline": pipeline]
    }
    #endif

    private func assertFixture(_ rows: [[String: Any]], name: String) throws {
        let payload: [String: Any] = ["schema": "golden-trace/v1", "kind": "routing", "traces": rows]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted])
        if let directory = ProcessInfo.processInfo.environment["VOX_GOLDEN_RECORD_DIR"] {
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".json"))
        }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary
        XCTAssertEqual(payload as NSDictionary, fixture)
    }
}

#if !VOX_ROUTING_HARNESS
private actor GoldenPreferences: PreferencesStore {
    private var values: [PreferencesKey: Data] = [:]
    func getValue<Value: Codable & Sendable>(for key: PreferencesKey) async -> Value? {
        values[key].flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
    func getValue<Value: Codable & Sendable>(for key: PreferencesKey, default defaultValue: Value) async -> Value {
        if let value: Value = await getValue(for: key) { return value }
        await setValue(defaultValue, for: key)
        return defaultValue
    }
    func setValue<Value: Codable & Sendable>(_ value: Value, for key: PreferencesKey) async {
        values[key] = try? JSONEncoder().encode(value)
    }
    func removeValue(for key: PreferencesKey) async { values.removeValue(forKey: key) }
}
#endif
