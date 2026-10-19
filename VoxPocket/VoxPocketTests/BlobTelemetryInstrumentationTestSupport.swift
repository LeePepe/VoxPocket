#if os(macOS)
import AppKit
import Combine
import CoreModels
import Foundation
import LLMKit
import LokiKit
import PlatformAdapters
import Preferences
import Synchronization
import TranscriptionKit
import UIShared
import UseCases
@testable import VoxPocket

actor QuickRecordStartGate {
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

actor TelemetryFlushGate {
    private let targetEntry: Int
    private var entryCount = 0
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var targetEntered = false
    private var released = false

    init(targetEntry: Int) {
        self.targetEntry = targetEntry
    }

    func suspendTarget() async {
        entryCount += 1
        guard entryCount == targetEntry else { return }
        targetEntered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !targetEntered else { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

final class QuickRecordOperationRecorder: Sendable {
    private struct State: Sendable {
        var operations: [String] = []
        var cleanupOperations: Set<String> = []
        var didSignalCleanup = false
    }

    private let state = Mutex(State())
    private let cleanupCompletion: AsyncStream<Void>
    private let cleanupContinuation: AsyncStream<Void>.Continuation

    init() {
        (cleanupCompletion, cleanupContinuation) = AsyncStream<Void>.makeStream()
    }

    var operations: [String] { state.withLock { $0.operations } }

    func record(_ operation: String) {
        let shouldSignal = state.withLock { state in
            state.operations.append(operation)
            guard operation == "hide" || operation == "end" else { return false }
            state.cleanupOperations.insert(operation)
            guard state.cleanupOperations.count == 2, !state.didSignalCleanup else { return false }
            state.didSignalCleanup = true
            return true
        }
        if shouldSignal {
            cleanupContinuation.yield()
            cleanupContinuation.finish()
        }
    }

    func waitForFirstCleanup() async {
        for await _ in cleanupCompletion {
            return
        }
    }
}

// Combine subjects provide the immutable publisher bridge; mutable counters are Mutex-protected.
final class QuickRecordRecordingUseCase: RecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let levelSubject = CurrentValueSubject<Float, Never>(0)
    private let startError: Error?
    private let startGate: QuickRecordStartGate?
    private let operationRecorder: QuickRecordOperationRecorder
    private let stopGate: QuickRecordStartGate?
    private let stopError: Error?
    private let onStop: (@Sendable () -> Void)?
    private let counts = Mutex((start: 0, stop: 0))

    init(
        startError: Error?,
        startGate: QuickRecordStartGate?,
        operationRecorder: QuickRecordOperationRecorder,
        stopGate: QuickRecordStartGate? = nil,
        stopError: Error? = nil,
        onStop: (@Sendable () -> Void)? = nil
    ) {
        self.startError = startError
        self.startGate = startGate
        self.operationRecorder = operationRecorder
        self.stopGate = stopGate
        self.stopError = stopError
        self.onStop = onStop
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
        operationRecorder.record("stop")
        if let stopGate { await stopGate.suspendStart() }
        if let stopError { throw stopError }
        onStop?()
        stateSubject.send(.idle)
    }

    func pauseRecording() { stateSubject.send(.paused(duration: 0)) }
    func resumeRecording() { stateSubject.send(.recording(duration: 0)) }
    func cancelRecording() { stateSubject.send(.idle) }
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

// Combine subjects provide the immutable publisher bridge; language and gate state use Mutex.
final class QuickRecordTranscriptionUseCase: TranscriptionUseCase, @unchecked Sendable {
    private struct State {
        var language = Locale(identifier: "zh-Hans")
        var snapshotGateActive = false
    }

    private let liveText = CurrentValueSubject<String, Never>("")
    private let finalResult = PassthroughSubject<TranscriptionResult, Error>()
    private let snapshots = PassthroughSubject<String, Never>()
    private let state = Mutex(State())

    var liveTextPublisher: AnyPublisher<String, Never> { liveText.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> {
        finalResult.eraseToAnyPublisher()
    }
    var currentLanguage: Locale { state.withLock { $0.language } }
    var supportedLanguages: [Locale] { [currentLanguage] }
    var snapshotPublisher: AnyPublisher<String, Never> { snapshots.eraseToAnyPublisher() }
    var snapshotGateActive: Bool {
        get { state.withLock { $0.snapshotGateActive } }
        set { state.withLock { $0.snapshotGateActive = newValue } }
    }

    func setLanguage(_ locale: Locale) {
        state.withLock { $0.language = locale }
    }

    func sendFinalText(_ text: String) {
        finalResult.send(TranscriptionResult(
            text: text, type: .final, confidence: nil, timestamp: Date(), locale: currentLanguage
        ))
    }

    func commitCurrentTranscription() async throws {}
    func clearLiveText() { liveText.send("") }
}

// Combine subject is the sole unchecked bridge; this double has no mutable non-subject state.
final class QuickRecordRefinementUseCase: RefinementUseCase, @unchecked Sendable {
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
    func refineText(
        _ text: String,
        customPrompt: String?
    ) -> AsyncThrowingStream<RefinementEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

final class QuickRecordClipboardService: ClipboardService, Sendable {
    var hasText: Bool { false }
    func copy(_ text: String) {}
    func paste() -> String? { nil }
    func clear() {}
    func simulatePaste() async throws {}
}

@MainActor
final class TestGlobalHotkeyService: GlobalHotkeyService {
    private var pressHandler: (@concurrent @Sendable () async -> Void)?
    private var releaseHandler: (@concurrent @Sendable () async -> Void)?

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
    ) {
        pressHandler = onPress
        releaseHandler = onRelease
    }

    func press() async {
        await pressHandler?()
    }

    func release() async {
        await releaseHandler?()
    }
}

@MainActor
final class RuntimeFixture {
    let suite = "BlobTelemetryInstrumentationTests.\(UUID())"
    let store: UserDefaultsPreferencesStore
    let preferences: ProductTelemetryPreferences
    let recorder: RuntimeTelemetryRecorder
    private let recordedIdentities = Mutex<[UUID]>([])

    init(
        telemetryOperationObserver: (@Sendable (String) -> Void)? = nil,
        telemetryFlushGate: (@Sendable () async -> Void)? = nil
    ) {
        recorder = RuntimeTelemetryRecorder(
            operationObserver: telemetryOperationObserver,
            flushGate: telemetryFlushGate
        )
        let defaults = UserDefaults(suiteName: suite)!
        store = UserDefaultsPreferencesStore(defaults: defaults)
        preferences = ProductTelemetryPreferences(store: store)
    }

    var identities: [UUID] { recordedIdentities.withLock { $0 } }

    func makeSettingsViewModel(
        notificationCenter: NotificationCenter
    ) -> ProductTelemetrySettingsViewModel {
        ProductTelemetrySettingsViewModel(
            preferences: preferences,
            onConsentChanged: { consent in
                let (completion, continuation) = AsyncStream<Void>.makeStream()
                notificationCenter.post(
                    name: ProductTelemetrySettingsViewModel.consentDidChange,
                    object: nil,
                    userInfo: [
                        "isConsented": consent,
                        "transitionCompletion": continuation,
                    ]
                )
                for await _ in completion {}
            }
        )
    }

    func makeContainer(notificationCenter: NotificationCenter = .default) -> ServiceContainer {
        ServiceContainer(
            productTelemetryPreferences: preferences,
            processEnvironment: [:],
            processArguments: [],
            productTelemetryConfiguration: { Self.configuration },
            productTelemetryBootstrapFactory: { [self] identity in
                recordedIdentities.withLock { $0.append(identity) }
                return .testing(
                    configuration: Self.configuration,
                    host: .interactiveApplication,
                    isConsented: true,
                    makeService: { recorder.construct() }
                )
            },
            productTelemetryNotificationCenter: notificationCenter
        )
    }

    private static var configuration: BlobTelemetryConfiguration {
        .enabled(.init(
            endpoint: URL(string: "https://telemetry.example.invalid/container")!,
            sasQuery: "sr=c&si=synthetic&spr=https&sig=fake"
        ))
    }

    func remove() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

final class RuntimeTelemetryRecorder: Sendable {
    private struct State: Sendable {
        var constructionCount = 0
        var operations: [String] = []
        var events: [TelemetryEvent] = []
    }
    private let state = Mutex(State())
    private let operationObserver: (@Sendable (String) -> Void)?
    private let flushGate: (@Sendable () async -> Void)?

    init(
        operationObserver: (@Sendable (String) -> Void)? = nil,
        flushGate: (@Sendable () async -> Void)? = nil
    ) {
        self.operationObserver = operationObserver
        self.flushGate = flushGate
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

    func flush() async {
        state.withLock { $0.operations.append("flush") }
        await flushGate?()
    }

    func setEnabled(_ value: Bool) {
        let operation = value ? "enable" : "disable"
        state.withLock { $0.operations.append(operation) }
        operationObserver?(operation)
    }
}

final class RuntimeTelemetryService: TelemetryService, Sendable {
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
        await recorder.flush()
    }

    func resetIdentifier() {}
}
#endif
