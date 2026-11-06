import VoxRefine
import VoxKitBridge
import VoxCore
import Foundation
import CoreFoundation
import XCTest
import Preferences
import VoxSpeech
import VoxLLM
import VoxWorkflow
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
        let availability = StageModelRouting.availability(environment: environment)
        let realtimeConfigured = LLMAppConfig.realtimeTranscriptionConfig(environment: environment) != nil
        let preset = StagePresetMapping.preset(settings: settings,
            batchConfigured: availability.batchConfigured,
            realtimeConfigured: realtimeConfigured,
            azureTextConfigured: availability.textConfigured)
        let runner = RefineWorkflowRunner(preset: preset,
            configuration: WorkflowExecutionConfiguration(),
            azureTextConfigured: availability.textConfigured)
        let snapshot = preset.exportedPipeline(batchConfigured: availability.batchConfigured,
            realtimeConfigured: realtimeConfigured, azureTextConfigured: availability.textConfigured)
        if !runner.isConfigured {
            do {
                _ = try await runner.refine(.init(text: "synthetic input"))
                XCTFail("Unconfigured Azure must fail before invoking a provider")
            } catch RefineWorkflowConfigurationError.unavailable {}
        }
        let pipeline = pipelineDictionary(snapshot)
        return ["settings": ["speech": settings.speech.rawValue, "intent": settings.intent.rawValue,
                             "tone": settings.tone.rawValue, "refinement": settings.refinement.rawValue, "skip": settings.skipAnalysis],
                "configuration": config, "pipeline": pipeline]
    }

    private func pipelineDictionary(_ snapshot: WorkflowPipelineSnapshot) -> [String: Any] {
        ["speech": snapshot.speech, "realtime": snapshot.realtime, "merger": snapshot.merger,
         "analysis": snapshot.analysis, "refine": snapshot.refine, "configFailure": snapshot.configFailure]
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
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        for batch in [false, true] {
            for realtime in [false, true] {
                var environment = ["AZURE_OPENAI_ENDPOINT": "https://example.invalid", "whisperkey": "fixture-speech"]
                if !batch { environment["AZURE_TRANSCRIPTION_ENDPOINT"] = "invalid" }
                if realtime { environment["AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT"] = "example-live" }
                let coordinator = ServiceContainer.makeIOSHybridTranscriber(environment: environment)
                XCTAssertEqual(coordinator.core is HybridWhisperTranscriber, batch)
                let configuredRealtime = try receivedRealtimeConfiguration(coordinator)
                XCTAssertEqual(configuredRealtime, batch && LLMAppConfig.realtimeTranscriptionConfig(environment: environment) != nil)
                rows.append(["platform": platform, "configuration": ["batch": batch, "realtime": realtime],
                             "pipeline": speechPipeline(coordinator, realtime: configuredRealtime)])
            }
        }
        XCTAssertEqual(rows.count, 228)
        try assertFixture(rows, name: "golden_b_ios", platform: platform)
    }

    @MainActor private func preferenceRows(batch: Bool, provider: String, skip: Bool, azure: Bool) async throws -> [[String: Any]] {
        let preferences = GoldenPreferences()
        if provider != "unset" { await preferences.setValue(provider, for: .llmProvider) }
        await preferences.setValue(skip, for: .llmSkipContentAnalysis)
        var environment: [String: String] = [:]
        if batch { environment["AZURE_TRANSCRIPTION_ENDPOINT"] = "https://example.invalid/audio"; environment["whisperkey"] = "fixture-speech" }
        if azure { environment["AZURE_FOUNDRY_ENDPOINT"] = "https://example.invalid"; environment["kimikey"] = "fixture-text" }
        let notifications = NotificationCenter()
        let binding = IOSPresetPreferenceBinding(batchConfigured: batch, azureTextConfigured: azure,
            preferences: preferences, notificationCenter: notifications)
        await binding.waitForPendingChanges()
        let runner = RefineWorkflowRunner(preset: binding.preset,
            configuration: WorkflowExecutionConfiguration(azureFoundryConfig: ServiceContainer.makeAzureFoundryConfig(environment: environment)),
            azureTextConfigured: azure)
        let coordinator = ServiceContainer.makeIOSHybridTranscriber(environment: environment)
        XCTAssertEqual(coordinator.core is HybridWhisperTranscriber, batch)
        let realtime = try receivedRealtimeConfiguration(coordinator)
        XCTAssertEqual(realtime, batch && LLMAppConfig.realtimeTranscriptionConfig(environment: environment) != nil)
        XCTAssertEqual(runner.currentProviderType, provider == "appleIntelligence" ? .appleIntelligence : .azureFoundry)
        let initial: [String: Any] = ["batch": batch, "provider": provider, "skip": skip, "azureText": azure]
        var rows = [preferenceRow(runner, batch: batch, azureTextConfigured: azure, initial: initial, event: "initial")]
        for name in [PreferencesNotification.llmProviderDidChange, PreferencesNotification.llmAnalysisSettingsDidChange] {
            for mutation in ["valid", "invalid", "deleted"] {
                let providerChange = name == PreferencesNotification.llmProviderDidChange
                let previousProvider = runner.currentProviderType
                try await mutate(preferences, providerChange: providerChange, mutation: mutation, skip: skip)
                notifications.post(name: name, object: nil)
                await binding.waitForPendingChanges()
                runner.configure(preset: binding.preset,
                    configuration: WorkflowExecutionConfiguration(azureFoundryConfig: ServiceContainer.makeAzureFoundryConfig(environment: environment)),
                    azureTextConfigured: azure)
                if providerChange {
                    XCTAssertEqual(runner.currentProviderType, mutation == "valid" ? .appleIntelligence : previousProvider)
                } else { XCTAssertEqual(runner.isContentAnalysisSkipped, mutation == "valid" ? !skip : false) }
                rows.append(preferenceRow(runner, batch: batch, azureTextConfigured: azure, initial: initial,
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

    private func receivedRealtimeConfiguration(_ coordinator: any TranscriptionCoordinator) throws -> Bool {
        guard let workflow = coordinator as? WorkflowTranscriptionCoordinator,
              let hybrid = workflow.core as? HybridWhisperTranscriber else { return false }
        let configuration = try XCTUnwrap(Mirror(reflecting: hybrid).children.first { $0.label == "realtimeConfig" })
        return configuration.value as? AzureRealtimeTranscriptionConfig != nil
    }

    private func speechPipeline(_ coordinator: any TranscriptionCoordinator, realtime: Bool) -> [String: Any] {
        var nodes = ["capture.microphone", "speech.apple"]
        if realtime { nodes.append("speech.azure.realtime") }
        if (coordinator as? WorkflowTranscriptionCoordinator)?.core is HybridWhisperTranscriber { nodes.append("speech.azure.batch") }
        return ["speech": nodes, "realtime": realtime,
                "merger": (coordinator as? any MultiRecognizerTranscriber)?.merger != nil]
    }

    @MainActor private func preferenceRow(_ runner: RefineWorkflowRunner, batch: Bool, azureTextConfigured: Bool,
                                         initial: [String: Any], event: String) -> [String: Any] {
        let routing = runner.resolvedAnalysisRouting.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue }
        XCTAssertEqual(routing["intent"], "appleIntelligence"); XCTAssertEqual(routing["tone"], "appleIntelligence")
        for step in ["entities", "tags", "params"] { XCTAssertEqual(routing[step], runner.currentProviderType?.rawValue) }
        let snapshot = runner.activePreset.exportedPipeline(batchConfigured: batch, realtimeConfigured: false,
            azureTextConfigured: azureTextConfigured)
        return ["initial": initial, "event": event, "routing": routing, "skip": runner.isContentAnalysisSkipped,
                "pipeline": pipelineDictionary(snapshot)]
    }
    #endif

    private func assertFixture(_ rows: [[String: Any]], name: String, platform: String? = nil) throws {
        let payload: [String: Any] = ["schema": "golden-trace/v1", "kind": "routing", "traces": rows]
        let data = try GoldenFixtureCodec.encode(payload)
        if let directory = ProcessInfo.processInfo.environment["VOX_GOLDEN_RECORD_DIR"] {
            let filename = name + (platform.map { "-" + $0 } ?? "") + ".json"
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(filename))
        }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        var fixture = try GoldenFixtureCodec.decode(Data(contentsOf: url)) as! [String: Any]
        if let platform {
            let traces = try XCTUnwrap(fixture["traces"] as? [[String: Any]])
            XCTAssertEqual(traces.count, 232)
            fixture["traces"] = traces.filter { $0["platform"] == nil || $0["platform"] as? String == platform }
        }
        XCTAssertEqual(payload as NSDictionary, fixture as NSDictionary)
    }
}

private enum GoldenFixtureCodec {
    static func encode(_ payload: [String: Any]) throws -> Data {
        var values: [Any] = []
        var indices: [Data: Int] = [:]
        func intern(_ value: Any) throws -> Int {
            let node: Any
            if let object = value as? [String: Any] {
                var references: [String: Int] = [:]
                for key in object.keys.sorted() { references[key] = try intern(object[key]!) }
                node = references
            } else if let array = value as? [Any] {
                node = try array.map(intern)
            } else {
                node = value
            }
            let key = try JSONSerialization.data(withJSONObject: node, options: [.sortedKeys, .fragmentsAllowed])
            if let index = indices[key] { return index }
            let index = values.count
            values.append(node)
            indices[key] = index
            return index
        }
        let root = try intern(payload)
        return try JSONSerialization.data(withJSONObject: [
            "schema": "golden-trace/v1", "encoding": "interned-values/v1", "root": root, "values": values
        ], options: [.sortedKeys])
    }

    static func decode(_ data: Data) throws -> NSDictionary {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["schema"] as? String == "golden-trace/v1" else { throw CocoaError(.coderReadCorrupt) }
        guard envelope["encoding"] != nil else { return envelope as NSDictionary }
        guard envelope["encoding"] as? String == "interned-values/v1",
              let values = envelope["values"] as? [Any], let root = envelope["root"] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var expanded: [Any] = []
        func resolve(_ reference: Any) throws -> Any {
            guard let number = reference as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let index = reference as? Int, expanded.indices.contains(index) else {
                throw CocoaError(.coderReadCorrupt)
            }
            return expanded[index]
        }
        for node in values {
            let value: Any
            if let object = node as? [String: Any] {
                value = try object.mapValues(resolve)
            } else if let array = node as? [Any] {
                value = try array.map(resolve)
            } else {
                value = node
            }
            expanded.append(value)
        }
        guard let payload = try resolve(root) as? NSDictionary else { throw CocoaError(.coderReadCorrupt) }
        return payload
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
