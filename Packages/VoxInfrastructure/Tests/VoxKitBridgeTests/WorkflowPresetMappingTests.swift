import XCTest
import Synchronization
import VoxCore
import VoxSpeech
import VoxLLM
import VoxRefine
import VoxWorkflow
import Preferences
@testable import VoxKitBridge

final class WorkflowPresetMappingTests: XCTestCase {
    func testWorkflowCoordinatorPreservesQuickRecordingReleaseCapability() async throws {
        let source = QuickReleaseProbeSource()
        let coordinator: any TranscriptionCoordinator = WorkflowTranscriptionCoordinator(source: source, preset: .default)
        let release = try XCTUnwrap(coordinator as? any QuickRecordingReleaseControlling)
        try release.prepareQuickRecording()
        let snapshot = try release.freezeQuickRecordingRelease()
        XCTAssertEqual(snapshot, source.snapshot)
        try await release.completeQuickRecordingRelease(snapshot)
        XCTAssertEqual(source.calls.withLock { $0 }, ["prepare", "freeze", "complete"])
        XCTAssertEqual(source.completed.withLock { $0 }, snapshot)
    }

    func testMappedHybridGraphsExecuteAppleAndCloudWithRealtimeFallback() async throws {
        for speech in [SpeechModelSelection.batch, .realtime] {
            for realtimeFails in [false, true] {
                let preset = StagePresetMapping.preset(settings: .init(speech: speech),
                    batchConfigured: true, realtimeConfigured: true, azureTextConfigured: true)
                let registry = NodeRegistry()
                let calls = MappingProbeCalls()
                for kind in [NodeKindID.captureMicrophone, .speechApple, .speechAzureRealtime, .speechAzureBatch] {
                    let signature = try XCTUnwrap(registry.signature(for: kind))
                    registry.register(signature, handler: MappingProbeHandler(calls: calls, realtimeFails: realtimeFails))
                }
                let events = try await WorkflowRuntime(registry: registry).execute(preset.speech)
                let executed = calls.values
                XCTAssertTrue(executed.contains(.captureMicrophone))
                XCTAssertTrue(executed.contains(.speechApple))
                XCTAssertEqual(executed.contains(.speechAzureRealtime), speech == .realtime)
                XCTAssertEqual(executed.filter { $0 == .speechAzureBatch }.count,
                    speech == .batch || realtimeFails ? 1 : 0)
                let expected = speech == .realtime && !realtimeFails ? "speech.azure.realtime" : "speech.azure.batch"
                XCTAssertTrue(events.contains { if case .final(let value) = $0 { value.text == expected } else { false } })
                XCTAssertFalse(preset.exportedPipeline().merger)
            }
        }
    }

    @MainActor
    func testCancelledPreferenceRefreshCannotOverwriteLatestPresetOrRunner() async {
        let store = SuspendedMappingPreferences()
        let runner = RefineWorkflowRunner()
        var updates = 0
        let binding = IOSPresetPreferenceBinding(batchConfigured: true, azureTextConfigured: true,
            preferences: store, notificationCenter: NotificationCenter(), onPresetChange: { preset in
                updates += 1
                runner.configure(preset: preset, configuration: WorkflowExecutionConfiguration(), azureTextConfigured: true)
            })
        let latestUpdate = Task { @MainActor in
            await store.waitForSuspendedRead()
            await store.setValue(LLMProviderType.azureFoundry.rawValue, for: .llmProvider)
            binding.refresh()
            await binding.waitForPendingChanges()
            XCTAssertEqual(binding.currentProvider, .azureFoundry)
            XCTAssertFalse(runner.isContentAnalysisSkipped)
            await store.releaseStaleRead()
        }
        await binding.waitForPendingChanges()
        await latestUpdate.value
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(binding.currentProvider, .azureFoundry)
        XCTAssertEqual(runner.currentProviderType, .azureFoundry)
        XCTAssertFalse(runner.isContentAnalysisSkipped)
        XCTAssertEqual(binding.preset, runner.activePreset)
    }

