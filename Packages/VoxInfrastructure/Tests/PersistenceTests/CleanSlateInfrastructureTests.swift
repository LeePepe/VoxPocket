import XCTest
import CoreModels
@testable import Persistence
@testable import PlatformAdapters

final class CleanSlateInfrastructureTests: XCTestCase {
    func testRepositoriesSanitizeCloudPayloads() async throws {
        let cloud = InMemoryCloudSyncTransport()
        let repo = DefaultVoiceCaptureRepository(cloudSync: cloud)
        try await repo.save(VoiceCapture(rawTranscript: "raw", refinedText: "refined", localAudioFileName: "audio"))
        guard let captureData = try await cloud.captureMetadata() else { return XCTFail("missing capture payload") }
        let captures = try JSONDecoder().decode([VoiceCapture].self, from: captureData)
        XCTAssertEqual(captures.first?.rawTranscript, "")
        XCTAssertEqual(captures.first?.refinedText, "")
        XCTAssertNil(captures.first?.localAudioFileName)

        let todoRepo = DefaultVoiceTodoRepository(cloudSync: cloud)
        try await todoRepo.save(VoiceTodo(title: "title", taskPrompt: "prompt", rawTranscript: "raw", lastExecutionSummary: "summary", localAudioFileName: "audio"))
        guard let todoData = try await cloud.todoMetadata() else { return XCTFail("missing todo payload") }
        let todos = try JSONDecoder().decode([VoiceTodo].self, from: todoData)
        XCTAssertEqual(todos.first?.title, "")
        XCTAssertEqual(todos.first?.taskPrompt, "")
        XCTAssertEqual(todos.first?.rawTranscript, "")
        XCTAssertNil(todos.first?.lastExecutionSummary)
        XCTAssertNil(todos.first?.localAudioFileName)
    }

