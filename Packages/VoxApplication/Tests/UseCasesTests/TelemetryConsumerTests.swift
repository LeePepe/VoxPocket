import XCTest
import Combine
import Foundation
import Synchronization
import CoreModels
import LLMKit
import LokiKit
@testable import UseCases

/// 仅验证生产 UseCase 的事件边界，不构造真实遥测、模型或持久化服务。
final class TelemetryConsumerTests: XCTestCase {
    func testRefinementSuccessPreservesEditingWithTelemetryEnabledOrDisabled() async throws {
        for enabled in [true, false] {
            let telemetry = FakeConsumerTelemetry(isEnabled: enabled)
            let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
            let llm = FakeConsumerLLM()
            let useCase = DefaultRefinementUseCase(llmService: llm, editing: editing, telemetry: telemetry)

            try await useCase.refine(customPrompt: FakeConsumerContent.prompt)

            XCTAssertEqual(editing.currentText, FakeConsumerContent.output)
            XCTAssertEqual(useCase.state, .completed)
            XCTAssertEqual(llm.lastRequest?.text, FakeConsumerContent.input)
            XCTAssertEqual(llm.lastRequest?.customPrompt, FakeConsumerContent.prompt)
            if enabled {
                assertConsumerMetric(telemetry.events, name: "refinement.completed", key: "duration_ms")
            } else {
                XCTAssertTrue(telemetry.events.isEmpty)
            }
            assertConsumerPrivacy(telemetry.events)
        }
    }

    func testRefinementCompletesWhileFakeAsyncFlushIsDeferred() async throws {
        let telemetry = FakeConsumerTelemetry()
        let editing = FakeConsumerEditing(text: FakeConsumerContent.input)
        let useCase = DefaultRefinementUseCase(
            llmService: FakeConsumerLLM(), editing: editing, telemetry: telemetry
        )
        let flush = Task { await telemetry.flush() }
        await telemetry.flushStarted.wait()

        do {
            try await useCase.refine(customPrompt: FakeConsumerContent.prompt)
        } catch {
            telemetry.releaseFlush.signal()
            await flush.value
            throw error
        }

        XCTAssertEqual(useCase.state, .completed)
        XCTAssertEqual(editing.currentText, FakeConsumerContent.output)
        XCTAssertFalse(telemetry.flushCompleted)
        assertConsumerMetric(telemetry.events, name: "refinement.completed", key: "duration_ms")
        assertConsumerPrivacy(telemetry.events)
        telemetry.releaseFlush.signal()
        await flush.value
        XCTAssertTrue(telemetry.flushCompleted)
        // track 是本地同步捕获；此测试不声称任意第三方同步 sink 都不会阻塞。
    }
}

enum FakeConsumerContent {
    static let input = "SYNTHETIC_INPUT_SENTINEL"
    static let output = "SYNTHETIC_OUTPUT_SENTINEL"
    static let prompt = "SYNTHETIC_PROMPT_SENTINEL"
    static let errorBody = "SYNTHETIC_ERROR_BODY_SENTINEL"
    static let all = [input, output, prompt, errorBody]
}

struct FakeConsumerError: LocalizedError, Equatable {
    let detail: String
    var errorDescription: String? { detail }
    static let sensitive = FakeConsumerError(detail: FakeConsumerContent.all.joined(separator: " "))
}

func assertConsumerPrivacy(
    _ events: [TelemetryEvent], file: StaticString = #filePath, line: UInt = #line
) {
    for event in events {
        let fields = [event.name] + Array(event.properties.keys) + Array(event.properties.values)
        for sentinel in FakeConsumerContent.all {
            XCTAssertFalse(fields.contains { $0.contains(sentinel) }, file: file, line: line)
        }
    }
}

func assertConsumerMetric(
    _ events: [TelemetryEvent], name: String, key: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(events.count, 1, file: file, line: line)
    guard let event = events.first else { return }
    XCTAssertEqual(event.name, name, file: file, line: line)
    XCTAssertEqual(Set(event.properties.keys), Set([key]), file: file, line: line)
    let value = Double(event.properties[key] ?? "")
    XCTAssertNotNil(value, file: file, line: line)
    if let value { XCTAssertTrue(value.isFinite && value >= 0, file: file, line: line) }
}

/// 所有捕获状态都在 Mutex 内；flush 仅等待内存信号，不接触传输或文件。
final class FakeConsumerTelemetry: TelemetryService {
    private struct State {
        var enabled: Bool
        var events: [TelemetryEvent] = []
        var flushCompleted = false
    }
    private let state: Mutex<State>
    let flushStarted = FakeConsumerSignal()
    let releaseFlush = FakeConsumerSignal()

