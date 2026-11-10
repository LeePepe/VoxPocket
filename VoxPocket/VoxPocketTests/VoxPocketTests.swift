//
//  VoxPocketTests.swift
//  VoxPocketTests
//
//  Created by 李天培 on 1/26/26.
//

import Foundation
import Testing
import CoreModels
import Preferences
import UIShared
import UseCases
@testable import VoxPocket
#if os(macOS)
import AppKit
import Carbon
import PlatformAdapters
#endif

struct VoxPocketTests {

    @MainActor
    @Test func shortcutIntentSkipsCaptureWhenStartupPreparationFails() async {
        enum ShortcutStartupError: Error { case invalidConfiguration }
        var actionCalls = 0
        let startup = AppStartup {
            throw ShortcutStartupError.invalidConfiguration
        }

        let executed = await StartRecordingIntent.execute(startup: startup) {
            actionCalls += 1
        }

        #expect(executed == false)
        #expect(actionCalls == 0)
    }

    @MainActor
    @Test func shortcutIntentRunsCaptureAfterStartupPreparationSucceeds() async {
        var actionCalls = 0
        let startup = AppStartup {}

        let executed = await StartRecordingIntent.execute(startup: startup) {
            actionCalls += 1
        }

        #expect(executed)
        #expect(actionCalls == 1)
    }

    @MainActor
    @Test func toggleQuickCaptureFromIntentStartsWithPreferredDestinationAndCancelsCleanly() async throws {
        let suite = "VoxPocketTests.QuickCapture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPreferencesStore(defaults: defaults)
        await store.setValue(CaptureMode.text, for: .iosQuickCaptureDestination)

        let intentNotificationCenter = NotificationCenter()
        let container = ServiceContainer(
            productTelemetryPreferences: ProductTelemetryPreferences(store: store),
            processEnvironment: [:],
            processArguments: [],
            preferencesStore: store,
            llmNotificationCenter: intentNotificationCenter,
            productTelemetryNotificationCenter: NotificationCenter(),
            productTelemetryHostOverride: .test
        )
        container.workspaceViewModel.isDemoRecordingEnabled = true

        #expect(container.workspaceViewModel.isRecordingActive == false)

        var startedModes: [String] = []
        var endedCount = 0
        let startedToken = NotificationCenter.default.addObserver(
            forName: Notification.Name("vox.liveActivity.recordingStarted"),
            object: nil,
            queue: nil
        ) { note in
            if let mode = note.userInfo?["mode"] as? String {
                startedModes.append(mode)
            }
        }
        let endedToken = NotificationCenter.default.addObserver(
            forName: Notification.Name("vox.liveActivity.recordingEnded"),
            object: nil,
            queue: nil
        ) { _ in
            endedCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(startedToken)
            NotificationCenter.default.removeObserver(endedToken)
        }

        await container.toggleQuickCaptureFromIntent()
        #expect(container.workspaceViewModel.isRecordingActive == true)
        #expect(container.workspaceViewModel.selectedCaptureMode == .text)
        #expect(startedModes.contains(CaptureMode.text.rawValue))

        try container.editingUseCase.replaceAll(with: "Background quick capture note")
        await container.toggleQuickCaptureFromIntent()
        #expect(container.workspaceViewModel.isRecordingActive == false)
        #expect(endedCount >= 1)

        #if os(iOS)
        #expect(StartRecordingIntent.openAppWhenRun == false)

        intentNotificationCenter.post(
            name: Notification.Name("vox.liveActivity.toggleCapture"),
            object: nil
        )
        for _ in 0..<200 where !container.workspaceViewModel.isRecordingActive {
            await Task.yield()
        }
        #expect(container.workspaceViewModel.isRecordingActive == true)

        try container.editingUseCase.replaceAll(with: "Finish capture from Dynamic Island")
        intentNotificationCenter.post(
            name: Notification.Name("vox.liveActivity.finishCapture"),
            object: nil
        )
        for _ in 0..<200 where container.workspaceViewModel.isRecordingActive {
            await Task.yield()
        }
        #expect(container.workspaceViewModel.isRecordingActive == false)
        #endif
    }

