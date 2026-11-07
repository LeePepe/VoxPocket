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
}