    func testAIRunnerUsesSandboxTaskFileAndDiscreteArguments() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectDirectory = directory.appendingPathComponent("project")
        let sandboxDirectory = directory.appendingPathComponent("sandbox")
        let service = DefaultAIRunnerExecutionService(processRunner: { executable, arguments, cwd in
            XCTAssertFalse(arguments.contains("title"))
            XCTAssertFalse(arguments.contains("$(unsafe)"))
            return (0, "ok")
        }, sandboxTasksDirectory: sandboxDirectory)
        let project = ProjectBinding(projectKey: "P", displayName: "P", localDirectoryPath: projectDirectory.path)
        let result = try await service.execute(todo: VoiceTodo(title: "title", taskPrompt: "$(unsafe)"), project: project, template: .herdrDefault)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.taskFilePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectDirectory.appendingPathComponent(".voxpocket/tasks").path))
        let fileContents = try String(contentsOfFile: result.taskFilePath, encoding: .utf8)
        XCTAssertFalse(fileContents.contains("title"))
        XCTAssertFalse(fileContents.contains("$(unsafe)"))
        XCTAssertTrue(fileContents.contains("\"project_key\":\"P\""))

        let unconfiguredService = DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDirectory)
        let disabledResult = try await unconfiguredService.execute(todo: VoiceTodo(title: "title", taskPrompt: "$(unsafe)"), project: project, template: .herdrDefault)
        XCTAssertEqual(disabledResult.exitCode, -1)
        XCTAssertTrue(disabledResult.outputSummary.contains("disabled by the sandbox privacy boundary"))
    }

    func testLinearTodoSyncServiceParsingAndBidirectionalStateMapping() async throws {
        let noop = NoopTodoExternalSyncService()
        XCTAssertFalse(noop.isEnabled)
        XCTAssertFalse(noop.isAutoSyncEnabled)
        let emptySnapshots = try await noop.fetchRemoteSnapshots()
        XCTAssertTrue(emptySnapshots.isEmpty)

        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "Triage", stateType: "triage", labels: []), .inbox)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "Backlog", stateType: "backlog", labels: []), .inbox)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "Todo", stateType: "unstarted", labels: []), .inbox)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "In Progress", stateType: "started", labels: []), .running)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "In Review", stateType: "started", labels: []), .running)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "In Progress", stateType: "started", labels: ["Blocked"]), .failed)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "Todo", stateType: "unstarted", labels: ["Needs Decision"]), .failed)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "Todo", stateType: "unstarted", labels: ["NEED_GO"]), .failed)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "Done", stateType: "completed", labels: ["Blocked"]), .done)
        XCTAssertEqual(LinearTodoSyncService.mapLinearStateToLocal(state: "Canceled", stateType: "canceled", labels: []), .done)

        XCTAssertEqual(LinearTodoSyncService.mapLocalStateToLinearState(.inbox), "Todo")
        XCTAssertEqual(LinearTodoSyncService.mapLocalStateToLinearState(.running), "In Progress")
        XCTAssertEqual(LinearTodoSyncService.mapLocalStateToLinearState(.done), "Done")
        XCTAssertEqual(LinearTodoSyncService.mapLocalStateToLinearState(.failed), "Todo")

        let service = LinearTodoSyncService(
            isEnabled: true,
            isAutoSyncEnabled: true,
            teamKey: "EXAMPLE",
            pushTransport: { todo, teamKey in
                XCTAssertEqual(teamKey, "EXAMPLE")
                XCTAssertEqual(todo.rawTranscript, "")
                XCTAssertNil(todo.localAudioFileName)
                return """
                {
                  "ok": true,
                  "command": "idea",
                  "issue": {
                    "id": "00000000-0000-0000-0000-000000000090",
                    "identifier": "EXAMPLE-90",
                    "title": "\(todo.title)",
                    "state": "Triage",
                    "stateType": "triage",
                    "project": "Personal project",
                    "priority": 0,
                    "url": "https://linear.app/example/issue/EXAMPLE-90",
                    "createdAt": "2026-11-09T13:30:00Z",
                    "updatedAt": "2026-11-09T13:30:00Z",
                    "labels": []
                  }
                }
                """.data(using: .utf8)!
            },
            pullTransport: { teamKey in
                XCTAssertEqual(teamKey, "EXAMPLE")
                return """
                {
                  "ok": true,
                  "command": "list-issues",
                  "issues": [
                    {
                      "id": "00000000-0000-0000-0000-000000000090",
                      "identifier": "EXAMPLE-90",
                      "title": "Older duplicate snapshot",
                      "state": "Todo",
                      "stateType": "unstarted",
                      "project": "Personal project",
                      "priority": 2,
                      "url": "https://linear.app/example/issue/EXAMPLE-90",
                      "createdAt": "2026-11-09T13:30:00Z",
                      "updatedAt": "2026-11-09T13:45:00Z",
                      "labels": []
                    },
                    {
                      "id": "00000000-0000-0000-0000-000000000090",
                      "identifier": "EXAMPLE-90",
                      "title": "Remote updated title",
                      "state": "In Progress",
                      "stateType": "started",
                      "project": "Personal project",
                      "priority": 2,
                      "url": "https://linear.app/example/issue/EXAMPLE-90",
                      "createdAt": "2026-11-09T13:30:00Z",
                      "updatedAt": "2026-11-09T14:00:00Z",
                      "labels": []
                    },
                    {
                      "id": "00000000-0000-0000-0000-000000000091",
                      "identifier": "EXAMPLE-91",
                      "title": "Blocked remote item",
                      "state": "In Progress",
                      "stateType": "started",
                      "project": "Personal project",
                      "priority": 1,
                      "url": "https://linear.app/example/issue/EXAMPLE-91",
                      "createdAt": "2026-11-09T13:30:00Z",
                      "updatedAt": "2026-11-09T14:05:00Z",
                      "labels": ["NEED_GO"]
                    }
                  ]
                }
                """.data(using: .utf8)!
            }
        )

        let pushedMeta = try await service.pushTodo(VoiceTodo(title: "Sync me", rawTranscript: "sensitive raw transcript", localAudioFileName: "clip.m4a"))
        XCTAssertEqual(pushedMeta.provider, "linear")
        XCTAssertEqual(pushedMeta.externalID, "EXAMPLE-90")
        XCTAssertEqual(pushedMeta.externalURL, "https://linear.app/example/issue/EXAMPLE-90")
        XCTAssertEqual(pushedMeta.teamKey, "EXAMPLE")
        XCTAssertEqual(pushedMeta.projectName, "Personal project")
        XCTAssertEqual(pushedMeta.syncState, .synced)
        XCTAssertEqual(pushedMeta.remoteUpdatedAt, "2026-11-09T13:30:00Z")
        XCTAssertNil(pushedMeta.lastError)

        let snapshots = try await service.fetchRemoteSnapshots()
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].externalID, "EXAMPLE-90")
        XCTAssertEqual(snapshots[0].title, "Remote updated title")
        XCTAssertEqual(snapshots[0].executionState, .running)
        XCTAssertEqual(snapshots[1].externalID, "EXAMPLE-91")
        XCTAssertEqual(snapshots[1].executionState, .failed)

        // File-backed concurrency regression test: concurrent update and delete serialize mutation + disk persistence so a deleted todo is never resurrected on reload
        let persistenceDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileRepo = DefaultVoiceTodoRepository(directoryURL: persistenceDir)
        let targetTodo = VoiceTodo(title: "File-backed target")
        let survivorTodo = VoiceTodo(title: "Survivor")
        try await fileRepo.save(targetTodo)
        try await fileRepo.save(survivorTodo)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<25 {
                group.addTask {
                    _ = try? await fileRepo.update(id: targetTodo.id) { current in
                        current.withEdits(title: "Concurrent edit \(i)")
                    }
                    _ = try? await fileRepo.update(id: survivorTodo.id) { current in
                        current.withEdits(title: "Survivor edit \(i)")
                    }
                }
            }
            group.addTask {
                try? await fileRepo.delete(by: targetTodo.id)
            }
        }
        try await fileRepo.delete(by: targetTodo.id)
        let reloadedRepo = DefaultVoiceTodoRepository(directoryURL: persistenceDir)
        let reloadedTarget = try await reloadedRepo.fetch(by: targetTodo.id)
        let reloadedSurvivor = try await reloadedRepo.fetch(by: survivorTodo.id)
        XCTAssertNil(reloadedTarget)
        XCTAssertNotNil(reloadedSurvivor)
    }

    #if os(macOS)
    @MainActor
    func testMacOSGlobalHotkeyServiceRegistersAndUnregistersCarbonLongPressHotkeys() async throws {
        let service = MacOSGlobalHotkeyService.shared
        let direct = HotkeyDefinition(keyCode: 49, modifiers: 2048, identifier: HotkeyIdentifier.directToText)
        let todo = HotkeyDefinition(keyCode: 49, modifiers: 2560, identifier: HotkeyIdentifier.voiceToTodo)
        var events: [String] = []
        service.registerLongPress(direct, onPress: {
            await MainActor.run { events.append("press") }
        }, onRelease: {
            await MainActor.run { events.append("release") }
        })
        service.registerLongPress(todo, onPress: {}, onRelease: {})
        XCTAssertEqual(service.getRegistered(HotkeyIdentifier.directToText), direct)
        XCTAssertEqual(service.getRegistered(HotkeyIdentifier.voiceToTodo), todo)

        let id = try XCTUnwrap(service.registeredHotkeyID(for: HotkeyIdentifier.directToText))
        XCTAssertEqual(service.carbonLongPressDuration, 0)

        // Default zero-delay path triggers onPress immediately and orders onRelease after onPress
        let immediatePressExp = expectation(description: "immediatePress")
        let immediateReleaseExp = expectation(description: "immediateRelease")
        service.registerLongPress(direct, onPress: {
            await MainActor.run {
                events.append("immediate-press")
                immediatePressExp.fulfill()
            }
        }, onRelease: {
            await MainActor.run {
                events.append("immediate-release")
                immediateReleaseExp.fulfill()
            }
        })
        let immediateId = try XCTUnwrap(service.registeredHotkeyID(for: HotkeyIdentifier.directToText))
        service.handleHotkeyTriggered(id: immediateId)
        service.handleHotkeyReleased(id: immediateId)
        await fulfillment(of: [immediatePressExp, immediateReleaseExp], timeout: 2.0)
        XCTAssertEqual(events, ["immediate-press", "immediate-release"])
        events.removeAll()

        service.carbonLongPressDuration = 0.04
        defer { service.carbonLongPressDuration = 0 }

        // Quick tap-release shorter than carbonLongPressDuration must not trigger onPress
        service.handleHotkeyTriggered(id: id)
        service.handleHotkeyReleased(id: id)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(events, [])

        // Holding past carbonLongPressDuration triggers onPress once and onRelease on release
        let pressExp = expectation(description: "press")
        let releaseExp = expectation(description: "release")
        service.registerLongPress(direct, onPress: {
            await MainActor.run {
                events.append("press")
                pressExp.fulfill()
            }
        }, onRelease: {
            await MainActor.run {
                events.append("release")
                releaseExp.fulfill()
            }
        })
        let refreshedId = try XCTUnwrap(service.registeredHotkeyID(for: HotkeyIdentifier.directToText))
        service.handleHotkeyTriggered(id: refreshedId)
        service.handleHotkeyTriggered(id: refreshedId)
        await fulfillment(of: [pressExp], timeout: 2.0)
        XCTAssertEqual(events, ["press"])

        service.handleHotkeyReleased(id: refreshedId)
        service.handleHotkeyReleased(id: refreshedId)
        await fulfillment(of: [releaseExp], timeout: 2.0)
        XCTAssertEqual(events, ["press", "release"])

        service.unregister(HotkeyIdentifier.directToText)
        service.unregister(HotkeyIdentifier.voiceToTodo)
        XCTAssertNil(service.getRegistered(HotkeyIdentifier.directToText))
        XCTAssertNil(service.getRegistered(HotkeyIdentifier.voiceToTodo))

        let clipboard = MacOSClipboardService.shared
        clipboard.copy("synthetic-clipboard-test")
        XCTAssertEqual(clipboard.paste(), "synthetic-clipboard-test")
        try await clipboard.simulatePaste()
    }
    #endif
}
