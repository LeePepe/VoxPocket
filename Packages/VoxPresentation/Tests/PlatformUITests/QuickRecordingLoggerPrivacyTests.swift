#if os(macOS)
import XCTest
import Combine
import Foundation
import Synchronization
import PlatformAdapters
import LLMKit
import TranscriptionKit
import UseCases
import LokiKit
@testable import PlatformUI

/// 宪法 IV 隐私门 — 转写/精炼/最终文本内容禁止落入 logger message 或 context value。
///
/// 用捕获型假 Logger + 哨兵短语跑一遍 stopRecording → completeWithText 路径,
/// 断言哨兵短语从未出现在任何 log message 或 context value 里。
@MainActor
final class QuickRecordingLoggerPrivacyTests: XCTestCase {

    /// 独特的哨兵短语 —— 只要它出现在日志里, 就说明有内容泄漏。
    /// 用 zero-width joiner-free ASCII+汉字混合, 避免与代码中出现的固定字符串冲突。
    private static let sentinelTranscription = "SENTINEL-XYZZY-哨兵短语-DO-NOT-LOG-42"
    private static let sentinelRefined = "SENTINEL-REFINED-PLUGH-精炼哨兵-91"

    func testLoggerDoesNotLeakTranscriptionOrRefinedTextContent() async throws {
        let capture = CapturingLogger()
        let recording = FakeRecordingUseCaseP()
        let transcription = FakeTranscriptionUseCaseP()
        let refinement = FakeRefinementUseCaseP(streamedChunks: [Self.sentinelRefined])
        let clipboard = FakeClipboardServiceP()

        let viewModel = QuickRecordingViewModel(
            recordingUseCase: recording,
            transcriptionUseCase: transcription,
            refinementUseCase: refinement,
            clipboardService: clipboard,
            streamingCoordinator: nil,
            logger: capture,
            telemetryService: nil
        )

        // 走完整快捷录音流水线:
        // start → 灌入 sentinel liveText → stop (触发 finalResult 分支及各 fallback 日志) → refinement 流入 sentinelRefined → completeWithText
        await viewModel.startRecording()
        transcription.sendLiveText(Self.sentinelTranscription)
        transcription.sendFinalText(Self.sentinelTranscription)
        await viewModel.stopRecording()

        // 等 refinement streaming task 落地 completeWithText
        try? await Task.sleep(nanoseconds: 300_000_000)

        // 至少要有一条 log 被记录, 否则说明未跑到关键路径, 测试会假绿。
        XCTAssertFalse(capture.entries.isEmpty, "no log entries captured — path did not execute")

        // 断言哨兵短语从未出现在 message 或任何 context value 里。
        for entry in capture.entries {
            XCTAssertFalse(
                entry.message.contains(Self.sentinelTranscription),
                "transcription content leaked to log message: \(entry.message)"
            )
            XCTAssertFalse(
                entry.message.contains(Self.sentinelRefined),
                "refined content leaked to log message: \(entry.message)"
            )
            for (key, value) in entry.context {
                let stringified = String(describing: value)
                XCTAssertFalse(
                    stringified.contains(Self.sentinelTranscription),
                    "transcription content leaked to context value (key=\(key)): \(stringified)"
                )
                XCTAssertFalse(
                    stringified.contains(Self.sentinelRefined),
                    "refined content leaked to context value (key=\(key)): \(stringified)"
                )
            }
        }
    }
}

// MARK: - Capturing Logger

private struct CapturedLogEntry: Sendable {
    let level: LogLevel
    let message: String
    let context: [String: String]
}

private final class CapturingLogger: LokiKit.Logger {
    // 宪法约束: minimumLevel 需可读写但 Logger 是 Sendable — 用 Mutex 守护。
    private let _minimumLevel = Mutex<LogLevel>(.debug)
    var minimumLevel: LogLevel {
        get { _minimumLevel.withLock { $0 } }
        set { _minimumLevel.withLock { $0 = newValue } }
    }

    // 共享可变状态用 Synchronization.Mutex, 禁止 ad-hoc NSLock (constitution line 30).
    private let _entries = Mutex<[CapturedLogEntry]>([])

    var entries: [CapturedLogEntry] { _entries.withLock { $0 } }

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        file: String,
        function: String,
        line: Int
    ) {
        let msg = message()
        _entries.withLock { $0.append(CapturedLogEntry(level: level, message: msg, context: [:])) }
    }

    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        let msg = message()
        // Stringify context values eagerly to preserve them across the assertion boundary
        // (also drops the non-Sendable [String: Any] before it crosses the Mutex boundary).
        var stringified: [String: String] = [:]
        for (k, v) in context {
            stringified[k] = String(describing: v)
        }
        _entries.withLock { $0.append(CapturedLogEntry(level: level, message: msg, context: stringified)) }
    }
}

