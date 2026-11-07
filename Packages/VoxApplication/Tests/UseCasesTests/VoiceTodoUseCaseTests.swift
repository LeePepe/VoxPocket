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
    }
}
