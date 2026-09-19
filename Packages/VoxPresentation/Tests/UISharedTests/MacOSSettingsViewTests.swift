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
        let view = MacOSSettingsView(providerSettings: LLMProviderSettingsViewModel(preferences: store),
                                    shortcuts: ShortcutsViewModel(preferences: store))
            .frame(width: 620, height: 420).background(.white).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let words = try recognize(bitmap).joined()
        XCTAssertTrue(words.contains("正在加载设置"), "Synthetic loading OCR: \(words)")
        XCTAssertFalse(words.contains("Azure"))
        XCTAssertFalse(words.contains("F7"))
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
                let words = try recognize(bitmap).joined(separator: " ")
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
            let words = try recognize(bitmap).joined()
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

    private func render(section: MacOSSettingsView.Section, scheme: ColorScheme,
                        configured: Bool = true) async throws -> NSBitmapImageRep {
        let availability: ModelSettingsAvailability = configured ? .init(
            batchConfigured: true, realtimeCredentialsConfigured: true, realtimeDeployment: "fixture-live",
            textConfigured: true, textModelName: "gpt-5.6-luna"
        ) : .init()
        let provider = LLMProviderSettingsViewModel(preferences: store, availability: availability)
        let shortcuts = ShortcutsViewModel(preferences: store)
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
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let frameView = try XCTUnwrap(panel.contentView?.superview)
        let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.effectiveAppearance.performAsCurrentDrawingAppearance {
            frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        }
        return bitmap
    }

    private func recognize(_ bitmap: NSBitmapImageRep) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
#endif
