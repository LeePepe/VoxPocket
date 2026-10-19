#if os(macOS)
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
        let container = fixture.makeContainer(notificationCenter: center)
        let model = fixture.makeSettingsViewModel(notificationCenter: center)

        await model.setSendingUsageData(true)
        center.post(name: ProductTelemetrySettingsViewModel.settingsDidOpen, object: nil)
        ProductTelemetryNotificationBoundary.postFullPanelOpened(to: center)
        await Task.yield()
        await model.setSendingUsageData(false)
        ProductTelemetryNotificationBoundary.postFullPanelOpened(to: center)
        await Task.yield()
        await container.waitForPendingProductTelemetryConsentChange()

        #expect(fixture.recorder.events.compactMap { $0.properties["action"] } == [
            "settings_opened", "full_panel_opened"
        ])
        #expect(fixture.recorder.operations.contains("disable"))
    }

    @Test func productionSettingsOptOutStopsLaterRuntimeAdmission() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        let center = NotificationCenter()
        let container = fixture.makeContainer(notificationCenter: center)
        let model = fixture.makeSettingsViewModel(notificationCenter: center)

        await model.setSendingUsageData(true)
        await model.setSendingUsageData(false)
        center.post(name: ProductTelemetrySettingsViewModel.settingsDidOpen, object: nil)
        ProductTelemetryNotificationBoundary.postFullPanelOpened(to: center)
        await container.productTelemetryApplicationWillResignActive()
        await container.waitForPendingProductTelemetryConsentChange()

        #expect(!model.isSendingUsageData)
        #expect(await fixture.preferences.isConsented == false)
        #expect(fixture.recorder.constructionCount == 1)
        #expect(fixture.recorder.events.isEmpty)
        #expect(fixture.recorder.operations == ["construct", "disable"])
    }

    @Test func productionQuickRecordBoundariesPreserveNormalAndRapidReleaseOrder() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        _ = await fixture.preferences.setConsent(true)
        let center = NotificationCenter()
        let container = fixture.makeContainer(notificationCenter: center)
        await container.completeProductTelemetryStartup(startedAt: .now)
        await container.waitForPendingProductTelemetryStartupCompletion()
        await assertNormalQuickRecord(center: center, container: container)
        await assertFailedQuickRecord(center: center, container: container)
        await assertRapidRelease(center: center, container: container)
        // 等待已入队的遥测写入完成，再检查完整事件顺序。
        await container.productTelemetryApplicationWillResignActive()
        #expect(fixture.recorder.events.compactMap { $0.properties["action"] } == [
            "quick_record_started", "quick_record_stopped",
            "quick_record_started", "quick_record_stopped"
        ])
    }

    private func assertNormalQuickRecord(
        center: NotificationCenter,
        container: ServiceContainer
    ) async {
        let normal = QuickRecordFixture()
        let launched = await launchQuickRecordDelegate(normal, center: center, container: container)
        let hotkeys = launched.1
        await hotkeys.press()
        #expect(normal.recording.startCallCount == 1)
        #expect(normal.viewModel.recorderStatus == .listening)
        await hotkeys.release()
        await normal.waitForFirstCleanup()
        #expect(normal.recording.stopCallCount == 1)
        #expect(normal.operations.first == "claim")
        assertQuickRecordOrder(normal.operations)
        withExtendedLifetime(launched.0) {}
    }

    private func assertFailedQuickRecord(
        center: NotificationCenter,
        container: ServiceContainer
    ) async {
        let failing = QuickRecordFixture(startError: QuickRecordFixture.StartError.synthetic)
        let launched = await launchQuickRecordDelegate(failing, center: center, container: container)
        let hotkeys = launched.1
        await hotkeys.press()
        #expect(failing.recording.startCallCount == 1)
        #expect(failing.viewModel.recorderStatus == .error)
        withExtendedLifetime(launched.0) {}
    }

    private func assertRapidRelease(
        center: NotificationCenter,
        container: ServiceContainer
    ) async {
        let startGate = QuickRecordStartGate()
        let rapid = QuickRecordFixture(startGate: startGate)
        let launched = await launchQuickRecordDelegate(rapid, center: center, container: container)
        let hotkeys = launched.1
        let startTask = Task { await hotkeys.press() }
        await startGate.waitUntilEntered()
        #expect(rapid.viewModel.isStartingRecording)
        await hotkeys.release()
        #expect(rapid.recording.stopCallCount == 0)
        await startGate.release()
        await startTask.value
        await rapid.waitForFirstCleanup()
        #expect(rapid.recording.startCallCount == 1)
        #expect(rapid.recording.stopCallCount == 1)
        assertQuickRecordOrder(rapid.operations)
        withExtendedLifetime(launched.0) {}
    }

    private func assertQuickRecordOrder(_ operations: [String]) {
        let expected = ["claim", "show", "get", "active", "get", "stop"]
        var nextIndex = operations.startIndex
        for operation in expected {
            guard let index = operations[nextIndex...].firstIndex(of: operation) else {
                Issue.record("Missing ordered quick-record operation: \(operation)")
                return
            }
            nextIndex = operations.index(after: index)
        }
        let cleanupIndex = operations[nextIndex...].firstIndex { $0 == "hide" || $0 == "end" }
        #expect(cleanupIndex != nil)
        #expect(operations.contains("hide"))
        #expect(operations.contains("end"))
    }

    private func launchQuickRecordDelegate(
        _ fixture: QuickRecordFixture,
        center: NotificationCenter,
        container: ServiceContainer
    ) async -> (AppDelegate, TestGlobalHotkeyService) {
        let hotkeys = TestGlobalHotkeyService()
        let delegate = AppDelegate(
            productTelemetryNotificationCenter: center,
            startup: AppStartup {},
            serviceContainer: container,
            hotkeyService: hotkeys,
            startupInitializePersistence: {},
            startupScheduleQuickRecordingPrewarm: {},
            quickRecordTryStart: fixture.tryStart,
            quickRecordActiveSource: fixture.activeSource,
            quickRecordEnd: fixture.end,
            quickRecordShowWindow: fixture.show,
            quickRecordViewModel: fixture.getViewModel,
            quickRecordHideWindow: fixture.hide,
            quickRecordDismissWindow: fixture.dismiss
        )
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await delegate.waitForPendingStartup()
        return (delegate, hotkeys)
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
        await container.waitForPendingProductTelemetryStartupCompletion()
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
        await container.waitForPendingProductTelemetrySessionCompletion()
        #expect(fixture.recorder.operations.filter { $0 == "flush" }.count == 3)
        delegate.applicationWillResignActive(
            Notification(name: Notification.Name("test.applicationWillResignActive"))
        )
        await delegate.waitForPendingProductTelemetryResignActive()

        #expect(fixture.recorder.operations.filter { $0 == "flush" }.count == 4)
    }

    @Test func startupAndSessionPersistenceReturnWhileLifecycleFlushRemainsPending() async {
        await assertStartupReturnsWhileFlushIsPending()
        await assertSessionReturnsWhileFlushIsPending()
    }

    private func assertStartupReturnsWhileFlushIsPending() async {
        let startupFlushGate = TelemetryFlushGate(targetEntry: 1)
        let startupFixture = RuntimeFixture(telemetryFlushGate: startupFlushGate.suspendTarget)
        defer { startupFixture.remove() }
        _ = await startupFixture.preferences.setConsent(true)
        let startupContainer = startupFixture.makeContainer()
        let startupDelegate = AppDelegate(
            productTelemetryNotificationCenter: NotificationCenter(),
            startup: AppStartup {},
            serviceContainer: startupContainer,
            hotkeyService: TestGlobalHotkeyService(),
            startupInitializePersistence: {},
            startupScheduleQuickRecordingPrewarm: {}
        )
        startupDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let startupReturned = Mutex(false)
        let startupCaller = Task {
            await startupDelegate.waitForPendingStartup()
            startupReturned.withLock { $0 = true }
        }

        await startupFlushGate.waitUntilEntered()
        for _ in 0..<100 where !startupReturned.withLock({ $0 }) {
            await Task.yield()
        }
        #expect(startupReturned.withLock { $0 })
        #expect(startupFixture.recorder.operations == [
            "construct", "track product.performance", "flush"
        ])
        await startupFlushGate.release()
        await startupCaller.value
        await startupContainer.waitForPendingProductTelemetryStartupCompletion()
    }

    private func assertSessionReturnsWhileFlushIsPending() async {
        let sessionFlushGate = TelemetryFlushGate(targetEntry: 2)
        let sessionFixture = RuntimeFixture(telemetryFlushGate: sessionFlushGate.suspendTarget)
        defer { sessionFixture.remove() }
        _ = await sessionFixture.preferences.setConsent(true)
        let sessionContainer = sessionFixture.makeContainer()
        await sessionContainer.completeProductTelemetryStartup(startedAt: .now)
        await sessionContainer.waitForPendingProductTelemetryStartupCompletion()

        let sessionReturned = Mutex(false)
        let sessionCaller = Task {
            _ = try? await sessionContainer.sessionUseCase.saveCompletedSession(
                title: nil,
                rawText: "synthetic raw",
                refinedText: "synthetic refined"
            )
            sessionReturned.withLock { $0 = true }
        }

        await sessionFlushGate.waitUntilEntered()
        for _ in 0..<100 where !sessionReturned.withLock({ $0 }) {
            await Task.yield()
        }
        #expect(sessionReturned.withLock { $0 })
        #expect(sessionFixture.recorder.operations == [
            "construct", "track product.performance", "flush", "flush"
        ])
        await sessionFlushGate.release()
        await sessionCaller.value
        await sessionContainer.waitForPendingProductTelemetrySessionCompletion()
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

    @Test func productionSettingsTransitionsReuseIdentityAndAllComplete() async {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        let center = NotificationCenter()
        let container = fixture.makeContainer(notificationCenter: center)
        let model = fixture.makeSettingsViewModel(notificationCenter: center)

        await model.setSendingUsageData(true)
        await model.setSendingUsageData(false)
        await model.setSendingUsageData(true)
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

        #expect(fixture.recorder.operations == [
            "construct", "disable", "enable", "track product.user_action", "flush"
        ])
    }

    @Test func startupAndActionsEmitOnlyAfterSuccessfulComposition() async throws {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        let center = NotificationCenter()
        let container = fixture.makeContainer(notificationCenter: center)
        let model = fixture.makeSettingsViewModel(notificationCenter: center)

        container.recordProductAction(.settingsOpened)
        await container.completeProductTelemetryStartup(startedAt: .now)
        #expect(fixture.recorder.operations.isEmpty)

        await model.setSendingUsageData(true)
        container.recordProductAction(.settingsOpened)
        container.recordProductAction(.fullPanelOpened)
        container.recordProductAction(.quickRecordStarted)
        container.recordProductAction(.quickRecordStopped)
        await container.productTelemetryApplicationWillResignActive()

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

    @Test func sameTurnFlushRequestIsAdmittedBeforeLaterAction() async throws {
        let flushGate = TelemetryFlushGate(targetEntry: 1)
        let fixture = RuntimeFixture(telemetryFlushGate: flushGate.suspendTarget)
        defer { fixture.remove() }
        let center = NotificationCenter()
        let container = fixture.makeContainer(notificationCenter: center)
        let model = fixture.makeSettingsViewModel(notificationCenter: center)
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
        await delegate.waitForPendingStartup()
        await container.waitForPendingProductTelemetryStartupCompletion()
        #expect(fixture.identities.isEmpty)
        #expect(fixture.recorder.constructionCount == 0)
        #expect(fixture.recorder.events.isEmpty)
        #expect(fixture.recorder.operations.isEmpty)
        await model.setSendingUsageData(true)
        await container.waitForPendingProductTelemetryConsentChange()
        delegate.applicationWillResignActive(
            Notification(name: Notification.Name("test.applicationWillResignActive"))
        )
        await flushGate.waitUntilEntered()
        container.recordProductAction(.settingsOpened)

        await flushGate.release()
        await delegate.waitForPendingProductTelemetryResignActive()
        delegate.applicationWillResignActive(
            Notification(name: Notification.Name("test.applicationWillResignActive"))
        )
        await delegate.waitForPendingProductTelemetryResignActive()

        #expect(fixture.recorder.operations == [
            "construct", "flush", "track product.user_action", "flush"
        ])
    }

    @Test func consentedStartupRecordsBoundedLaunchDurationThenFlushes() async throws {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        _ = await fixture.preferences.setConsent(true)
        let container = fixture.makeContainer()

        await container.completeProductTelemetryStartup(startedAt: .now)
        await container.waitForPendingProductTelemetryStartupCompletion()

        let event = try #require(fixture.recorder.events.first)
        #expect(event.name == "product.performance")
        #expect(event.properties["operation"] == "app_launch")
        let duration = try #require(Double(event.properties["duration_ms"] ?? ""))
        #expect((0...3_600_000).contains(duration))
        #expect(fixture.recorder.operations == ["construct", "track product.performance", "flush"])
    }

    @Test func disableStopsAdmissionUntilExplicitReenable() async throws {
        let fixture = RuntimeFixture()
        defer { fixture.remove() }
        let center = NotificationCenter()
        let container = fixture.makeContainer(notificationCenter: center)
        let model = fixture.makeSettingsViewModel(notificationCenter: center)

        await model.setSendingUsageData(true)
        container.recordProductAction(.quickRecordStarted)
        await model.setSendingUsageData(false)
        container.recordProductAction(.quickRecordStopped)
        await model.setSendingUsageData(true)
        container.recordProductAction(.quickRecordStopped)
        await container.productTelemetryApplicationWillResignActive()

        #expect(fixture.recorder.constructionCount == 1)
        #expect(fixture.recorder.events.compactMap { $0.properties["action"] } == [
            "quick_record_started", "quick_record_stopped"
        ])
        #expect(fixture.identities.count == 2)
        #expect(Set(fixture.identities).count == 1)
        #expect(fixture.recorder.operations == [
            "construct",
            "track product.user_action",
            "disable",
            "enable",
            "track product.user_action",
            "flush",
        ])
    }
}

