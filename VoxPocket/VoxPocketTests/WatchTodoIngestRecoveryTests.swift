import XCTest
import Combine
import Synchronization
import CoreModels
import Persistence
import UseCases
import PlatformAdapters
import VoxPocketKit
@testable import VoxPocket

final class WatchTodoIngestRecoveryTests: XCTestCase {
    func testActualUseCaseRecoversEachSaveWindowWithoutDuplicateRows() async throws {
        for window in 1...3 {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let captures = FaultWatchCaptures(base: DefaultVoiceCaptureRepository(directoryURL: folder), failureOnSave: window == 1 ? 1 : (window == 3 ? 2 : 0))
            let todos = FaultWatchTodos(base: DefaultVoiceTodoRepository(directoryURL: folder), failureOnSave: window == 2 ? 1 : 0)
            let useCase = DefaultVoiceCaptureAndTodoUseCase(captures: captures, todos: todos, runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: folder))
            let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 3, basename: "\(id.uuidString).m4a")
            let adapter = WatchTodoIngestAdapter(useCase: useCase)
            let transcript = WatchTranscribedCapture(rawTranscript: "整理会议纪要", refinedText: "整理会议纪要。")
            do { _ = try await adapter.ingest(captureID: id, transcript: transcript, metadata: metadata); XCTFail("Injected save window \(window) must fail") } catch {}
            // 新 adapter 与磁盘 repository 模拟进程重启，而非继续用预设的结果。
            let reopenedCaptures = DefaultVoiceCaptureRepository(directoryURL: folder)
            let reopenedTodos = DefaultVoiceTodoRepository(directoryURL: folder)
            let reopenedUseCase = DefaultVoiceCaptureAndTodoUseCase(captures: reopenedCaptures, todos: reopenedTodos, runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: folder))
            let recovered = WatchTodoIngestAdapter(useCase: reopenedUseCase)
            let result = try await recovered.ingest(captureID: id, transcript: transcript, metadata: metadata)
            let duplicate = try await recovered.ingest(captureID: id, transcript: transcript, metadata: metadata)
            let savedCaptures = try await reopenedCaptures.fetchAll(), savedTodos = try await reopenedTodos.fetchAll()
            XCTAssertEqual(result, duplicate)
            XCTAssertEqual(savedCaptures.count, 1, "window \(window)")
            XCTAssertEqual(savedTodos.count, 1, "window \(window)")
            XCTAssertEqual(savedCaptures.first?.linkedTodoID, savedTodos.first?.id)
            XCTAssertEqual(savedTodos.first?.sourceCaptureID, savedCaptures.first?.id)
            XCTAssertEqual(savedCaptures.first?.mode, .todo)
            XCTAssertEqual(savedCaptures.first?.deviceSource, .appleWatch)
            XCTAssertEqual(savedTodos.first?.deviceSource, .appleWatch)
            XCTAssertEqual(savedTodos.first?.localAudioFileName, metadata.basename)
        }
    }
    func testMissingLinkedTodoFailsSafelyAndDoesNotInventRows() async throws {
        let captures = DefaultVoiceCaptureRepository(), todos = DefaultVoiceTodoRepository()
        let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 3, basename: "\(id.uuidString).m4a")
        let capture = VoiceCapture(mode: .todo, rawTranscript: "整理纪要", localAudioFileName: metadata.basename, durationSeconds: 3, deviceSource: .appleWatch)
        try await captures.save(capture.withLinkedTodo(UUID()))
        let useCase = DefaultVoiceCaptureAndTodoUseCase(captures: captures, todos: todos, runner: DefaultAIRunnerExecutionService())
        let adapter = WatchTodoIngestAdapter(useCase: useCase)
        do { _ = try await adapter.ingest(captureID: id, transcript: WatchTranscribedCapture(rawTranscript: "整理纪要"), metadata: metadata); XCTFail("Missing link must not create another Todo") } catch {}
        let savedCaptures = try await captures.fetchAll(), savedTodos = try await todos.fetchAll()
        XCTAssertEqual(savedCaptures.count, 1); XCTAssertTrue(savedTodos.isEmpty)
    }
    func testConcurrentDuplicateCallsSerializeActualUseCase() async throws {
        let captures = DefaultVoiceCaptureRepository(), todos = DefaultVoiceTodoRepository()
        let useCase = DefaultVoiceCaptureAndTodoUseCase(captures: captures, todos: todos, runner: DefaultAIRunnerExecutionService())
        let adapter = WatchTodoIngestAdapter(useCase: useCase)
        let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 1, basename: "\(id.uuidString).m4a")
        let text = WatchTranscribedCapture(rawTranscript: "整理会议")
        async let first = adapter.ingest(captureID: id, transcript: text, metadata: metadata)
        async let second = adapter.ingest(captureID: id, transcript: text, metadata: metadata)
        let results = try await (first, second)
        XCTAssertEqual(results.0.todoID, results.1.todoID)
        let savedCaptures = try await captures.fetchAll(), savedTodos = try await todos.fetchAll()
        XCTAssertEqual(savedCaptures.count, 1); XCTAssertEqual(savedTodos.count, 1)
    }
    func testCompletionJournalFailureReplaysActualUseCaseWithoutDuplicateTodo() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 1, basename: "\(id.uuidString).m4a")
        let url = folder.appendingPathComponent(metadata.basename)
        try Data(repeating: 1, count: 32).write(to: url)
        let captures = DefaultVoiceCaptureRepository(directoryURL: folder), todos = DefaultVoiceTodoRepository(directoryURL: folder)
        let useCase = DefaultVoiceCaptureAndTodoUseCase(captures: captures, todos: todos, runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: folder))
        let adapter = WatchTodoIngestAdapter(useCase: useCase)
        let state = FileWatchIngestPersistence(directory: folder.appendingPathComponent("state"))
        let coordinator = WatchCaptureIngestCoordinator(inboxDirectory: folder, persistence: FaultWatchCompletion(base: state),
            transcriber: AppTestWatchTranscriber(), ingestTodo: { try await adapter.ingest(captureID: $0, transcript: $1, metadata: $2) }, sendReceipt: { _ in })
        do { try await coordinator.enqueue(fileURL: url, metadata: metadata); XCTFail("Completion journal fault must fail after real Todo save") } catch {}
        let reopenedCaptures = DefaultVoiceCaptureRepository(directoryURL: folder), reopenedTodos = DefaultVoiceTodoRepository(directoryURL: folder)
        let reopened = DefaultVoiceCaptureAndTodoUseCase(captures: reopenedCaptures, todos: reopenedTodos, runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: folder))
        let recovery = WatchTodoIngestAdapter(useCase: reopened)
        let resumed = WatchCaptureIngestCoordinator(inboxDirectory: folder, persistence: FileWatchIngestPersistence(directory: folder.appendingPathComponent("state")),
            transcriber: AppTestWatchTranscriber(), ingestTodo: { try await recovery.ingest(captureID: $0, transcript: $1, metadata: $2) }, sendReceipt: { _ in })
        await resumed.resume { _ in url }
        let savedCaptures = try await reopenedCaptures.fetchAll(), savedTodos = try await reopenedTodos.fetchAll()
        XCTAssertEqual(savedCaptures.count, 1); XCTAssertEqual(savedTodos.count, 1)
        XCTAssertEqual(savedCaptures.first?.linkedTodoID, savedTodos.first?.id)
        let diskCompletion = try await FileWatchIngestPersistence(directory: folder.appendingPathComponent("state")).completion(for: id)
        guard let diskCompletion else { XCTFail("Recovered Todo must have a durable receipt"); return }
        XCTAssertEqual(diskCompletion.captureID, id)
        if case .todoAdded(_, let title, let todoID) = diskCompletion.status {
            XCTAssertEqual(todoID, savedTodos.first?.id); XCTAssertEqual(title, savedTodos.first?.title)
        } else { XCTFail("Receipt must describe the actual persisted Todo") }
    }
    func testContradictoryTodoOriginLinkIsRejectedWithoutCreatingRows() async throws {
        let captures = DefaultVoiceCaptureRepository(), todos = DefaultVoiceTodoRepository()
        let id = UUID(), metadata = try WatchCaptureMetadata(captureID: id, duration: 1, basename: "\(id.uuidString).m4a")
        let other = VoiceCapture(mode: .todo, rawTranscript: "other", localAudioFileName: "other.m4a", durationSeconds: 1, deviceSource: .mac)
        try await captures.save(other)
        try await todos.save(VoiceTodo(title: "other", sourceCaptureID: other.id, localAudioFileName: metadata.basename, durationSeconds: 1, deviceSource: .appleWatch))
        let useCase = DefaultVoiceCaptureAndTodoUseCase(captures: captures, todos: todos, runner: DefaultAIRunnerExecutionService())
        let adapter = WatchTodoIngestAdapter(useCase: useCase)
        do { _ = try await adapter.ingest(captureID: id, transcript: WatchTranscribedCapture(rawTranscript: "整理纪要"), metadata: metadata); XCTFail("Contradictory source must not return another capture's Todo") } catch {}
        let savedCaptures = try await captures.fetchAll(), savedTodos = try await todos.fetchAll()
        XCTAssertEqual(savedCaptures.count, 1); XCTAssertEqual(savedTodos.count, 1)
    }
    func testSpeechOnceGateHandlesFinalErrorAndCancelBeforeInstall() async throws {
        let once = WatchRecognitionOnce<String>()
        let value: String = try await withCheckedThrowingContinuation { continuation in
            once.install(continuation); once.finish(.success("已识别")); once.finish(.failure(WatchCaptureError.captureFailed))
        }
        XCTAssertEqual(value, "已识别")
        let cancelled = WatchRecognitionOnce<String>()
        cancelled.finish(.failure(CancellationError()))
        do {
            let _: String = try await withCheckedThrowingContinuation { cancelled.install($0) }
            XCTFail("Early cancellation must resume once")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}

private struct WatchInjectedSaveFailure: Error {}
private struct AppTestWatchTranscriber: WatchAudioTranscribing {
    func transcribe(fileURL: URL) async throws -> WatchTranscribedCapture { WatchTranscribedCapture(rawTranscript: "整理纪要") }
}
private actor FaultWatchCompletion: WatchIngestPersistence {
    let base: FileWatchIngestPersistence
    var fails = true
    init(base: FileWatchIngestPersistence) { self.base = base }
    func pending() async throws -> [WatchCaptureMetadata] { try await base.pending() }
    func savePending(_ metadata: WatchCaptureMetadata) async throws { try await base.savePending(metadata) }
    func removePending(captureID: UUID) async throws { try await base.removePending(captureID: captureID) }
    func completion(for captureID: UUID) async throws -> WatchCaptureReceipt? { try await base.completion(for: captureID) }
    func saveCompletion(_ receipt: WatchCaptureReceipt) async throws {
        if fails { fails = false; throw WatchInjectedSaveFailure() }
        try await base.saveCompletion(receipt)
    }
}
private final class FaultWatchCaptures: VoiceCaptureRepository, Sendable {
    let base: DefaultVoiceCaptureRepository
    private let remaining: Mutex<Int>
    init(base: DefaultVoiceCaptureRepository, failureOnSave: Int) { self.base = base; remaining = Mutex(failureOnSave) }
    func fetchAll() async throws -> [VoiceCapture] { try await base.fetchAll() }
    func fetch(by id: UUID) async throws -> VoiceCapture? { try await base.fetch(by: id) }
    func save(_ capture: VoiceCapture) async throws {
        try await base.save(capture)
        let fail = remaining.withLock { value in guard value > 0 else { return false }; value -= 1; return value == 0 }
        if fail { throw WatchInjectedSaveFailure() }
    }
    func delete(by id: UUID) async throws { try await base.delete(by: id) }
    func observe() -> AnyPublisher<[VoiceCapture], Never> { base.observe() }
}
private final class FaultWatchTodos: VoiceTodoRepository, Sendable {
    let base: DefaultVoiceTodoRepository
    private let remaining: Mutex<Int>
    init(base: DefaultVoiceTodoRepository, failureOnSave: Int) { self.base = base; remaining = Mutex(failureOnSave) }
    func fetchAll() async throws -> [VoiceTodo] { try await base.fetchAll() }
    func fetch(by id: UUID) async throws -> VoiceTodo? { try await base.fetch(by: id) }
    func save(_ todo: VoiceTodo) async throws {
        try await base.save(todo)
        let fail = remaining.withLock { value in guard value > 0 else { return false }; value -= 1; return value == 0 }
        if fail { throw WatchInjectedSaveFailure() }
    }
    func delete(by id: UUID) async throws { try await base.delete(by: id) }
    func observe() -> AnyPublisher<[VoiceTodo], Never> { base.observe() }
}
