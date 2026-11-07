import XCTest
import CoreModels
import UseCases
@testable import UIShared

final class VoxWorkspaceContractTests: XCTestCase {
    func testTodoExtractorBuildsBoundedTitleAndProjectMatch() async throws {
        let binding = ProjectBinding(projectKey: "VP", displayName: "VoxPocket", matchKeywords: ["voice"], localDirectoryPath: "/tmp")
        let draft = try await DefaultVoiceTodoExtractor().extractTodo(
            from: "Please improve the voice capture experience with a very long context that should be shortened for the title.",
            refinedText: "",
            availableProjects: [binding]
        )
        XCTAssertLessThanOrEqual(draft.title.count, 60)
        XCTAssertEqual(draft.matchedProjectKey, "VP")
        XCTAssertTrue(draft.taskPrompt.contains("Goal"))
    }

    @MainActor
    func testDeepLinksPreserveLegacyAndSupportCaptureModes() {
        let router = DefaultDeepLinkRouter()
        XCTAssertEqual(router.resolve(URL(string: "voxpocket://quickRecord")!), .startRecording)
        XCTAssertEqual(router.resolve(URL(string: "voxpocket://quickRecord?mode=todo")!), .startRecordingInMode(.todo))
        XCTAssertEqual(router.resolve(URL(string: "voxpocket://stopRecording")!), .stopRecording)
    }
}
