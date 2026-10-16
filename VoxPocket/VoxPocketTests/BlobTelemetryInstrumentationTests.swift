import AppKit
import Combine
import CoreModels
import Foundation
import LLMKit
import LokiKit
import PlatformAdapters
import PlatformUI
import Preferences
import Synchronization
import Testing
import TranscriptionKit
import UIShared
import UseCases
@testable import VoxPocket

@MainActor
struct BlobTelemetryInstrumentationTests {
    @Test func productionSettingsAndActionBoundariesDriveRuntime() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        let center = NotificationCenter()
        let instrumentation = ProductTelemetryInstrumentation(
            runtime: fixture.makeRuntime(),
            notificationCenter: center
        )

        center.post(
            name: ProductTelemetrySettingsViewModel.consentDidChange,
            object: nil,
            userInfo: ["isConsented": true]
        )
        await Task.yield()
        await instrumentation.waitForPendingConsentChange()
        center.post(name: ProductTelemetrySettingsViewModel.settingsDidOpen, object: nil)
        ProductTelemetryNotificationBoundary.postFullPanelOpened(to: center)
        await Task.yield()
        center.post(
            name: ProductTelemetrySettingsViewModel.consentDidChange,
            object: nil,
            userInfo: ["isConsented": false]
        )
        await Task.yield()
        await instrumentation.waitForPendingConsentChange()
        ProductTelemetryNotificationBoundary.postFullPanelOpened(to: center)
        await Task.yield()

