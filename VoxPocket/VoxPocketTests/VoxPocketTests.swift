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

        fixture.hotkeys.trigger(HotkeyIdentifier.voiceToTodo)
        try await waitForDismissBoundary { fixture.visible && fixture.recording.startCallCount == 1 }
        #expect(fixture.delegate?.activeQuickCaptureMode == .todo)

        fixture.hotkeys.trigger(HotkeyIdentifier.voiceToTodo)
        try await waitForDismissBoundary { fixture.refinement.isWaiting }
        fixture.refinement.finish()
        await fixture.clipboard.gate.release()
        try await waitForDismissBoundary { fixture.saved.count == 1 }
        #expect(fixture.saved.count == 1)
        fixture.remove()
    }
    #else
    @Test func example() async throws {
        #expect(true)
    }
    #endif

}