    func testStageMappingCoversSpeechAndAnalysisCombinations() {
        let speechSelections = SpeechModelSelection.allCases
        let textSelections = TextModelSelection.allCases
        for speech in speechSelections {
            for intent in textSelections {
                for tone in textSelections {
                    let settings = StageModelSettings(speech: speech, intent: intent, tone: tone,
                        refinement: .azureFoundry, skipAnalysis: true)
                    for batchConfigured in [false, true] {
                        for realtimeConfigured in [false, true] {
                            let pipeline = StagePresetMapping.exportedPipeline(settings: settings,
                                batchConfigured: batchConfigured, realtimeConfigured: realtimeConfigured,
                                azureTextConfigured: true)
                            let expectedSpeech: [String]
                            if speech == .appleSpeech || !batchConfigured {
                                expectedSpeech = ["capture.microphone", "speech.apple"]
                            } else if speech == .realtime && realtimeConfigured {
                                expectedSpeech = ["capture.microphone", "speech.apple", "speech.azure.realtime", "speech.azure.batch"]
                            } else {
                                expectedSpeech = ["capture.microphone", "speech.apple", "speech.azure.batch"]
                            }
                            XCTAssertEqual(pipeline.speech, expectedSpeech)
                            let expectedAnalysis = settings.skipAnalysis ? "skipped" : intent.rawValue
                            XCTAssertEqual(pipeline.analysis["intent"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["entities"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["tags"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["params"], expectedAnalysis)
                            XCTAssertEqual(pipeline.analysis["tone"], settings.skipAnalysis ? "skipped" : tone.rawValue)
                            XCTAssertEqual(pipeline.analysis["skip"], nil)
                            XCTAssertEqual(pipeline.refine, "azureFoundry")
                        }
                    }
                }
            }
        }
    }

    func testIOSMappingKeepsAzureProviderWhenTextConfigurationIsMissing() {
        let pipeline = IOSPresetMapping(batchConfigured: true, azureTextConfigured: false).exportedPipeline()
        XCTAssertEqual(pipeline.speech, ["capture.microphone", "speech.apple", "speech.azure.batch"])
        XCTAssertEqual(pipeline.refine, LLMProviderType.azureFoundry.rawValue)
        XCTAssertEqual(pipeline.configFailure, "textModelUnavailable")
        XCTAssertEqual(pipeline.analysis["intent"], LLMProviderType.appleIntelligence.rawValue)
        XCTAssertEqual(pipeline.analysis["tone"], LLMProviderType.appleIntelligence.rawValue)
        XCTAssertEqual(pipeline.analysis["entities"], LLMProviderType.azureFoundry.rawValue)
    }

    @MainActor
    func testIOSPreferenceBindingRetainsProviderForInvalidValuesAndReappliesAnalysis() async {
        let suite = "WorkflowPresetMappingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        let center = NotificationCenter()
        let runner = RefineWorkflowRunner(preset: .hybridAzure,
            configuration: WorkflowExecutionConfiguration(), azureTextConfigured: true)
        let binding = IOSPresetPreferenceBinding(batchConfigured: true, azureTextConfigured: true,
            preferences: store, notificationCenter: center,
            onPresetChange: { preset in
                runner.configure(preset: preset, configuration: WorkflowExecutionConfiguration(), azureTextConfigured: true)
            })

        await binding.waitForPendingChanges()
        XCTAssertEqual(binding.currentProvider, .azureFoundry)
        await store.setValue(LLMProviderType.appleIntelligence.rawValue, for: .llmProvider)
        await store.setValue(true, for: .llmSkipContentAnalysis)
        center.post(name: PreferencesNotification.llmAnalysisSettingsDidChange, object: nil)
        await binding.waitForPendingChanges()
        XCTAssertEqual(binding.currentProvider, .appleIntelligence)
        XCTAssertEqual(runner.currentProviderType, .appleIntelligence)
        let pipeline = binding.preset.exportedPipeline(batchConfigured: true, realtimeConfigured: false,
            azureTextConfigured: true)
        XCTAssertEqual(pipeline.analysis["entities"], "skipped")
        XCTAssertEqual(pipeline.analysis["intent"], "skipped")
        XCTAssertEqual(pipeline.analysis["tone"], "skipped")
        let entityNode = try! XCTUnwrap(binding.preset.refine.nodes.first { $0.id == "entities" })
        XCTAssertEqual(entityNode.params["analysis.entities.provider"], .string("appleIntelligence"))

        await store.setValue("invalid-provider", for: .llmProvider)
        center.post(name: PreferencesNotification.llmProviderDidChange, object: nil)
        await binding.waitForPendingChanges()
        XCTAssertEqual(binding.currentProvider, .appleIntelligence)
    }

    func testRunnerReportsUnavailableAzureConfigurationAndOwnsRuntimeState() async throws {
        let configuration = WorkflowExecutionConfiguration()
        let main = RefineWorkflowRunner(preset: .hybridAzure, configuration: configuration, azureTextConfigured: false)
        let quick = RefineWorkflowRunner(preset: .hybridAzure, configuration: configuration, azureTextConfigured: false)
        XCTAssertFalse(main.isConfigured)
        XCTAssertFalse(quick.isConfigured)
        XCTAssertNotIdentical(main, quick)
        do {
            _ = try await main.refine(RefinementRequest(text: "fixture"))
            XCTFail("Expected unavailable configuration")
        } catch let error as RefineWorkflowConfigurationError {
            XCTAssertEqual(error, .unavailable)
        }
    }
}

private struct MappingProbeHandler: WorkflowNodeHandler {
    let calls: MappingProbeCalls
    let realtimeFails: Bool

    func execute(context: WorkflowNodeContext) async throws -> WorkflowNodeValue {
        calls.append(context.node.kind)
        if context.node.kind == .speechAzureRealtime, realtimeFails { throw WorkflowRuntimeError.nodeFailed }
        if context.node.kind == .captureMicrophone { return .speechSession(MappingProbeSession()) }
        return .transcription(TranscriptionResult(text: context.node.kind.rawValue, type: .final))
    }
}

private final class MappingProbeCalls: Sendable {
    private let storage = Mutex<[NodeKindID]>([])
    func append(_ kind: NodeKindID) { storage.withLock { $0.append(kind) } }
    var values: [NodeKindID] { storage.withLock { $0 } }
}

private struct MappingProbeSession: SpeechSession {
    func events() -> AsyncThrowingStream<TranscriptionEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func pause() async {}
    func resume() async {}
    func stop() async {}
    func cancel() async {}
}

private final class QuickReleaseProbeSource: SpeechSessionSource, QuickRecordingReleaseControlling {
    let snapshot = QuickRecordingReleaseSnapshot(sessionID: UUID(), hasRecognizedSpeech: true)
    let calls = Mutex<[String]>([])
    let completed = Mutex<QuickRecordingReleaseSnapshot?>(nil)
    var supportedLanguages: [Locale] { [] }
    var providerKind: ASRProviderType { .custom }
    var isActive: Bool { false }
    var hasMicrophonePermission: Bool { true }
    var hasSpeechPermission: Bool { true }
    func requestMicrophonePermission() async -> Bool { true }
    func requestSpeechPermission() async -> Bool { true }
    func captureStates() -> AsyncStream<AudioCaptureState> { AsyncStream { $0.finish() } }
    func audioLevels() -> AsyncStream<Float> { AsyncStream { $0.finish() } }
    func startSession(language: Locale) async throws -> any SpeechSession { MappingProbeSession() }
    func prepareQuickRecording() throws { calls.withLock { $0.append("prepare") } }
    func freezeQuickRecordingRelease() throws -> QuickRecordingReleaseSnapshot {
        calls.withLock { $0.append("freeze") }
        return snapshot
    }
    func completeQuickRecordingRelease(_ snapshot: QuickRecordingReleaseSnapshot) async throws {
        calls.withLock { $0.append("complete") }
        completed.withLock { $0 = snapshot }
    }
}

private actor SuspendedMappingPreferences: PreferencesStore {
    private var provider = LLMProviderType.appleIntelligence.rawValue
    private var suspendNextSkip = true
    private var suspendedRead: CheckedContinuation<Bool, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func getValue<Value: Codable & Sendable>(for key: PreferencesKey) async -> Value? {
        key == .llmProvider ? provider as? Value : nil
    }

    func getValue<Value: Codable & Sendable>(for key: PreferencesKey, default defaultValue: Value) async -> Value {
        guard key == .llmSkipContentAnalysis else { return defaultValue }
        if suspendNextSkip {
            suspendNextSkip = false
            let skip = await withCheckedContinuation { continuation in
                suspendedRead = continuation
                observer?.resume()
                observer = nil
            }
            return (skip as? Value) ?? defaultValue
        }
        return (false as? Value) ?? defaultValue
    }

    func setValue<Value: Codable & Sendable>(_ value: Value, for key: PreferencesKey) async {
        if key == .llmProvider, let value = value as? String { provider = value }
    }

    func removeValue(for key: PreferencesKey) async {}

    func waitForSuspendedRead() async {
        if suspendedRead != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func releaseStaleRead() {
        suspendedRead?.resume(returning: true)
        suspendedRead = nil
    }
}
