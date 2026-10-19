import Foundation

// 生产 handlers、会话类型及事件目录原样注入；只替换设备、窗口与存储边界。
@MainActor
final class FakeAppDelegate {
    let serviceContainer = FakeServiceContainer()
    let windowManager = FakeWindowManager()
    let logger = FakeLogger()
    let productTelemetryNotificationCenter = NotificationCenter()
    var quickRecordStartCount = 0
    var quickRecordStopCount = 0
    let quickRecordTryStart: (@MainActor @Sendable (RecordingSource) -> Bool)? = nil
    let quickRecordActiveSource: (@MainActor @Sendable () -> RecordingSource?)? = nil
    let quickRecordEnd: (@MainActor @Sendable () -> Void)? = nil
    let quickRecordShowWindow: (@MainActor @Sendable () -> Void)? = nil
    let quickRecordViewModel: (@MainActor @Sendable () -> QuickRecordingViewModel?)? = nil
    let quickRecordHideWindow: (@MainActor @Sendable () -> Void)? = nil
    let quickRecordDismissWindow: (@MainActor @Sendable () -> Bool)? = nil
    let quickRecordSaveSession: (@MainActor @Sendable (String, String) async throws -> Void)? = nil
    let quickRecordTrack: (@MainActor @Sendable (String, [String: String]) -> Void)? = nil
    private var quickRecordingSession: QuickRecordingSession?
    // PRODUCTION_SESSION
    func press() async { await handleQuickRecordStart() }
    func release() async { await handleQuickRecordStop() }
    // PRODUCTION_HANDLERS
}

// PRODUCTION_EVENT_NAMES
enum FakeWindowType: String { case quickRecording, fullPanel }
typealias RecordingSource = FakeWindowType
enum FakeRecorderStatus { case idle, listening, transcribing, refining, done, error }
struct FakeLogger {
    enum Level { case debug }
    func debug(_ message: String) {}
    func log(_ level: Level, _ message: String, context: [String: Any]) {}
}
struct ProbeFailure: Error { let message: String }

@MainActor
final class FakeTelemetry {
    var events: [(name: String, properties: [String: String])] = []
    func track(name: String, properties: [String: String]) { events.append((name, properties)) }
}

@MainActor
enum ProductTelemetryNotificationBoundary {
    static var actions: [String] = []
    static func postQuickRecordStarted(to: NotificationCenter) { actions.append("started") }
    static func postQuickRecordStopped(to: NotificationCenter) { actions.append("stopped") }
}

@MainActor
final class ProbeGate {
    var entered = false
    var released = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func open() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class FakeServiceContainer {
    var activeRecordingSource: FakeWindowType?
    let sessionUseCase = FakeSessionUseCase()
    let telemetryService = FakeTelemetry()
    var endCount = 0
    func tryStartRecording(source: FakeWindowType) -> Bool {
        guard activeRecordingSource == nil else { return false }
        activeRecordingSource = source
        return true
    }
    func endRecording() { activeRecordingSource = nil; endCount += 1 }
    func initializePersistence() async {}
}

@MainActor
final class FakeSessionUseCase {
    var gate: ProbeGate?
    var shouldFail = false
    var saves: [(String, String)] = []
    func saveCompletedSession(title: String?, rawText: String, refinedText: String) async throws {
        saves.append((rawText, refinedText))
        if let gate { await gate.wait() }
        if shouldFail { throw ProbeFailure(message: "synthetic save failure") }
    }
}

@MainActor
final class FakeWindowManager {
    var viewModels: [FakeWindowType: Any] = [:]
    var isVisible = false
    var showCount = 0
    var closeCount = 0
    var dismissCount = 0
    var missingModel = false
    func showWindow(_ type: FakeWindowType) {
        showCount += 1
        isVisible = true
        if !missingModel { viewModels[type] = QuickRecordingViewModel() }
    }
    func dismissQuickRecordingWindow() -> Bool {
        guard isVisible else { return false }
        isVisible = false
        dismissCount += 1
        return true
    }
    func hideWindow(_ type: FakeWindowType) {
        isVisible = false
        closeCount += 1
        viewModels[type] = nil
    }
    func getQuickRecordingViewModel() -> QuickRecordingViewModel? {
        viewModels[.quickRecording] as? QuickRecordingViewModel
    }
    // PRODUCTION_WINDOW_START
}

typealias QuickRecordingViewModel = FakeQuickRecordingViewModel

// 保留真实 VM 的启动待停止和非流式润色独立任务契约。
@MainActor
final class FakeQuickRecordingViewModel {
    var onComplete: ((String) -> Void)?
    var onNoResult: (() -> Void)?
    var rawTranscription = ""
    var recorderStatus = FakeRecorderStatus.idle
    var isStartingRecording = false
    var shouldStopAfterStart = false
    var startContinuation: CheckedContinuation<Void, Never>?
    var stopGate: ProbeGate?
    var refinementGate: ProbeGate?
    var pasteGate: ProbeGate?
    var startFails = false
    var stopFails = false
    var hasResult = false
    var stopCount = 0
    var pasteCount = 0
    var noResultCount = 0
    var callbacksReadyAtStart = false

