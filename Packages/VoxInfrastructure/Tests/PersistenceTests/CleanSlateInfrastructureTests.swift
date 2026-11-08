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
        service.carbonLongPressDuration = 0.04
        defer { service.carbonLongPressDuration = 0.12 }

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
