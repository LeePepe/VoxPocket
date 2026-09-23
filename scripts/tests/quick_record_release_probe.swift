import Foundation

// 只替换设备与存储边界；Fn 的两个处理方法及窗口启动方法由脚本注入生产源码。
@MainActor
final class FakeAppDelegate {
    let serviceContainer = FakeServiceContainer()
    let windowManager = FakeWindowManager()
    let logger = FakeLogger()
    var quickRecordStartCount = 0
    var quickRecordStopCount = 0
    func press() async { await handleQuickRecordStart() }
    func release() async { await handleQuickRecordStop() }
    // PRODUCTION_HANDLERS
}

enum FakeWindowType: String { case quickRecording, fullPanel }
enum FakeRecorderStatus { case idle, listening, transcribing, refining, done, error }

struct FakeLogger {
    enum Level { case debug }
    func debug(_ message: String) {}
    func log(_ level: Level, _ message: String, context: [String: Any]) {}
}

@MainActor
final class FakeServiceContainer {
    var activeRecordingSource: FakeWindowType?
    let sessionUseCase = FakeSessionUseCase()
    func tryStartRecording(source: FakeWindowType) -> Bool {
        guard activeRecordingSource == nil else { return false }
        activeRecordingSource = source
        return true
    }
    func endRecording() { activeRecordingSource = nil }
    func initializePersistence() async {}
}

@MainActor
final class FakeSessionUseCase {
    func saveCompletedSession(title: String?, rawText: String, refinedText: String) async throws {}
}

@MainActor
final class FakeWindowManager {
    var viewModels: [FakeWindowType: Any] = [:]
    var isVisible = false
    var showCount = 0
    func showWindow(_ type: FakeWindowType) {
        showCount += 1
        isVisible = true
        viewModels[type] = QuickRecordingViewModel()
    }
    func hideWindow(_ type: FakeWindowType) {
        isVisible = false
        viewModels[type] = nil
    }
    func getQuickRecordingViewModel() -> QuickRecordingViewModel? {
        viewModels[.quickRecording] as? QuickRecordingViewModel
    }
    // PRODUCTION_WINDOW_START
}

// 仅供原样提取的生产窗口方法使用；测试替身仍以 Fake 命名。
typealias QuickRecordingViewModel = FakeQuickRecordingViewModel

// 保留真实 ViewModel 的启动契约：启动中的 stop 先返回，启动恢复后再回调无结果。
@MainActor
final class FakeQuickRecordingViewModel {
    var onComplete: ((String) -> Void)?
    var onNoResult: (() -> Void)?
    var rawTranscription = ""
    var recorderStatus = FakeRecorderStatus.idle
    var isStartingRecording = false
    var shouldStopAfterStart = false
    var startContinuation: CheckedContinuation<Void, Never>?
    var stopCount = 0
    var noResultCount = 0
    var callbacksReadyAtStart = false

    func startRecording() async {
        callbacksReadyAtStart = onComplete != nil && onNoResult != nil
        isStartingRecording = true
        await withCheckedContinuation { startContinuation = $0 }
        isStartingRecording = false
        recorderStatus = .listening
        if shouldStopAfterStart { await stopRecording() }
    }
    func finishStarting() {
        startContinuation?.resume()
        startContinuation = nil
    }
    func stopRecording() async {
        if isStartingRecording {
            shouldStopAfterStart = true
            return
        }
        guard recorderStatus == .listening else { return }
        stopCount += 1
        recorderStatus = .idle
        noResultCount += 1
        onNoResult?()
    }
}

struct ProbeFailure: Error { let message: String }

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
        throw ProbeFailure(message: "Timed out waiting for deterministic startup/callback boundary")
    }

    @MainActor
    static func exerciseRelease(duringStart: Bool, delegate: FakeAppDelegate) async throws {
        let start = Task { await delegate.press() }
        try await waitUntil { delegate.windowManager.getQuickRecordingViewModel()?.startContinuation != nil }
        let model = delegate.windowManager.getQuickRecordingViewModel()!
        if duringStart {
            await delegate.release()
            try require(model.shouldStopAfterStart, "Release must be remembered during startup")
        }
        model.finishStarting()
        await start.value
        if !duringStart { await delegate.release() }
        // onNoResult 的宿主清理由 MainActor Task 执行。
        for _ in 0..<100 { await Task.yield() }
        try require(!delegate.windowManager.isVisible,
                    "FAIL: Fn released duringStart=\(duringStart), empty panel remains visible")
        try require(delegate.serviceContainer.activeRecordingSource == nil,
                    "FAIL: quick-record ownership remains held")
        try require(model.stopCount == 1 && model.noResultCount == 1,
                    "Stop and no-result must each occur exactly once")
        try require(model.callbacksReadyAtStart, "Both callbacks must be installed before startup")
    }

    @MainActor
    static func main() async throws {
        let delegate = FakeAppDelegate()
        try await exerciseRelease(duringStart: true, delegate: delegate)
        print("PASS: release during suspended startup dismisses panel and releases ownership")
        try await exerciseRelease(duringStart: true, delegate: delegate)
        print("PASS: next quick tap starts a fresh session and dismisses again")
        try await exerciseRelease(duringStart: false, delegate: delegate)
        print("PASS: ordinary empty recording still dismisses")
        delegate.serviceContainer.activeRecordingSource = .fullPanel
        let showCount = delegate.windowManager.showCount
        await delegate.press()
        await delegate.release()
        try require(delegate.windowManager.showCount == showCount, "Busy source must not show a new panel")
        try require(delegate.serviceContainer.activeRecordingSource == .fullPanel,
                    "Rejected quick tap must preserve the other recording source")
        print("PASS: rejected quick tap leaves the other recording source unchanged")
    }
}