    func startRecording() async {
        callbacksReadyAtStart = onComplete != nil && onNoResult != nil
        isStartingRecording = true
        await withCheckedContinuation { startContinuation = $0 }
        isStartingRecording = false
        if startFails { recorderStatus = .error; return }
        recorderStatus = .listening
        if shouldStopAfterStart { await stopRecording() }
    }
    func finishStarting() { startContinuation?.resume(); startContinuation = nil }
    func stopRecording() async {
        if isStartingRecording { shouldStopAfterStart = true; return }
        guard recorderStatus == .listening else { return }
        stopCount += 1
        recorderStatus = .transcribing
        if let stopGate { await stopGate.wait() }
        if stopFails { recorderStatus = .error; return }
        guard hasResult else {
            recorderStatus = .idle
            noResultCount += 1
            onNoResult?()
            return
        }
        rawTranscription = "synthetic raw"
        recorderStatus = .refining
        Task { await self.finishRefinement() }
    }
    func finishRefinement() async {
        if let refinementGate { await refinementGate.wait() }
        if let pasteGate { await pasteGate.wait() }
        pasteCount += 1
        recorderStatus = .done
        onComplete?("synthetic refined")
    }
}

@main
struct QuickRecordReleaseProbe {
    @MainActor
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ProbeFailure(message: message) }
    }
    @MainActor
    static func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if predicate() { return }
            await Task.yield()
        }
        throw ProbeFailure(message: "Timed out waiting for deterministic boundary")
    }
    @MainActor
    static func start(_ delegate: FakeAppDelegate) async throws -> FakeQuickRecordingViewModel {
        let task = Task { await delegate.press() }
        try await waitUntil { delegate.windowManager.getQuickRecordingViewModel()?.startContinuation != nil }
        let model = delegate.windowManager.getQuickRecordingViewModel()!
        model.finishStarting()
        await task.value
        return model
    }
    @MainActor
    static func assertHiddenAndBusy(_ delegate: FakeAppDelegate) throws {
        try require(!delegate.windowManager.isVisible, "Panel must be hidden before background boundary")
        try require(delegate.serviceContainer.activeRecordingSource == .quickRecording,
                    "Background work must retain recording ownership")
        try require(delegate.windowManager.getQuickRecordingViewModel() != nil,
                    "Hidden panel must retain its background model")
    }
    @MainActor
    static func assertClean(_ delegate: FakeAppDelegate) throws {
        try require(!delegate.windowManager.isVisible, "Terminal panel must be hidden")
        try require(delegate.serviceContainer.activeRecordingSource == nil, "Terminal must release ownership")
        try require(delegate.windowManager.getQuickRecordingViewModel() == nil, "Terminal must release model")
    }
    @MainActor
    static func assertEvents(_ delegate: FakeAppDelegate, count: Int) throws {
        let events = delegate.serviceContainer.telemetryService.events
        try require(events.count == count * 2, "Each valid release must emit exactly one pair")
        for index in stride(from: 0, to: events.count, by: 2) {
            let release = events[index], close = events[index + 1]
            try require(release.name == "quick_record.fn_released", "Release event must come first")
            try require(close.name == "quick_record.panel_closed", "Close event must come after hide")
            try require(Set(release.properties.keys) == ["source", "session_id"], "Release privacy allowlist")
            try require(Set(close.properties.keys) == ["source", "session_id", "duration_ms"], "Close privacy allowlist")
            try require(release.properties["source"] == "quick" && close.properties["source"] == "quick", "Fixed source")
            try require(release.properties["session_id"] == close.properties["session_id"], "Same session ID")
            try require(UUID(uuidString: release.properties["session_id"] ?? "") != nil, "Random session ID")
            try require((Double(close.properties["duration_ms"] ?? "") ?? -1) >= 0, "Nonnegative duration")
        }
        try require(Set(events.compactMap { $0.name == "quick_record.fn_released" ? $0.properties["session_id"] : nil }).count == count,
                    "New sessions must have distinct IDs")
    }
    @MainActor
    static func exerciseRelease(duringStart: Bool, delegate: FakeAppDelegate) async throws {
        let task = Task { await delegate.press() }
        try await waitUntil { delegate.windowManager.getQuickRecordingViewModel()?.startContinuation != nil }
        let model = delegate.windowManager.getQuickRecordingViewModel()!
        if duringStart {
            await delegate.release()
            try assertHiddenAndBusy(delegate)
            try require(model.shouldStopAfterStart, "Release must be remembered during startup")
        }
        model.finishStarting()
        await task.value
        if !duringStart { await delegate.release() }
        try assertClean(delegate)
        try require(model.stopCount == 1 && model.noResultCount == 1, "Stop and no-result exactly once")
        try require(model.callbacksReadyAtStart, "Callbacks installed before startup")
    }
    @MainActor
    static func exerciseBackgroundCompletion(saveFails: Bool) async throws {
        let delegate = FakeAppDelegate()
        let model = try await start(delegate)
        model.hasResult = true
        let stop = ProbeGate(), refine = ProbeGate(), paste = ProbeGate(), save = ProbeGate()
        model.stopGate = stop; model.refinementGate = refine; model.pasteGate = paste
        delegate.serviceContainer.sessionUseCase.gate = save
        delegate.serviceContainer.sessionUseCase.shouldFail = saveFails
        let oldCompletion = model.onComplete, oldNoResult = model.onNoResult
        let release = Task { await delegate.release() }
        try await waitUntil { stop.entered }
        try assertHiddenAndBusy(delegate)
        try assertEvents(delegate, count: 1)
        await delegate.release()
        await delegate.press()
        try require(delegate.windowManager.showCount == 1, "Reject overlap while background is active")
        stop.open()
        await release.value
        try await waitUntil { refine.entered }
        try assertHiddenAndBusy(delegate)
        refine.open()
        try await waitUntil { paste.entered }
        try assertHiddenAndBusy(delegate)
        paste.open()
        try await waitUntil { save.entered }
        try assertHiddenAndBusy(delegate)
        oldCompletion?("duplicate must not save"); oldNoResult?()
        try assertHiddenAndBusy(delegate)
        save.open()
        try await waitUntil { delegate.serviceContainer.activeRecordingSource == nil }
        try assertClean(delegate)
        try require(model.stopCount == 1 && model.pasteCount == 1, "Stop and paste exactly once")
        let saved = delegate.serviceContainer.sessionUseCase.saves
        try require(saved.count == 1 && saved[0].0 == "synthetic raw" && saved[0].1 == "synthetic refined",
                    "Raw and final snapshots must survive hidden model")
        try require(delegate.windowManager.closeCount == 1 && delegate.serviceContainer.endCount == 1,
                    "Terminal cleanup exactly once, including save failure")
        _ = try await start(delegate)
        oldCompletion?("stale completion"); oldNoResult?()
        try require(delegate.windowManager.isVisible, "Old callbacks must not close next session")
        await delegate.release()
        try assertClean(delegate)
        try assertEvents(delegate, count: 2)
    }
    @MainActor
    static func exerciseErrors() async throws {
        for duringStart in [false, true] {
            let delegate = FakeAppDelegate()
            let startTask = Task { await delegate.press() }
            try await waitUntil { delegate.windowManager.getQuickRecordingViewModel()?.startContinuation != nil }
            let model = delegate.windowManager.getQuickRecordingViewModel()!
            model.startFails = true
            if duringStart { await delegate.release(); try assertHiddenAndBusy(delegate) }
            model.finishStarting()
            await startTask.value
            try assertClean(delegate)
            try require(model.stopCount == 0, "Startup error must not stop twice")
            try assertEvents(delegate, count: duringStart ? 1 : 0)
            try await exerciseRelease(duringStart: false, delegate: delegate)
        }
        let delegate = FakeAppDelegate()
        let model = try await start(delegate)
        model.stopFails = true
        await delegate.release()
        try assertClean(delegate)
        try assertEvents(delegate, count: 1)
        try await exerciseRelease(duringStart: false, delegate: delegate)
    }
    @MainActor
    static func exerciseRejectedAndMissing() async throws {
        let delegate = FakeAppDelegate()
        delegate.serviceContainer.activeRecordingSource = .fullPanel
        await delegate.press(); await delegate.release()
        try require(delegate.windowManager.showCount == 0, "Busy source must not show panel")
        try require(delegate.serviceContainer.activeRecordingSource == .fullPanel, "Preserve other source")
        try assertEvents(delegate, count: 0)
        delegate.serviceContainer.activeRecordingSource = nil
        delegate.windowManager.missingModel = true
        await delegate.press(); await delegate.release()
        try assertClean(delegate)
        try assertEvents(delegate, count: 0)
        delegate.windowManager.missingModel = false
        _ = try await start(delegate)
        delegate.windowManager.viewModels.removeValue(forKey: .quickRecording)
        await delegate.release()
        try assertClean(delegate)
        try assertEvents(delegate, count: 0)
    }
    @MainActor
    static func main() async throws {
        let delegate = FakeAppDelegate()
        try await exerciseRelease(duringStart: true, delegate: delegate)
        print("PASS: release during suspended startup immediately hides and later stops once")
        try await exerciseRelease(duringStart: true, delegate: delegate)
        print("PASS: next quick tap starts a fresh session and dismisses again")
        try await exerciseRelease(duringStart: false, delegate: delegate)
        print("PASS: ordinary empty recording still dismisses")
        try assertEvents(delegate, count: 3)
        try await exerciseBackgroundCompletion(saveFails: false)
        print("PASS: suspended stop, refinement, paste and save stay hidden; outputs and ownership preserved")
        try await exerciseBackgroundCompletion(saveFails: true)
        print("PASS: save failure cleans once; stale callbacks cannot close next recording")
        try await exerciseErrors()
        print("PASS: startup and stop errors hide, release ownership and permit retry")
        try await exerciseRejectedAndMissing()
        print("PASS: rejected source and missing model emit no timing events")
    }
}
