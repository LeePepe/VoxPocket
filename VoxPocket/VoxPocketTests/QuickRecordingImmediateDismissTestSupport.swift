#if os(macOS)
import AppKit
import Combine
import CoreModels
import Foundation
import LLMKit
import PlatformAdapters
import PlatformUI
import Synchronization
import Testing
import TranscriptionKit
import UIShared
import UseCases
@testable import VoxPocket

// unchecked 仅桥接 Combine subject；可变流 continuation 用 Mutex 保护。
final class DismissRefinementUseCase: RefinementUseCase, @unchecked Sendable {
    private let subject = CurrentValueSubject<RefinementState, Never>(.idle)
    private let continuation = Mutex<AsyncThrowingStream<RefinementEvent, Error>.Continuation?>(nil)
    var state: RefinementState { subject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { subject.eraseToAnyPublisher() }
    var isConfigured: Bool { true }
    var isWaiting: Bool { continuation.withLock { $0 != nil } }
    func refine(customPrompt: String?) async throws {}
    func refineSelection(range: NSRange, customPrompt: String?) async throws {}
    func refineStreaming(customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        refineStreaming(customPrompt: customPrompt, transcriptionMetadata: nil)
    }
    func refineStreaming(
        customPrompt: String?, transcriptionMetadata: TranscriptionMetadata?
    ) -> AsyncThrowingStream<RefinementEvent, Error> {
        AsyncThrowingStream { next in continuation.withLock { $0 = next } }
    }
    func refineText(_ text: String, customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        refineStreaming(customPrompt: customPrompt)
    }
    func finish() {
        let next = continuation.withLock { value in let next = value; value = nil; return next }
        next?.yield(.chunk("synthetic refined。"))
        next?.finish()
    }
    func cancel() { finish() }
}

final class DismissClipboardService: ClipboardService, Sendable {
    private let copies = Mutex<[String]>([])
    private let pasteCalls = Mutex(0)
    let gate = QuickRecordStartGate()
    var copied: [String] { copies.withLock { $0 } }
    var pasteCount: Int { pasteCalls.withLock { $0 } }
    var hasText: Bool { !copied.isEmpty }
    func copy(_ text: String) { copies.withLock { $0.append(text) } }
    func paste() -> String? { copied.last }
    func clear() { copies.withLock { $0 = [] } }
    func simulatePaste() async throws {
        pasteCalls.withLock { $0 += 1 }
        await gate.suspendStart()
    }
}

@MainActor
final class ImmediateDismissFixture {
    enum Failure: Error { case synthetic }
    let runtime = RuntimeFixture()
    let hotkeys = TestGlobalHotkeyService()
    let recording: QuickRecordRecordingUseCase
    let transcription: QuickRecordTranscriptionUseCase
    let refinement = DismissRefinementUseCase()
    let clipboard = DismissClipboardService()
    let saveGate = QuickRecordStartGate()
    var model: QuickRecordingViewModel?
    var delegate: AppDelegate?
    var source: RecordingSource?
    var visible = false
    var closes = 0
    var ends = 0
    var events: [(String, [String: String], Bool)] = []
    var saved: [(String, String)] = []
    var saveFails = false
    private var dismissalWaiter: CheckedContinuation<Void, Never>?

    init(startGate: QuickRecordStartGate? = nil, stopGate: QuickRecordStartGate? = nil,
         startFails: Bool = false, stopFails: Bool = false, hasResult: Bool = true,
         stopError: Error? = nil) {
        let transcription = QuickRecordTranscriptionUseCase()
        self.transcription = transcription
        recording = QuickRecordRecordingUseCase(
            startError: startFails ? Failure.synthetic : nil, startGate: startGate,
            operationRecorder: QuickRecordOperationRecorder(), stopGate: stopGate,
            stopError: stopError ?? (stopFails ? Failure.synthetic : nil),
            onStop: { if hasResult { transcription.sendFinalText("synthetic raw") } },
            appleTextOnStart: (hasResult || stopFails) ? "synthetic Apple partial" : nil
        )
        model = QuickRecordingViewModel(recordingUseCase: recording, transcriptionUseCase: transcription,
                                       refinementUseCase: refinement, clipboardService: clipboard)
    }

    func launch(recognitionTimeout: Duration? = nil) async {
        let delegate = AppDelegate(
            productTelemetryNotificationCenter: NotificationCenter(), startup: AppStartup {},
            serviceContainer: runtime.makeContainer(), hotkeyService: hotkeys,
            startupInitializePersistence: {}, startupScheduleQuickRecordingPrewarm: {},
            quickRecordTryStart: { [self] requested in
                guard source == nil else { return false }; source = requested; return true
            },
            quickRecordActiveSource: { [self] in source },
            quickRecordEnd: { [self] in source = nil; ends += 1 },
            quickRecordShowWindow: { [self] in visible = true },
            quickRecordViewModel: { [self] in model },
            quickRecordHideWindow: { [self] in visible = false; model = nil; closes += 1 },
            quickRecordDismissWindow: { [self] in
                let wasVisible = visible
                visible = false
                dismissalWaiter?.resume()
                dismissalWaiter = nil
                return wasVisible
            },
            quickRecordSaveSession: { [self] raw, final in
                saved.append((raw, final)); await saveGate.suspendStart()
                if saveFails { throw Failure.synthetic }
            },
            quickRecordTrack: { [self] name, properties in events.append((name, properties, visible)) }
        )
        if let recognitionTimeout { delegate.quickRecordRecognitionTimeout = recognitionTimeout }
        self.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate.waitForPendingStartup()
    }

    func remove() { delegate = nil; runtime.remove() }

    func waitForVisualDismissal() async {
        guard visible else { return }
        await withCheckedContinuation { dismissalWaiter = $0 }
    }

    func expectVisibleAndBusy() {
        #expect(visible)
        #expect(source == .quickRecording)
        #expect(model != nil)
        #expect(closes == 0)
        #expect(ends == 0)
    }

    func expectHiddenAndBusy() {
        #expect(!visible)
        #expect(source == .quickRecording)
        #expect(model != nil)
    }

    func expectClean() {
        #expect(!visible)
        #expect(source == nil)
        #expect(model == nil)
        #expect(closes == 1)
        #expect(ends == 1)
    }
}

@MainActor
func assertQuickRecordTimingEvents(_ fixture: ImmediateDismissFixture) {
    #expect(fixture.events.map(\.0) == ["quick_record.fn_released", "quick_record.panel_closed"])
    guard fixture.events.count == 2 else { return }
    let release = fixture.events[0], close = fixture.events[1]
    #expect(release.2)
    #expect(!close.2)
    #expect(Set(release.1.keys) == ["source", "session_id"])
    #expect(Set(close.1.keys) == ["source", "session_id", "duration_ms"])
    #expect(release.1["source"] == "quick" && close.1["source"] == "quick")
    #expect(release.1["session_id"] == close.1["session_id"])
    #expect(UUID(uuidString: release.1["session_id"] ?? "") != nil)
    #expect((Double(close.1["duration_ms"] ?? "") ?? -1) >= 0)
}

@MainActor
func waitForDismissBoundary(_ condition: () -> Bool) async throws {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
    try #require(condition(), "Timed out at controlled quick-record boundary")
}
#endif