        #expect(fixture.recorder.events.compactMap { $0.properties["action"] } == [
            "settings_opened", "full_panel_opened"
        ])
        #expect(fixture.recorder.operations.contains("disable"))
    }

    @Test func productionSettingsOptOutCancelsSuspendedEnableBeforeRuntimeEntry() async {
        let persistenceGate = ConsentPersistenceGate(consent: true, entry: 1)
        let fixture = RuntimeFixture(productTelemetryConsentWriteGate: persistenceGate.suspend)
        defer { fixture.remove() }
        let center = NotificationCenter()
        let instrumentation = ProductTelemetryInstrumentation(
            runtime: fixture.makeRuntime(),
            notificationCenter: center
        )
        let model = ProductTelemetrySettingsViewModel(
            preferences: fixture.preferences,
            notificationCenter: center
        )

        let enable = Task { await model.setSendingUsageData(true) }
        await persistenceGate.waitUntilSuspended()
        let optOut = Task { await model.setSendingUsageData(false) }
        await Task.yield()
        await Task.yield()

        center.post(name: ProductTelemetrySettingsViewModel.settingsDidOpen, object: nil)
        ProductTelemetryNotificationBoundary.postFullPanelOpened(to: center)
        await instrumentation.applicationWillResignActive()
        #expect(fixture.recorder.operations.isEmpty)

        await persistenceGate.release()
        await enable.value
        await optOut.value
        await instrumentation.waitForPendingConsentChange()

        #expect(!model.isSendingUsageData)
        #expect(await fixture.preferences.isConsented == false)
        #expect(fixture.recorder.constructionCount == 0)
        #expect(fixture.recorder.events.isEmpty)
        #expect(fixture.recorder.operations.isEmpty)
    }

    @Test func productionQuickRecordBoundariesPreserveNormalAndRapidReleaseOrder() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        _ = await fixture.preferences.setConsent(true)
        let center = NotificationCenter()
        let instrumentation = ProductTelemetryInstrumentation(
            runtime: fixture.makeRuntime(),
            notificationCenter: center
        )
        await instrumentation.completeStartup(startedAt: .now)
        let normal = QuickRecordFixture()
        let normalDelegate = AppDelegate(
            productTelemetryNotificationCenter: center,
            quickRecordTryStart: normal.tryStart,
            quickRecordActiveSource: normal.activeSource,
            quickRecordEnd: normal.end,
            quickRecordShowWindow: normal.show,
            quickRecordViewModel: normal.getViewModel,
            quickRecordHideWindow: normal.hide
        )
        await normalDelegate.enterQuickRecordStart()
        #expect(normal.recording.startCallCount == 1)
        #expect(normal.viewModel.recorderStatus == .listening)
        await normalDelegate.enterQuickRecordStop()
        await Task.yield()
        #expect(normal.recording.stopCallCount == 1)
        #expect(normal.operations.first == "claim")
        #expect(normal.operations.contains("show"))
        #expect(normal.operations.contains("stop"))
        #expect(normal.operations.contains("hide"))
        #expect(normal.operations.contains("end"))

        let failing = QuickRecordFixture(startError: QuickRecordFixture.StartError.synthetic)
        let errorDelegate = AppDelegate(
            productTelemetryNotificationCenter: center,
            quickRecordTryStart: failing.tryStart,
            quickRecordActiveSource: failing.activeSource,
            quickRecordEnd: failing.end,
            quickRecordShowWindow: failing.show,
            quickRecordViewModel: failing.getViewModel,
            quickRecordHideWindow: failing.hide
        )
        await errorDelegate.enterQuickRecordStart()
        #expect(failing.recording.startCallCount == 1)
        #expect(failing.viewModel.recorderStatus == .error)

        let startGate = QuickRecordStartGate()
        let rapid = QuickRecordFixture(startGate: startGate)
        let rapidReleaseDelegate = AppDelegate(
            productTelemetryNotificationCenter: center,
            quickRecordTryStart: rapid.tryStart,
            quickRecordActiveSource: rapid.activeSource,
            quickRecordEnd: rapid.end,
            quickRecordShowWindow: rapid.show,
            quickRecordViewModel: rapid.getViewModel,
            quickRecordHideWindow: rapid.hide
        )
        let startTask = Task { await rapidReleaseDelegate.enterQuickRecordStart() }
        await startGate.waitUntilEntered()
        #expect(rapid.viewModel.isStartingRecording)
        await rapidReleaseDelegate.enterQuickRecordStop()
        #expect(rapid.recording.stopCallCount == 0)
        await startGate.release()
        await startTask.value
        await Task.yield()
        #expect(rapid.recording.startCallCount == 1)
        #expect(rapid.recording.stopCallCount == 1)
        #expect(rapid.operations.starts(with: ["claim", "show", "get", "get"]))

        #expect(fixture.recorder.events.compactMap { $0.properties["action"] } == [
            "quick_record_started", "quick_record_stopped",
            "quick_record_started", "quick_record_stopped"
        ])
    }

    @Test func productionLifecycleBoundariesFlushStartupRecordingSessionAndResignActive() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        _ = await fixture.preferences.setConsent(true)
        let container = fixture.makeContainer()
        let startup = AppStartup {}
        let delegate = AppDelegate(
            productTelemetryNotificationCenter: NotificationCenter(),
            startup: startup,
            serviceContainer: container,
            hotkeyService: TestGlobalHotkeyService(),
            startupInitializePersistence: {},
            startupScheduleQuickRecordingPrewarm: {}
        )
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await delegate.waitForPendingStartup()
        #expect(fixture.recorder.operations.filter { $0 == "flush" }.count == 1)

        #expect(container.tryStartRecording(source: .quickRecording))
        container.endRecording()
        await container.waitForPendingProductTelemetryRecordingCompletion()
        #expect(fixture.recorder.operations.filter { $0 == "flush" }.count == 2)
        _ = try? await container.sessionUseCase.saveCompletedSession(
            title: nil,
            rawText: "synthetic raw",
            refinedText: "synthetic refined"
        )
        #expect(fixture.recorder.operations.filter { $0 == "flush" }.count == 3)
        delegate.applicationWillResignActive(
            Notification(name: Notification.Name("test.applicationWillResignActive"))
        )
        await delegate.waitForPendingProductTelemetryResignActive()

        #expect(fixture.recorder.operations.filter { $0 == "flush" }.count == 4)
    }

    @Test func suspendedPersistenceCannotPrecedeInteractiveTelemetryActivation() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        _ = await fixture.preferences.setConsent(true)
        let container = fixture.makeContainer()
        let persistenceGate = QuickRecordStartGate()
        let delegate = AppDelegate(
            productTelemetryNotificationCenter: NotificationCenter(),
            startup: AppStartup {},
            serviceContainer: container,
            hotkeyService: TestGlobalHotkeyService(),
            startupInitializePersistence: persistenceGate.suspendStart,
            startupScheduleQuickRecordingPrewarm: {}
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await persistenceGate.waitUntilEntered()

        container.recordProductAction(.settingsOpened)
        await container.productTelemetryApplicationWillResignActive()

        #expect(fixture.recorder.events.map(\.name) == [
            "product.performance", "product.user_action"
        ])
        #expect(fixture.recorder.events.last?.properties["action"] == "settings_opened")
        #expect(fixture.recorder.operations == [
            "construct", "track product.performance", "flush",
            "track product.user_action", "flush"
        ])

        await persistenceGate.release()
        await delegate.waitForPendingStartup()
    }

    @Test func overlappingProductionSettingsChoicesSupersedeDelayedStartupAndAllComplete() async {
        let activationGate = ActivationBootstrapGate()
        let disableGate = TelemetryOperationGate(operation: "disable")
        let fixture = RuntimeFixture(telemetryOperationObserver: { operation in
            Task { await disableGate.observe(operation) }
        })
        defer { fixture.remove() }
        _ = await fixture.preferences.setConsent(true)
        let center = NotificationCenter()
        let notificationGate = ConsentNotificationGate(notificationCenter: center)
        defer { notificationGate.remove() }
        let container = fixture.makeContainer(activationCheckpoint: activationGate.suspendFirst)
        let delegate = AppDelegate(
            productTelemetryNotificationCenter: center,
            startup: AppStartup {},
            serviceContainer: container,
            hotkeyService: TestGlobalHotkeyService(),
            startupInitializePersistence: {},
            startupScheduleQuickRecordingPrewarm: {}
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await activationGate.waitUntilSuspended()

        let model = ProductTelemetrySettingsViewModel(
            preferences: fixture.preferences,
            notificationCenter: center
        )
        let optOut = Task { await model.setSendingUsageData(false) }
        await disableGate.waitUntilObserved()
        #expect(fixture.recorder.operations == ["construct", "disable"])

        let optIn = Task { await model.setSendingUsageData(true) }
        await notificationGate.waitUntilOptInPosted()
        await optOut.value
        await optIn.value
        await container.waitForPendingProductTelemetryConsentChange()

        container.recordProductAction(.settingsOpened)
        await container.productTelemetryApplicationWillResignActive()

        #expect(model.isSendingUsageData)
        #expect(await fixture.preferences.isConsented)
        #expect(fixture.recorder.constructionCount == 1)
        #expect(fixture.identities.count == 2)
        #expect(Set(fixture.identities).count == 1)
        #expect(fixture.recorder.events.compactMap { $0.properties["action"] } == ["settings_opened"])
        #expect(fixture.recorder.operations == [
            "construct", "disable", "enable", "track product.user_action", "flush"
        ])

        await activationGate.release()
        await delegate.waitForPendingStartup()

        #expect(fixture.recorder.operations == [
            "construct", "disable", "enable", "track product.user_action", "flush"
        ])
    }

    @Test func startupAndActionsEmitOnlyAfterSuccessfulComposition() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        let runtime = fixture.makeRuntime()

        runtime.record(.settingsOpened)
        await runtime.completeStartup(startedAt: .now)
        #expect(fixture.recorder.operations.isEmpty)

        await runtime.setConsent(true)
        runtime.record(.settingsOpened)
        runtime.record(.fullPanelOpened)
        runtime.record(.quickRecordStarted)
        runtime.record(.quickRecordStopped)
        await runtime.flush()

        let events = fixture.recorder.events
        #expect(events.map(\.name) == [
            "product.user_action", "product.user_action",
            "product.user_action", "product.user_action"
        ])
        #expect(events.map { $0.properties["action"] } == [
            "settings_opened", "full_panel_opened",
            "quick_record_started", "quick_record_stopped"
        ])
        #expect(fixture.recorder.operations.last == "flush")
    }

    @Test func consentedStartupRecordsBoundedLaunchDurationThenFlushes() async throws {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        _ = await fixture.preferences.setConsent(true)
        let runtime = fixture.makeRuntime()

        await runtime.completeStartup(startedAt: .now)

        let event = try #require(fixture.recorder.events.first)
        #expect(event.name == "product.performance")
        #expect(event.properties["operation"] == "app_launch")
        let duration = try #require(Double(event.properties["duration_ms"] ?? ""))
        #expect((0...3_600_000).contains(duration))
        #expect(fixture.recorder.operations == ["construct", "track product.performance", "flush"])
    }

    @Test func disableStopsAdmissionUntilExplicitReenable() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        let runtime = fixture.makeRuntime()

        await runtime.setConsent(true)
        runtime.record(.quickRecordStarted)
        await runtime.setConsent(false)
        runtime.record(.quickRecordStopped)
        await runtime.setConsent(true)
        runtime.record(.quickRecordStopped)
        await runtime.flush()

        #expect(fixture.recorder.constructionCount == 1)
        #expect(fixture.recorder.events.compactMap { $0.properties["action"] } == [
            "quick_record_started", "quick_record_stopped"
        ])
        #expect(fixture.identities.count == 2)
        #expect(Set(fixture.identities).count == 1)
    }
}

