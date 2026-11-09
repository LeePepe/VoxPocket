import XCTest
import CoreModels
import Persistence
import PlatformAdapters
@testable import UseCases

final class VoiceTodoUseCaseTests: XCTestCase {
    func testCaptureToTodoConversionAndAIRunnerExecutionLifecycle() async throws {
        let captures = DefaultVoiceCaptureRepository()
        let todos = DefaultVoiceTodoRepository()
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runner = DefaultAIRunnerExecutionService(processRunner: { executable, arguments, cwd in
            XCTAssertEqual(executable, "herdr")
            return (0, "completed task")
        }, sandboxTasksDirectory: sandboxDir)
        let project = ProjectBinding(projectKey: "VP", displayName: "VoxPocket", matchKeywords: ["voxpocket"], localDirectoryPath: "/tmp")
        let useCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: runner,
            projects: { [project] }
        )

        let textResult = try await useCase.recordCompletedCapture(
            mode: .text,
            rawTranscript: "Update VoxPocket hotkey handling",
            refinedText: "Update VoxPocket hotkey handling.",
            localAudioFileName: "clip.m4a",
            durationSeconds: 3,
            deviceSource: .mac
        )
        XCTAssertNil(textResult.todo)

        let converted = try await useCase.convertCaptureToTodo(captureID: textResult.capture.id)
        XCTAssertEqual(converted.projectKey, "VP")
        XCTAssertEqual(converted.executionState, .inbox)

        let executed = try await useCase.runTodoWithAI(todoID: converted.id, project: project, template: .herdrDefault)
        XCTAssertEqual(executed.executionState, .done)
        XCTAssertEqual(executed.lastExecutionSummary, "completed task")

        let defaultUseCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir),
            projects: { [project] }
        )
        let blocked = try await defaultUseCase.runTodoWithAI(todoID: converted.id, project: project, template: .herdrDefault)
        XCTAssertEqual(blocked.executionState, .failed)
        XCTAssertTrue(blocked.lastExecutionSummary?.contains("disabled by the sandbox privacy boundary") == true)
    }

    func testPluggableExternalTodoSyncOfflineDegradationAndConflictReconciliation() async throws {
        let captures = DefaultVoiceCaptureRepository()
        let todos = DefaultVoiceTodoRepository()
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runner = DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir)

        actor SyncRecorder {
            var shouldFailPush = false
            var pushedStates: [(String, TodoExecutionState)] = []
            var remoteSnapshotsPayload: Data = """
            {"ok": true, "command": "list-issues", "issues": []}
            """.data(using: .utf8)!

            func setShouldFailPush(_ value: Bool) { shouldFailPush = value }
            func setRemotePayload(_ json: String) { remoteSnapshotsPayload = json.data(using: .utf8)! }
            func recordPush(title: String, state: TodoExecutionState) -> Bool {
                pushedStates.append((title, state))
                return shouldFailPush
            }
            func getPushedStates() -> [(String, TodoExecutionState)] { pushedStates }
            func getRemotePayload() -> Data { remoteSnapshotsPayload }
        }

        let recorder = SyncRecorder()
        let syncService = LinearTodoSyncService(
            isEnabled: true,
            isAutoSyncEnabled: false,
            teamKey: "TIA",
            pushTransport: { todo, teamKey in
                if await recorder.recordPush(title: todo.title, state: todo.executionState) {
                    throw TodoExternalSyncError.remoteCommandFailed("offline")
                }
                let identifier = todo.externalSync?.externalID ?? "\(teamKey)-101"
                let stateName = LinearTodoSyncService.mapLocalStateToLinearState(todo.executionState)
                return """
                {
                  "ok": true,
                  "command": "idea",
                  "issue": {
                    "id": "00000000-0000-0000-0000-000000000101",
                    "identifier": "\(identifier)",
                    "title": "\(todo.title)",
                    "state": "\(stateName)",
                    "stateType": "\(todo.executionState == .done ? "completed" : "unstarted")",
                    "project": "Personal project",
                    "priority": 0,
                    "url": "https://linear.app/example/issue/\(identifier)",
                    "createdAt": "2026-11-09T13:00:00Z",
                    "updatedAt": "2026-11-09T13:30:00Z",
                    "labels": []
                  }
                }
                """.data(using: .utf8)!
            },
            pullTransport: { _ in
                await recorder.getRemotePayload()
            }
        )

        let useCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: runner,
            externalSync: syncService
        )

        let created = try await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "Draft architecture note",
            refinedText: "Draft architecture note.",
            localAudioFileName: nil,
            durationSeconds: 2,
            deviceSource: .mac
        )
        let localTodo = try XCTUnwrap(created.todo)
        XCTAssertNil(localTodo.externalSync)

        // Manual promote to Linear
        let promoted = try await useCase.syncTodoToExternal(todoID: localTodo.id)
        XCTAssertEqual(promoted.externalSync?.provider, "linear")
        XCTAssertEqual(promoted.externalSync?.externalID, "TIA-101")
        XCTAssertEqual(promoted.externalSync?.syncState, .synced)
        XCTAssertEqual(promoted.externalSync?.remoteUpdatedAt, "2026-11-09T13:30:00Z")

        // Simulate offline failure when marking done: local state must become .done and syncState .pendingPush
        await recorder.setShouldFailPush(true)
        let offlineDone = try await useCase.markTodoDone(todoID: promoted.id)
        XCTAssertEqual(offlineDone.executionState, .done)
        XCTAssertEqual(offlineDone.externalSync?.syncState, .pendingPush)
        XCTAssertNotNil(offlineDone.externalSync?.lastError)

        // Come back online with a remote snapshot: refreshExternalTodos pushes .pendingPush first before pulling
        await recorder.setShouldFailPush(false)
        await recorder.setRemotePayload("""
        {
          "ok": true,
          "command": "list-issues",
          "issues": [
            {
              "id": "00000000-0000-0000-0000-000000000101",
              "identifier": "TIA-101",
              "title": "Remote finalized title",
              "state": "In Progress",
              "stateType": "started",
              "project": "Personal project",
              "priority": 2,
              "url": "https://linear.app/example/issue/TIA-101",
              "createdAt": "2026-11-09T13:00:00Z",
              "updatedAt": "2026-11-09T14:00:00Z",
              "labels": []
            }
          ]
        }
        """)
        let reconciled = try await useCase.refreshExternalTodos()
        let updatedItem = try XCTUnwrap(reconciled.first(where: { $0.id == promoted.id }))
        XCTAssertEqual(updatedItem.title, "Remote finalized title")
        XCTAssertEqual(updatedItem.executionState, .running)
        XCTAssertEqual(updatedItem.externalSync?.syncState, .synced)
        XCTAssertEqual(updatedItem.externalSync?.remoteUpdatedAt, "2026-11-09T14:00:00Z")

        let pushes = await recorder.getPushedStates()
        XCTAssertGreaterThanOrEqual(pushes.count, 3)
    }
}