// MARK: - Test doubles (locally scoped to avoid clashing with other test files)

/// `@unchecked Sendable` justified: Combine bridging — all state is held in Combine subjects
/// (`CurrentValueSubject`), which provide their own thread-safety.
private final class FakeRecordingUseCaseP: RecordingUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let levelSubject = CurrentValueSubject<Float, Never>(0)

    var state: RecordingState { stateSubject.value }
    var statePublisher: AnyPublisher<RecordingState, Never> { stateSubject.eraseToAnyPublisher() }
    var audioLevelPublisher: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    func startRecording() async throws { stateSubject.send(.recording(duration: 0)) }
    func stopRecording() async throws { stateSubject.send(.idle) }
    func pauseRecording() { stateSubject.send(.paused(duration: 0)) }
    func resumeRecording() { stateSubject.send(.recording(duration: 0)) }
    func cancelRecording() { stateSubject.send(.idle) }
    func checkPermission() async -> Bool { true }
    func requestPermission() async -> Bool { true }
}

/// `@unchecked Sendable` justified: Combine bridging for publishers, `Mutex` for the two
/// non-publisher mutable fields (`_currentLanguage`, `_snapshotGateActive`) per constitution
/// line 30 (no ad-hoc locks).
private final class FakeTranscriptionUseCaseP: TranscriptionUseCase, @unchecked Sendable {
    private let liveTextSubject = CurrentValueSubject<String, Never>("")
    private let finalResultSubject = PassthroughSubject<TranscriptionResult, Error>()
    private let snapshotSubject = PassthroughSubject<String, Never>()

    private let _currentLanguage = Mutex<Locale>(Locale(identifier: "zh-Hans"))
    private let _snapshotGateActive = Mutex<Bool>(false)

    var liveTextPublisher: AnyPublisher<String, Never> { liveTextSubject.eraseToAnyPublisher() }
    var finalResultPublisher: AnyPublisher<TranscriptionResult, Error> { finalResultSubject.eraseToAnyPublisher() }
    var snapshotPublisher: AnyPublisher<String, Never> { snapshotSubject.eraseToAnyPublisher() }
    var currentLanguage: Locale { _currentLanguage.withLock { $0 } }
    var supportedLanguages: [Locale] { [currentLanguage] }
    var snapshotGateActive: Bool {
        get { _snapshotGateActive.withLock { $0 } }
        set { _snapshotGateActive.withLock { $0 = newValue } }
    }

    func setLanguage(_ locale: Locale) { _currentLanguage.withLock { $0 = locale } }
    func commitCurrentTranscription() async throws {}
    func clearLiveText() { liveTextSubject.send("") }

    func sendLiveText(_ text: String) { liveTextSubject.send(text) }
    func sendFinalText(_ text: String) {
        finalResultSubject.send(
            TranscriptionResult(
                text: text,
                type: .final,
                confidence: nil,
                timestamp: Date(),
                locale: currentLanguage
            )
        )
    }
}

/// `@unchecked Sendable` justified: Combine bridging — mutable state held in `CurrentValueSubject`;
/// `streamedChunks` is an immutable `let`.
private final class FakeRefinementUseCaseP: RefinementUseCase, @unchecked Sendable {
    private let stateSubject = CurrentValueSubject<RefinementState, Never>(.idle)
    private let streamedChunks: [String]

    init(streamedChunks: [String] = []) { self.streamedChunks = streamedChunks }

    var state: RefinementState { stateSubject.value }
    var statePublisher: AnyPublisher<RefinementState, Never> { stateSubject.eraseToAnyPublisher() }
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
        _ = customPrompt; _ = transcriptionMetadata
        return AsyncThrowingStream { continuation in
            for chunk in streamedChunks { continuation.yield(RefinementEvent.chunk(chunk)) }
            continuation.finish()
        }
    }
    func cancel() { stateSubject.send(.idle) }
    func refineText(_ text: String, customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error> {
        _ = text; _ = customPrompt
        return AsyncThrowingStream { continuation in
            for chunk in streamedChunks { continuation.yield(RefinementEvent.chunk(chunk)) }
            continuation.finish()
        }
    }
}

/// `@unchecked Sendable` justified: `Mutex` guards the single mutable field (`copiedText`);
/// no ad-hoc locks (constitution line 30).
private final class FakeClipboardServiceP: ClipboardService, @unchecked Sendable {
    private let _copiedText = Mutex<String?>(nil)
    var copiedText: String? { _copiedText.withLock { $0 } }
    var hasText: Bool { false }
    func copy(_ text: String) { _copiedText.withLock { $0 = text } }
    func paste() -> String? { nil }
    func clear() {}
    func simulatePaste() async throws {}
}
#endif