@MainActor
private final class QuickRecordFixture {
    enum StartError: Error { case synthetic }

    let recording: QuickRecordRecordingUseCase
    let viewModel: QuickRecordingViewModel
    private(set) var source: RecordingSource?
    private let operationRecorder = QuickRecordOperationRecorder()

    init(startError: Error? = nil, startGate: QuickRecordStartGate? = nil) {
        recording = QuickRecordRecordingUseCase(
            startError: startError,
            startGate: startGate,
            operationRecorder: operationRecorder
        )
        viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: QuickRecordTranscriptionUseCase(),
            refinementUseCase: QuickRecordRefinementUseCase(),
            clipboardService: QuickRecordClipboardService()
        )
    }

    var operations: [String] { operationRecorder.operations }

    func waitForFirstCleanup() async {
        await operationRecorder.waitForFirstCleanup()
    }

    func tryStart(_ requestedSource: RecordingSource) -> Bool {
        operationRecorder.record("claim")
        guard source == nil else { return false }
        source = requestedSource
        return true
    }

    func activeSource() -> RecordingSource? {
        operationRecorder.record("active")
        return source
    }

    func end() {
        operationRecorder.record("end")
        source = nil
    }

    func show() {
        operationRecorder.record("show")
    }

    func getViewModel() -> QuickRecordingViewModel? {
        operationRecorder.record("get")
        return viewModel
    }

    func dismiss() -> Bool {
        operationRecorder.record("dismiss")
        return true
    }

    func hide() {
        operationRecorder.record("hide")
    }
}
#endif
