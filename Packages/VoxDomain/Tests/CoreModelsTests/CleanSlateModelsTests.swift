import XCTest
@testable import CoreModels

final class CleanSlateModelsTests: XCTestCase {
    func testCloudSanitizationStripsSensitiveFields() {
        let capture = VoiceCapture(rawTranscript: "raw", refinedText: "refined", localAudioFileName: "audio.m4a")
        let sanitizedCapture = capture.sanitizedForCloudSync()
        XCTAssertEqual(sanitizedCapture.rawTranscript, "")
        XCTAssertEqual(sanitizedCapture.refinedText, "")
        XCTAssertNil(sanitizedCapture.localAudioFileName)

        let todo = VoiceTodo(title: "title", taskPrompt: "prompt", rawTranscript: "raw", lastExecutionSummary: "summary", localAudioFileName: "audio.m4a")
        let sanitizedTodo = todo.sanitizedForCloudSync()
        XCTAssertEqual(sanitizedTodo.title, "")
        XCTAssertEqual(sanitizedTodo.taskPrompt, "")
        XCTAssertEqual(sanitizedTodo.rawTranscript, "")
        XCTAssertNil(sanitizedTodo.lastExecutionSummary)
        XCTAssertNil(sanitizedTodo.localAudioFileName)
    }

    func testRunnerEscapingAndArguments() {
        let value = "$(whoami); rm -rf /"
        let template = AIRunnerTemplate.herdrDefault
        XCTAssertTrue(template.interpolate(cwd: "/tmp", title: value, prompt: value, taskFile: "/tmp/task.md").contains("'$(whoami); rm -rf /'"))
        let execArgs = template.executableAndArguments(cwd: "/tmp", taskFile: "/tmp/task.md")
        XCTAssertEqual(execArgs.arguments.last, "/tmp/task.md")
        XCTAssertFalse(execArgs.arguments.contains(value))
        XCTAssertEqual(ProjectBinding.matchProjectKey(in: "Please update VoxPocket voice", bindings: [ProjectBinding(projectKey: "VP", displayName: "VoxPocket", localDirectoryPath: "/tmp")]), "VP")
    }

    func testExternalTodoSyncMetadataBackwardCompatibleDecodingAndSanitization() throws {
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Legacy todo",
          "taskPrompt": "Legacy prompt",
          "rawTranscript": "Legacy raw",
          "executionState": "inbox",
          "durationSeconds": 4.5,
          "deviceSource": "mac",
          "createdAt": 1000,
          "updatedAt": 1000
        }
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(VoiceTodo.self, from: legacyJSON)
        XCTAssertNil(decodedLegacy.externalSync)
        XCTAssertEqual(decodedLegacy.title, "Legacy todo")

        let syncMeta = ExternalTodoSyncMetadata(
            provider: "linear",
            externalID: "TIA-90",
            externalURL: "https://linear.app/example/issue/TIA-90",
            teamKey: "TIA",
            projectName: "Personal project",
            syncState: .synced,
            remoteUpdatedAt: "2026-11-09T13:30:00Z",
            lastError: "transient network error"
        )
        let linked = decodedLegacy.withExternalSync(syncMeta)
        XCTAssertEqual(linked.externalSync, syncMeta)
        XCTAssertEqual(linked.withEdits(title: "Renamed").externalSync, syncMeta)
        XCTAssertEqual(linked.withExecutionState(.done).externalSync, syncMeta)

        let sanitized = linked.sanitizedForCloudSync()
        XCTAssertEqual(sanitized.title, "")
        XCTAssertEqual(sanitized.externalSync?.provider, "linear")
        XCTAssertEqual(sanitized.externalSync?.externalID, "TIA-90")
        XCTAssertEqual(sanitized.externalSync?.teamKey, "TIA")
        XCTAssertEqual(sanitized.externalSync?.syncState, .synced)
        XCTAssertEqual(sanitized.externalSync?.remoteUpdatedAt, "2026-11-09T13:30:00Z")
        XCTAssertNil(sanitized.externalSync?.externalURL)
        XCTAssertNil(sanitized.externalSync?.projectName)
        XCTAssertNil(sanitized.externalSync?.lastError)
    }
}