@MainActor
private final class ConsentNotificationGate {
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private var optInPosted = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: ProductTelemetrySettingsViewModel.consentDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard notification.userInfo?["isConsented"] as? Bool == true else { return }
                self?.optInPosted = true
                self?.waiter?.resume()
                self?.waiter = nil
            }
        }
    }

    func waitUntilOptInPosted() async {
        guard !optInPosted else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func remove() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}

@MainActor
private final class QuickRecordFixture {
    enum StartError: Error { case synthetic }

    let recording: QuickRecordRecordingUseCase
    let viewModel: QuickRecordingViewModel
    private(set) var source: RecordingSource?
    private(set) var operations: [String] = []

    init(startError: Error? = nil, startGate: QuickRecordStartGate? = nil) {
        recording = QuickRecordRecordingUseCase(startError: startError, startGate: startGate)
        viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: QuickRecordTranscriptionUseCase(),
            refinementUseCase: QuickRecordRefinementUseCase(),
            clipboardService: QuickRecordClipboardService()
        )
    }

    func tryStart(_ requestedSource: RecordingSource) -> Bool {
        operations.append("claim")
        guard source == nil else { return false }
        source = requestedSource
        return true
    }

    func activeSource() -> RecordingSource? {
        operations.append("active")
        return source
    }

    func end() {
        operations.append("end")
        source = nil
    }

    func show() {
        operations.append("show")
    }

    func getViewModel() -> QuickRecordingViewModel? {
        operations.append("get")
        return viewModel
    }

    func hide() {
        operations.append("hide")
    }
}