    #if os(macOS)
    @MainActor
    @Test func registersOptionSpaceAndOptionShiftSpaceHotkeysAndTogglesQuickRecord() async throws {
        let fixture = ImmediateDismissFixture()
        await fixture.launch()

        let direct = fixture.hotkeys.getRegistered(HotkeyIdentifier.directToText)
        let todo = fixture.hotkeys.getRegistered(HotkeyIdentifier.voiceToTodo)
        #expect(direct?.keyCode == UInt16(kVK_Space))
        #expect(direct?.modifiers == UInt(optionKey))
        #expect(todo?.keyCode == UInt16(kVK_Space))
        #expect(todo?.modifiers == UInt(optionKey | shiftKey))

        await fixture.hotkeys.press(HotkeyIdentifier.voiceToTodo)
        try await waitForDismissBoundary { fixture.visible && fixture.recording.startCallCount == 1 }
        #expect(fixture.delegate?.activeQuickCaptureMode == .todo)

        await fixture.hotkeys.release(HotkeyIdentifier.voiceToTodo)
        try await waitForDismissBoundary { fixture.refinement.isWaiting }

        // Pressing directToText while the previous .todo session is still completing
        // must not overwrite the in-flight session's .todo capture mode.
        await fixture.hotkeys.press(HotkeyIdentifier.directToText)
        #expect(fixture.delegate?.activeQuickCaptureMode == .todo)
        #expect(fixture.delegate != nil)

        fixture.refinement.finish()
        await fixture.clipboard.gate.release()
        try await waitForDismissBoundary { fixture.saved.count == 1 }
        #expect(fixture.saved.count == 1)
        #expect(fixture.delegate?.activeQuickCaptureMode == .todo)

        let container = fixture.runtime.makeContainer()
        container.activeSessionCaptureMode = .todo
        _ = try await container.sessionUseCase.saveCompletedSession(
            title: nil, rawText: "Fix hotkey mode", refinedText: "Fix hotkey mode."
        )
        let captures = try await container.voiceCaptureAndTodoUseCase.fetchCaptures()
        let todos = try await container.voiceCaptureAndTodoUseCase.fetchTodos()
        #expect(captures.contains(where: { $0.rawTranscript == "Fix hotkey mode" && $0.mode == .todo }))
        #expect(todos.contains(where: { $0.rawTranscript == "Fix hotkey mode" }))
        fixture.remove()
    }

    @MainActor
    @Test func missingPermissionOnFirstPressPromptsWithoutShowingQuickRecordingPanel() async throws {
        let fixture = ImmediateDismissFixture()
        await fixture.launch()
        defer { fixture.remove() }

        var permissionPrompts = 0
        var isAuthorized = false
        fixture.delegate?.quickRecordEnsurePermissions = { _ in
            if !isAuthorized {
                permissionPrompts += 1
                return false
            }
            return true
        }

        // First press without permission requests permission and does not show the panel
        await fixture.hotkeys.press(HotkeyIdentifier.directToText)
        #expect(permissionPrompts == 1)
        #expect(fixture.visible == false)
        #expect(fixture.recording.startCallCount == 0)

        // Subsequent press after permission is granted shows the panel and starts recording
        isAuthorized = true
        await fixture.hotkeys.press(HotkeyIdentifier.directToText)
        try await waitForDismissBoundary { fixture.visible && fixture.recording.startCallCount == 1 }
        #expect(fixture.visible == true)
        await fixture.hotkeys.release(HotkeyIdentifier.directToText)
        try await waitForDismissBoundary { fixture.refinement.isWaiting }
        fixture.refinement.finish()
        await fixture.clipboard.gate.release()
        try await waitForDismissBoundary { fixture.saved.count == 1 }
    }

    @MainActor
    @Test func ensureQuickRecordingPermissionsChecksMicAndSpeechWithoutRequiringAccessibility() async throws {
        let fixture = ImmediateDismissFixture()
        await fixture.launch()
        defer { fixture.remove() }

        var micPrompts = 0
        var speechPrompts = 0
        var hasMic = false
        var hasSpeech = false
        fixture.delegate?.quickRecordHasMicPermission = { hasMic }
        fixture.delegate?.quickRecordRequestMicPermission = {
            micPrompts += 1
            return false
        }
        fixture.delegate?.quickRecordHasSpeechPermission = { hasSpeech }
        fixture.delegate?.quickRecordRequestSpeechPermission = {
            speechPrompts += 1
            return false
        }

        await fixture.hotkeys.press(HotkeyIdentifier.directToText)
        #expect(micPrompts == 1)
        #expect(speechPrompts == 1)
        #expect(fixture.visible == false)
        #expect(fixture.recording.startCallCount == 0)

        hasMic = true
        hasSpeech = true
        await fixture.hotkeys.press(HotkeyIdentifier.directToText)
        try await waitForDismissBoundary { fixture.visible && fixture.recording.startCallCount == 1 }
        #expect(fixture.visible == true)
        await fixture.hotkeys.release(HotkeyIdentifier.directToText)
        try await waitForDismissBoundary { fixture.refinement.isWaiting }
        fixture.refinement.finish()
        await fixture.clipboard.gate.release()
        try await waitForDismissBoundary { fixture.saved.count == 1 }
    }
    #else
    @Test func example() async throws {
        #expect(true)
    }
    #endif

}