    init(isEnabled: Bool = true) { state = Mutex(State(enabled: isEnabled)) }
    var isEnabled: Bool {
        get { state.withLock { $0.enabled } }
        set { state.withLock { $0.enabled = newValue } }
    }
    var events: [TelemetryEvent] { state.withLock { $0.events } }
    var flushCompleted: Bool { state.withLock { $0.flushCompleted } }

    func track(_ event: TelemetryEvent) {
        state.withLock { if $0.enabled { $0.events.append(event) } }
    }
    func track(name: String, properties: [String: String]) {
        track(TelemetryEvent(name: name, properties: properties))
    }
    func flush() async {
        flushStarted.signal()
        await releaseFlush.wait()
        state.withLock { $0.flushCompleted = true }
    }
    func resetIdentifier() {}
}

/// 一次性异步信号；先 signal 后 wait 同样有效，不使用 sleep 或阻塞等待。
final class FakeConsumerSignal: Sendable {
    private struct State {
        var signalled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock {
                if $0.signalled { return true }
                $0.waiters.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }
    func signal() {
        let waiters = state.withLock {
            $0.signalled = true
            let waiters = $0.waiters
            $0.waiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}

final class FakeConsumerLLM: LLMService {
    enum Outcome: Sendable {
        case success, failure, cancellation, suspended
    }
    private struct State {
        var request: RefinementRequest?
        var cancelCount = 0
    }
    private let state = Mutex(State())
    private let outcome: Outcome
    let started = FakeConsumerSignal()
    let release = FakeConsumerSignal()
    let streamTerminated = FakeConsumerSignal()

    init(outcome: Outcome = .success) { self.outcome = outcome }
    var lastRequest: RefinementRequest? { state.withLock { $0.request } }
    var cancelCount: Int { state.withLock { $0.cancelCount } }
    var availableProviders: [LLMProviderType] { [] }
    var currentProvider: LLMProvider? { nil }
    var currentProviderType: LLMProviderType? { nil }
    func setProvider(_ config: LLMProviderConfig) throws {}
    func complete(prompt: String) async throws -> String { FakeConsumerContent.output }
    func completeStreaming(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementResponse {
        state.withLock { $0.request = request }
        started.signal()
        switch outcome {
        case .failure: throw FakeConsumerError.sensitive
        case .cancellation: throw CancellationError()
        case .suspended:
            await release.wait()
            try Task.checkCancellation()
        case .success: break
        }
        return RefinementResponse(
            originalText: request.text, refinedText: FakeConsumerContent.output,
            intentAnalysis: IntentAnalysis(), toneAnalysis: ToneAnalysis(), missingAnalysisSteps: []
        )
    }

    func refineStreaming(_ request: RefinementRequest) async throws -> AsyncThrowingStream<String, Error> {
        state.withLock { $0.request = request }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.onTermination = { [streamTerminated] _ in streamTerminated.signal() }
            continuation.yield(FakeConsumerContent.output)
            switch outcome {
            case .success: continuation.finish()
            case .failure: continuation.finish(throwing: FakeConsumerError.sensitive)
            case .cancellation: continuation.finish(throwing: CancellationError())
            case .suspended: break
            }
        }
        started.signal()
        return stream
    }

    func cancel() {
        state.withLock { $0.cancelCount += 1 }
    }
    func validateCurrentProvider() async -> Bool { true }
}

/// 测试只读取当前文本；publisher 是值快照，不需要 Combine unchecked 桥接。
final class FakeConsumerEditing: EditingUseCase {
    private struct State {
        var text: String
        var anchor: Int?
        var locked = false
    }
    private let state: Mutex<State>
    private let replacementError: FakeConsumerError?

    init(text: String, replacementError: FakeConsumerError? = nil) {
        state = Mutex(State(text: text))
        self.replacementError = replacementError
    }
    var currentText: String { state.withLock { $0.text } }
    var currentTextPublisher: AnyPublisher<String, Never> { Just(currentText).eraseToAnyPublisher() }
    var voiceAnchorLocation: Int? { state.withLock { $0.anchor } }
    var isVoiceZoneLocked: Bool { state.withLock { $0.locked } }
    func replaceAll(with text: String) throws {
        if let replacementError { throw replacementError }
        state.withLock { $0.text = text }
    }
    func applyEdit(range: CoreModels.TextRange, newText: String) throws {}
    func insert(_ text: String, at location: Int) throws {}
    func delete(range: CoreModels.TextRange) throws {}
    func append(_ text: String) throws { state.withLock { $0.text += text } }
    func mergeRecentEdits() {}
    func setVoiceAnchor(_ location: Int) { state.withLock { $0.anchor = location } }
    func clearVoiceAnchor() { state.withLock { $0.anchor = nil } }
    func setVoiceZoneLocked(_ locked: Bool) { state.withLock { $0.locked = locked } }
    func replaceVoiceZone(with text: String) throws { try replaceAll(with: text) }
}
