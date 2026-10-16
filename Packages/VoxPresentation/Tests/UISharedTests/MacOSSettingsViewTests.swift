#if os(macOS)
import AppKit
import SwiftUI
import Vision
import Preferences
import PlatformAdapters
import XCTest
@testable import UIShared

@MainActor
final class MacOSSettingsViewTests: XCTestCase {
    private var suite: String!
    private var store: UserDefaultsPreferencesStore!

    override func setUp() async throws {
        await MainActor.run {
            suite = "MacOSSettingsViewTests.\(UUID().uuidString)"
            store = UserDefaultsPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    func testExistingSelectionsSurviveSettingsMigration() async {
        await store.setValue(LLMProviderSelection.appleIntelligence.rawValue, for: .llmProvider)
        await store.setValue(true, for: .llmSkipContentAnalysis)
        let oldShortcuts = ShortcutsViewModel(preferences: store)
        await oldShortcuts.updateShowPanelKey(.f8)
        await oldShortcuts.updateQuickRecordKey(.f9)
        let provider = LLMProviderSettingsViewModel(preferences: store)
        let shortcuts = ShortcutsViewModel(preferences: store)
        _ = MacOSSettingsView(providerSettings: provider, shortcuts: shortcuts).body
        await provider.load()
        await shortcuts.load()
        XCTAssertEqual(provider.selectedProvider, .appleIntelligence)
        XCTAssertTrue(provider.skipContentAnalysis)
        XCTAssertEqual(shortcuts.showPanelKey, .f8)
        XCTAssertEqual(shortcuts.quickRecordKey, .f9)
    }

    func testNewControlBindingsPersistUsingExistingKeysAndNotifications() async throws {
        let provider = LLMProviderSettingsViewModel(preferences: store)
        let shortcuts = ShortcutsViewModel(preferences: store)
        let textPane = MacOSTextSettingsPane(viewModel: provider, localModelLoadingStatus: nil)
        let keyPane = MacOSShortcutSettingsPane(viewModel: shortcuts)
        let providerChanged = expectation(forNotification: PreferencesNotification.llmProviderDidChange, object: nil)
        let analysisChanged = expectation(forNotification: PreferencesNotification.llmAnalysisSettingsDidChange, object: nil)
        let keysChanged = expectation(forNotification: PreferencesNotification.hotkeysDidChange, object: nil)
        keysChanged.expectedFulfillmentCount = 2
        textPane.providerBinding.wrappedValue = .appleIntelligence
        textPane.skipAnalysisBinding.wrappedValue = true
        keyPane.quickRecordBinding.wrappedValue = .f10
        keyPane.panelBinding.wrappedValue = .f11
        await fulfillment(of: [providerChanged, analysisChanged, keysChanged], timeout: 2)
        let reloadedProvider = LLMProviderSettingsViewModel(preferences: store)
        let reloadedShortcuts = ShortcutsViewModel(preferences: store)
        await reloadedProvider.load()
        await reloadedShortcuts.load()
        XCTAssertEqual(reloadedProvider.selectedProvider, .appleIntelligence)
        XCTAssertTrue(reloadedProvider.skipContentAnalysis)
        XCTAssertEqual(reloadedShortcuts.quickRecordKey, .f10)
        XCTAssertEqual(reloadedShortcuts.showPanelKey, .f11)
        await reloadedShortcuts.resetToDefaults()
        await shortcuts.load()
        XCTAssertEqual(shortcuts.quickRecordKey, .fn)
        XCTAssertEqual(shortcuts.showPanelKey, .f7)
    }

    func testShortcutsKeepConflictFeedback() async {
        let shortcuts = ShortcutsViewModel(preferences: store)
        await shortcuts.load()
        await shortcuts.updateQuickRecordKey(.f7)
        XCTAssertTrue(shortcuts.hasConflict)
        await shortcuts.updateQuickRecordKey(.fn)
        XCTAssertFalse(shortcuts.hasConflict)
    }

    func testLoadingDoesNotShowTemporaryDefaultValues() async throws {
        let gate = SettingsLoadGate()
        let view = MacOSSettingsView(
            providerSettings: LLMProviderSettingsViewModel(preferences: store),
            shortcuts: ShortcutsViewModel(preferences: store),
            initialSection: .shortcuts,
            loadShortcuts: { _ in await gate.suspend() }
        )
        .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        let panel = mount(host, height: 420)
        defer { panel.orderOut(nil) }
        await gate.waitUntilSuspended()
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let bitmap = try capture(panel)
        let words = try await recognize(bitmap).joined()
        XCTAssertTrue(words.contains("正在加载设置"), "Synthetic loading OCR: \(words)")
        XCTAssertFalse(words.contains("Azure"))
        XCTAssertFalse(words.contains("F7"))
        gate.release()
        if let directory = ProcessInfo.processInfo.environment["VOX_SETTINGS_RENDER_DIR"] {
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory).appendingPathComponent("settings-loading.png")
            try await Task.detached { try png.write(to: url) }.value
        }
    }

    func testNativeSettingsPagesRenderWithoutPlaceholderCards() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for section in [MacOSSettingsView.Section.shortcuts, .text] {
                let bitmap = try await render(section: section, scheme: scheme)
                let words = try await recognize(bitmap).joined(separator: " ")
                XCTAssertTrue(words.contains(section == .shortcuts ? "快捷录音" : "识别模型"), "Synthetic settings OCR: \(words)")
                if section == .text {
                    XCTAssertTrue(words.contains("意图模型"))
                    XCTAssertTrue(words.contains("语气模型"))
                    XCTAssertTrue(words.contains("精炼模型"))
                }
                // 离屏 cacheDisplay 未能可靠捕获系统玻璃页签；这里只验表单正文，导航交互由 App XCUITest 覆盖。
                for placeholder in ["VAD", "Verbose", "30 days", "VoxPocket 用户", "未连接"] {
                    XCTAssertFalse(words.contains(placeholder))
                }
                if let directory = ProcessInfo.processInfo.environment["VOX_SETTINGS_RENDER_DIR"] {
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("settings-\(section)-\(scheme).png")
                    try await Task.detached { try png.write(to: url) }.value
                }
            }
        }
    }

    func testUnconfiguredRealtimeShowsFallbackAndDeploymentEntry() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let bitmap = try await render(section: .text, scheme: scheme, configured: false)
            let words = try await recognize(bitmap).joined()
            XCTAssertTrue(words.contains("回退"))
            XCTAssertTrue(words.contains("部署名"))
            XCTAssertFalse(words.contains("实时配置就绪"))
            if let directory = ProcessInfo.processInfo.environment["VOX_SETTINGS_RENDER_DIR"] {
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let url = URL(fileURLWithPath: directory).appendingPathComponent("settings-unconfigured-\(scheme).png")
                try await Task.detached { try png.write(to: url) }.value
            }
        }
    }

    func testTelemetryControlsLoadAndBindThroughProductionParents() async throws {
        var observedSettingsModels: [(ObjectIdentifier, Bool, Bool)] = []
        let observeSettings: @MainActor (ProductTelemetrySettingsViewModel) -> Void = {
            observedSettingsModels.append((ObjectIdentifier($0), $0.isLoaded, $0.isSendingUsageData))
        }
        let settingsPreferences = ProductTelemetryPreferences(store: store)
        let retainedSettingsModel = ProductTelemetrySettingsViewModel(
            preferences: settingsPreferences,
            onConsentChanged: { await settingsPreferences.persistConsent($0) }
        )
        let settingsView = MacOSSettingsView(
            providerSettings: LLMProviderSettingsViewModel(preferences: store),
            shortcuts: ShortcutsViewModel(preferences: store),
            productTelemetry: retainedSettingsModel,
            initialSection: .privacy,
            observeProductTelemetryControl: observeSettings
        )
        let settingsHost = NSHostingView(rootView: settingsView)
        let settingsPanel = mount(settingsHost, height: 760)
        defer { settingsPanel.orderOut(nil) }

        try await waitUntil { retainedSettingsModel.isLoaded }
        settingsHost.layoutSubtreeIfNeeded()
        settingsPanel.displayIfNeeded()
        try await waitUntil { observedSettingsModels.last?.1 == true }
        let replacementSettingsModel = ProductTelemetrySettingsViewModel(
            preferences: settingsPreferences,
            onConsentChanged: { await settingsPreferences.persistConsent($0) }
        )
        settingsHost.rootView = MacOSSettingsView(
            providerSettings: LLMProviderSettingsViewModel(preferences: store),
            shortcuts: ShortcutsViewModel(preferences: store),
            productTelemetry: replacementSettingsModel,
            initialSection: .privacy,
            observeProductTelemetryControl: observeSettings
        )
        settingsHost.layoutSubtreeIfNeeded()
        settingsPanel.displayIfNeeded()
        let settingsWords = try await recognize(capture(settingsPanel)).joined()
        XCTAssertTrue(settingsWords.contains("Send usage data"), "Mounted settings parent OCR: \(settingsWords)")
        let settingsObservationsBeforeReplacementMutation = observedSettingsModels.count
        await replacementSettingsModel.setSendingUsageData(true)
        await Task.yield()
        XCTAssertEqual(observedSettingsModels.count, settingsObservationsBeforeReplacementMutation)
        await retainedSettingsModel.setSendingUsageData(true)
        try await waitUntil {
            guard let last = observedSettingsModels.last else { return false }
            return last.0 == ObjectIdentifier(retainedSettingsModel) && last.1 && last.2
        }
        XCTAssertTrue(retainedSettingsModel.isSendingUsageData)
        XCTAssertFalse(replacementSettingsModel.isLoaded)
        let settingsConsent = await ProductTelemetryPreferences(store: store).isConsented
        XCTAssertTrue(settingsConsent)
        XCTAssertNil(UserDefaults(suiteName: suite)?.data(forKey: "telemetry.product.installIdentity"))

        var observedMeModels: [(ObjectIdentifier, Bool, Bool)] = []
        let observeMe: @MainActor (ProductTelemetrySettingsViewModel) -> Void = {
            observedMeModels.append((ObjectIdentifier($0), $0.isLoaded, $0.isSendingUsageData))
        }
        let mePreferences = ProductTelemetryPreferences(store: store)
        let retainedMeModel = ProductTelemetrySettingsViewModel(
            preferences: mePreferences,
            onConsentChanged: { await mePreferences.persistConsent($0) }
        )
        let meView = MeRootView(
            productTelemetry: retainedMeModel,
            observeProductTelemetryControl: observeMe
        )
        let meHost = NSHostingView(rootView: meView)
        let mePanel = mount(meHost, height: 1_200)
        defer { mePanel.orderOut(nil) }

        try await waitUntil { retainedMeModel.isLoaded && retainedMeModel.isSendingUsageData }
        try await waitUntil {
            guard let last = observedMeModels.last else { return false }
            return last.0 == ObjectIdentifier(retainedMeModel) && last.1 && last.2
        }
        let replacementMeModel = ProductTelemetrySettingsViewModel(
            preferences: mePreferences,
            onConsentChanged: { await mePreferences.persistConsent($0) }
        )
        meHost.rootView = MeRootView(
            productTelemetry: replacementMeModel,
            observeProductTelemetryControl: observeMe
        )
        meHost.layoutSubtreeIfNeeded()
        mePanel.displayIfNeeded()
        let meWords = try await recognize(capture(mePanel)).joined()
        XCTAssertTrue(meWords.contains("Send usage data"), "Mounted Me parent OCR: \(meWords)")
        let meObservationsBeforeReplacementMutation = observedMeModels.count
        await replacementMeModel.setSendingUsageData(false)
        await Task.yield()
        XCTAssertEqual(observedMeModels.count, meObservationsBeforeReplacementMutation)
        await retainedMeModel.setSendingUsageData(false)
        try await waitUntil {
            guard let last = observedMeModels.last else { return false }
            return last.0 == ObjectIdentifier(retainedMeModel) && last.1 && !last.2
        }
        XCTAssertFalse(retainedMeModel.isSendingUsageData)
        XCTAssertFalse(replacementMeModel.isLoaded)
        let meConsent = await ProductTelemetryPreferences(store: store).isConsented
        XCTAssertFalse(meConsent)
        XCTAssertNil(UserDefaults(suiteName: suite)?.data(forKey: "telemetry.product.installIdentity"))
    }

    func testPrivacyConsentRemainsInteractiveWhileUnrelatedSettingsLoadIsSuspended() async throws {
        enum SuspendedLoad: CaseIterable { case provider, shortcuts }

        for suspendedLoad in SuspendedLoad.allCases {
            await store.setValue(true, for: .productTelemetryConsent)
            let gate = SettingsLoadGate()
            let preferences = ProductTelemetryPreferences(store: store)
            let productTelemetry = ProductTelemetrySettingsViewModel(
                preferences: preferences,
                onConsentChanged: { await preferences.persistConsent($0) }
            )
            let providerLoad: (@MainActor (LLMProviderSettingsViewModel) async -> Void)?
            if suspendedLoad == .provider {
                providerLoad = { _ in await gate.suspend() }
            } else {
                providerLoad = nil
            }
            let shortcutsLoad: (@MainActor (ShortcutsViewModel) async -> Void)?
            if suspendedLoad == .shortcuts {
                shortcutsLoad = { _ in await gate.suspend() }
            } else {
                shortcutsLoad = nil
            }
            let view = MacOSSettingsView(
                providerSettings: LLMProviderSettingsViewModel(preferences: store),
                shortcuts: ShortcutsViewModel(preferences: store),
                productTelemetry: productTelemetry,
                initialSection: .privacy,
                loadProviderSettings: providerLoad,
                loadShortcuts: shortcutsLoad
            )
            let host = NSHostingView(rootView: view)
            let panel = mount(host, height: 760)

            await gate.waitUntilSuspended()
            try await waitUntil { productTelemetry.isLoaded && productTelemetry.isSendingUsageData }
            host.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            let words = try await recognize(capture(panel)).joined()
            XCTAssertTrue(words.contains("Send usage data"), "Mounted Privacy surface OCR: \(words)")

            let privacySurface = ProductTelemetrySettingsView(viewModel: productTelemetry)
            XCTAssertTrue(privacySurface.consentBinding.wrappedValue)
            privacySurface.consentBinding.wrappedValue = false
            try await waitUntil { productTelemetry.isLoaded && !productTelemetry.isSendingUsageData }
            let persistedConsent = await ProductTelemetryPreferences(store: store).isConsented
            XCTAssertFalse(persistedConsent)
            XCTAssertNil(UserDefaults(suiteName: suite)?.data(forKey: "telemetry.product.installIdentity"))

            gate.release()
            panel.orderOut(nil)
        }
    }

    private func render(section: MacOSSettingsView.Section, scheme: ColorScheme,
                        configured: Bool = true) async throws -> NSBitmapImageRep {
        let availability: ModelSettingsAvailability = configured ? .init(
            batchConfigured: true, realtimeCredentialsConfigured: true, realtimeDeployment: "fixture-live",
            textConfigured: true, textModelName: "gpt-5.6-luna"
        ) : .init()
        let provider = LLMProviderSettingsViewModel(preferences: store, availability: availability)
        let shortcuts = ShortcutsViewModel(preferences: store)
        await provider.load()
        await shortcuts.load()
        let previousAppearance = NSApplication.shared.appearance
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        NSApplication.shared.appearance = appearance
        defer { NSApplication.shared.appearance = previousAppearance }
        let host = NSHostingView(rootView: MacOSSettingsView(providerSettings: provider, shortcuts: shortcuts,
                                                            initialSection: section)
            .environment(\.colorScheme, scheme))
        host.appearance = appearance
        let panel = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 640, height: 760),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "VoxPocket 设置"
        panel.appearance = appearance
        panel.contentView = host
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        let expectedText = section == .shortcuts ? "快捷录音" : "识别模型"
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            let bitmap = try capture(panel)
            if try await recognize(bitmap).joined().contains(expectedText) {
                return bitmap
            }
            if ContinuousClock.now >= deadline {
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                panel.displayIfNeeded()
                let finalBitmap = try capture(panel)
                let finalWords = try await recognize(finalBitmap).joined()
                XCTAssertTrue(finalWords.contains(expectedText), "Timed out rendering settings: \(finalWords)")
                return finalBitmap
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func capture(_ panel: NSPanel) throws -> NSBitmapImageRep {
        let frameView = try XCTUnwrap(panel.contentView?.superview)
        let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.effectiveAppearance.performAsCurrentDrawingAppearance {
            frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        }
        return bitmap
    }

    private func mount<Content: View>(
        _ host: NSHostingView<Content>,
        height: CGFloat
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 640, height: height),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out waiting for mounted production view state", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func recognize(_ bitmap: NSBitmapImageRep) async throws -> [String] {
        let image = try XCTUnwrap(bitmap.cgImage)
        return try await Task.detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

@MainActor
private final class SettingsLoadGate {
    private var isSuspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private let releaseStream: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init() {
        (releaseStream, releaseContinuation) = AsyncStream.makeStream()
    }

    func suspend() async {
        isSuspended = true
        suspensionWaiter?.resume()
        suspensionWaiter = nil
        for await _ in releaseStream.prefix(1) {}
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { suspensionWaiter = $0 }
    }

    func release() {
        releaseContinuation.yield()
        releaseContinuation.finish()
    }
}
#endif