private actor QuickRecordStartGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func suspendStart() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor ConsentPersistenceGate {
    private let consent: Bool
    private let targetEntry: Int
    private var entryCount = 0
    private var suspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    init(consent: Bool, entry: Int) {
        self.consent = consent
        targetEntry = entry
    }

    func suspend(_ consent: Bool) async {
        guard consent == self.consent else { return }
        entryCount += 1
        guard entryCount == targetEntry else { return }
        suspended = true
        suspensionWaiter?.resume()
        suspensionWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilSuspended() async {
        guard !suspended else { return }
        await withCheckedContinuation { suspensionWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor ActivationBootstrapGate {
    private var entryCount = 0
    private var suspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func suspendFirst() async {
        entryCount += 1
        guard entryCount == 1 else { return }
        suspended = true
        suspensionWaiter?.resume()
        suspensionWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilSuspended() async {
        guard !suspended else { return }
        await withCheckedContinuation { suspensionWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor TelemetryOperationGate {
    private let operation: String
    private var observed = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(operation: String) {
        self.operation = operation
    }

    func observe(_ operation: String) {
        guard operation == self.operation else { return }
        observed = true
        waiter?.resume()
        waiter = nil
    }

    func waitUntilObserved() async {
        guard !observed else { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private final class QuickRecordRecordingUseCase: RecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let levelSubject = CurrentValueSubject<Float, Never>(0)
    private let startError: Error?
    private let startGate: QuickRecordStartGate?
    private let counts = Mutex((start: 0, stop: 0))

    init(startError: Error?, startGate: QuickRecordStartGate?) {
        self.startError = startError
        self.startGate = startGate
    }

    var startCallCount: Int { counts.withLock { $0.start } }
    var stopCallCount: Int { counts.withLock { $0.stop } }
    var state: RecordingState { stateSubject.value }
    var statePublisher: AnyPublisher<RecordingState, Never> { stateSubject.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    func startRecording() async throws {
        counts.withLock { $0.start += 1 }
        if let startGate { await startGate.suspendStart() }
        if let startError { throw startError }
        stateSubject.send(.recording(duration: 0))
    }

    func stopRecording() async throws {
        counts.withLock { $0.stop += 1 }
        stateSubject.send(.idle)
    }

    func pauseRecording() { stateSubject.send(.paused(duration: 0)) }
    func resumeRecording() { stateSubject.send(.recording(duration: 0)) }
    func cancelRecording() { stateSubject.send(.idle) }
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

private final class QuickRecordTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private let liveText = CurrentValueSubject<String, Never>("")
    private let finalResult = PassthroughSubject<TranscriptionResult, Error>()
    private let snapshots = PassthroughSubject<String, Never>()
    private var language = Locale(identifier: "zh-Hans")

    var liveTextPublisher: AnyPublisher<String, Never> { liveText.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { finalResult.eraseToAnyPublisher() }
    var currentLanguage: Locale { language }
    var supportedLanguages: [Locale] { [language] }
    var snapshotPublisher: AnyPublisher<String, Never> { snapshots.eraseToAnyPublisher() }
    var snapshotGateActive = false

    func setLanguage(_ locale: Locale) { language = locale }
    func commitCurrentTranscription() async throws {}
    func clearLiveText() { liveText.send("") }
}

private final class QuickRecordRefinementUseCase: RefinementUseCase, @unchecked Sendable {
    private let subject = CurrentValueSubject<RefinementState, Never>(.idle)
    var state: RefinementState { subject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { subject.eraseToAnyPublisher() }
    var isConfigured: Bool { true }
    func refine(customPrompt: String?) async throws {}
    func refineSelection(range: NSRange, customPrompt: String?) async throws {}
    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        refineStreaming(customPrompt: customPrompt, transcriptionMetadata: nil)
    }
    func refineStreaming(
        customPrompt: String?,
        transcriptionMetadata: TranscriptionMetadata?
    ) -> AsyncThrowingStream<RefinementEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func cancel() {}
    func refineText(_ text: String, customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private final class QuickRecordClipboardService: ClipboardService, @unchecked Sendable {
    var hasText: Bool { false }
    func copy(_ text: String) {}
    func paste() -> String? { nil }
    func clear() {}
    func simulatePaste() async throws {}
}

@MainActor
private final class TestGlobalHotkeyService: GlobalHotkeyService {
    var hotkeyTriggeredPublisher: AnyPublisher<String, Never> {
        Empty().eraseToAnyPublisher()
    }
    func register(_ hotkey: HotkeyDefinition, handler: @escaping @Sendable () -> Void) throws {}
    func unregister(_ identifier: String) {}
    func unregisterAll() {}
    func update(_ identifier: String, to newHotkey: HotkeyDefinition) throws {}
    func getRegistered(_ identifier: String) -> HotkeyDefinition? { nil }
    func isAvailable(_ hotkey: HotkeyDefinition) -> Bool { true }
    func registerLongPress(
        _ hotkey: HotkeyDefinition,
        onPress: @escaping @concurrent @Sendable () async -> Void,
        onRelease: @escaping @concurrent @Sendable () async -> Void
    ) {}
}

@MainActor
private final class RuntimeFixture {
    let suite = "BlobTelemetryInstrumentationTests.\(UUID())"
    let store: UserDefaultsPreferencesStore
    let preferences: ProductTelemetryPreferences
    let recorder: RuntimeTelemetryRecorder
    private let recordedIdentities = Mutex<[UUID]>([])

    init(
        productTelemetryConsentWriteGate: (@Sendable (Bool) async -> Void)? = nil,
        telemetryOperationObserver: (@Sendable (String) -> Void)? = nil
    ) {
        recorder = RuntimeTelemetryRecorder(operationObserver: telemetryOperationObserver)
        let defaults = UserDefaults(suiteName: suite)!
        if let productTelemetryConsentWriteGate {
            store = UserDefaultsPreferencesStore(
                defaults: defaults,
                productTelemetryConsentWriteGate: productTelemetryConsentWriteGate
            )
        } else {
            store = UserDefaultsPreferencesStore(defaults: defaults)
        }
        preferences = ProductTelemetryPreferences(store: store)
    }

    var identities: [UUID] { recordedIdentities.withLock { $0 } }

    func makeRuntime(host: BlobTelemetryHostKind = .interactiveApplication) -> ProductTelemetryRuntime {
        let coordinator = TelemetryLifecycleCoordinator(isEnabled: false) { NoopTelemetryService() }
        return ProductTelemetryRuntime(
            coordinator: coordinator,
            preferences: preferences,
            host: host,
            configuration: { .enabled(.init(
                endpoint: URL(string: "https://telemetry.example.invalid/container")!,
                sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
            )) },
            makeBootstrap: { [self] identity in
                recordedIdentities.withLock { $0.append(identity) }
                return .testing(
                    configuration: .enabled(.init(
                        endpoint: URL(string: "https://telemetry.example.invalid/container")!,
                        sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
                    )),
                    host: host,
                    isConsented: true,
                    makeService: { recorder.construct() }
                )
            }
        )
    }

    func makeContainer(
        activationCheckpoint: ProductTelemetryRuntime.ActivationCheckpoint? = nil
    ) -> ServiceContainer {
        ServiceContainer(
            productTelemetryPreferences: preferences,
            processEnvironment: [:],
            processArguments: [],
            productTelemetryConfiguration: { .enabled(.init(
                endpoint: URL(string: "https://telemetry.example.invalid/container")!,
                sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
            )) },
            productTelemetryBootstrapFactory: { [self] identity in
                recordedIdentities.withLock { $0.append(identity) }
                return .testing(
                    configuration: .enabled(.init(
                        endpoint: URL(string: "https://telemetry.example.invalid/container")!,
                        sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
                    )),
                    host: .interactiveApplication,
                    isConsented: true,
                    makeService: { recorder.construct() }
                )
            },
            productTelemetryActivationCheckpoint: activationCheckpoint
        )
    }

    func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

private final class RuntimeTelemetryRecorder: Sendable {
    private struct State: Sendable {
        var constructionCount = 0
        var operations: [String] = []
        var events: [TelemetryEvent] = []
    }
    private let state = Mutex(State())
    private let operationObserver: (@Sendable (String) -> Void)?

    init(operationObserver: (@Sendable (String) -> Void)? = nil) {
        self.operationObserver = operationObserver
    }

    var constructionCount: Int { state.withLock { $0.constructionCount } }
    var operations: [String] { state.withLock { $0.operations } }
    var events: [TelemetryEvent] { state.withLock { $0.events } }

    func construct() -> any TelemetryService {
        state.withLock {
            $0.constructionCount += 1
            $0.operations.append("construct")
        }
        return RuntimeTelemetryService(recorder: self)
    }

    func track(_ event: TelemetryEvent) {
        state.withLock {
            $0.events.append(event)
            $0.operations.append("track \(event.name)")
        }
    }

    func flush() {
        state.withLock { $0.operations.append("flush") }
    }

    func setEnabled(_ value: Bool) {
        let operation = value ? "enable" : "disable"
        state.withLock { $0.operations.append(operation) }
        operationObserver?(operation)
    }
}

private final class RuntimeTelemetryService: TelemetryService, Sendable {
    private let recorder: RuntimeTelemetryRecorder
    private let enabled = Mutex(true)

    init(recorder: RuntimeTelemetryRecorder) {
        self.recorder = recorder
    }

    var isEnabled: Bool {
        get { enabled.withLock { $0 } }
        set {
            enabled.withLock { $0 = newValue }
            recorder.setEnabled(newValue)
        }
    }

    func track(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        recorder.track(event)
    }

    func track(name: String, properties: [String: String]) {
        track(TelemetryEvent(name: name, properties: properties))
    }

    func flush() async {
        guard isEnabled else { return }
        recorder.flush()
    }

    func resetIdentifier() {}
}
