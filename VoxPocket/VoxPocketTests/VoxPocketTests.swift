//
//  VoxPocketTests.swift
//  VoxPocketTests
//
//  Created by 李天培 on 1/26/26.
//

import Testing
#if os(macOS)
import AppKit
import Carbon
import CoreModels
import PlatformAdapters
import UseCases
@testable import VoxPocket
#endif

struct VoxPocketTests {

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
    #else
    @Test func example() async throws {
        #expect(true)
    }
    #endif

}
