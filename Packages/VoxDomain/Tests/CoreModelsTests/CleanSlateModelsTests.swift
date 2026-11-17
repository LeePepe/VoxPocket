import XCTest
@testable import CoreModels

final class CleanSlateModelsTests: XCTestCase {
    func testCloudSanitizationStripsSensitiveFields() {
        let capture = VoiceCapture(rawTranscript: "raw", refinedText: "refined", localAudioFileName: "audio.m4a")
        let sanitizedCapture = capture.sanitizedForCloudSync()
        XCTAssertEqual(sanitizedCapture.rawTranscript, "")
        XCTAssertEqual(sanitizedCapture.refinedText, "")
        XCTAssertNil(sanitizedCapture.localAudioFileName)

        let todo = VoiceTodo(
            title: "title",
            description: "Sensitive spoken context and background details",
            taskPrompt: "prompt",
            rawTranscript: "raw",
            priority: .p0,
            tags: ["VoxPocket", "AI", "Design", "ExtraIgnored"],
            subtasks: [VoiceTodoSubtask(title: "Secret subtask from voice")],
            lastExecutionSummary: "summary",
            localAudioFileName: "audio.m4a"
        )
        XCTAssertEqual(todo.description, "Sensitive spoken context and background details")
        XCTAssertEqual(todo.tags, ["#VoxPocket", "#AI", "#Design"])
        let sanitizedTodo = todo.sanitizedForCloudSync()
        XCTAssertEqual(sanitizedTodo.title, "")
        XCTAssertEqual(sanitizedTodo.description, "")
        XCTAssertEqual(sanitizedTodo.taskPrompt, "")
        XCTAssertEqual(sanitizedTodo.rawTranscript, "")
        XCTAssertEqual(sanitizedTodo.tags, [])
        XCTAssertEqual(sanitizedTodo.subtasks.map(\.title), [""])
        XCTAssertNil(sanitizedTodo.lastExecutionSummary)
        XCTAssertNil(sanitizedTodo.localAudioFileName)
    }

    func testVoiceTodoSubtasksPriorityTagsAndCopyPreservation() throws {
        let base = VoiceTodo(
            title: "Prepare iOS slide nav",
            taskPrompt: "## Goal\nSlide nav",
            rawTranscript: "Prepare iOS slide nav",
            projectKey: "VP",
            priority: .p0,
            tags: ["VoxPocket", "#iOS", "Glass", "OverflowTag"]
        )
        XCTAssertEqual(base.priority, .p0)
        XCTAssertEqual(base.tags, ["#VoxPocket", "#iOS", "#Glass"])
        XCTAssertTrue(base.subtasks.isEmpty)

        let withSubtask = base.withAppendedSubtask("Add bottom-left switch button")
        XCTAssertEqual(withSubtask.subtasks.count, 1)
        XCTAssertEqual(withSubtask.subtasks[0].title, "Add bottom-left switch button")
        XCTAssertFalse(withSubtask.subtasks[0].isCompleted)
        XCTAssertTrue(withSubtask.taskPrompt.contains("- [ ] Add bottom-left switch button"))

        let subtaskID = withSubtask.subtasks[0].id
        let toggled = withSubtask.withToggledSubtask(subtaskID)
        XCTAssertTrue(toggled.subtasks[0].isCompleted)

        let stateUpdated = toggled.withExecutionState(.running)
        XCTAssertEqual(stateUpdated.priority, .p0)
        XCTAssertEqual(stateUpdated.tags, ["#VoxPocket", "#iOS", "#Glass"])
        XCTAssertEqual(stateUpdated.subtasks, toggled.subtasks)

        let reprioritized = stateUpdated.withPriority(.p2)
        XCTAssertEqual(reprioritized.priority, .p2)
        XCTAssertEqual(reprioritized.subtasks, toggled.subtasks)

        let encoded = try JSONEncoder().encode(reprioritized)
        let decoded = try JSONDecoder().decode(VoiceTodo.self, from: encoded)
        XCTAssertEqual(decoded, reprioritized)

        let retitled = reprioritized
            .withTitle("  Updated Top Focus Title  ")
            .withTitle("   ")
            .withUpdatedSubtaskTitle(subtaskID, title: "  Verify v02+v04 subtask inline edit  ")
            .withUpdatedSubtaskTitle(subtaskID, title: "   ")
            .withToggledTag("#iOS")
            .withToggledTag("Podcast")
        XCTAssertEqual(retitled.title, "Updated Top Focus Title")
        XCTAssertEqual(retitled.subtasks[0].title, "Verify v02+v04 subtask inline edit")
        XCTAssertEqual(retitled.tags, ["#VoxPocket", "#Glass", "#Podcast"])
        XCTAssertEqual(retitled.withAddedTag("FourthIgnored").tags, ["#VoxPocket", "#Glass", "#Podcast"])

        let retitledEncoded = try JSONEncoder().encode(retitled)
        let retitledDecoded = try JSONDecoder().decode(VoiceTodo.self, from: retitledEncoded)
        XCTAssertEqual(retitledDecoded, retitled)

        let reminderDate = Date(timeIntervalSince1970: 1_763_300_000)
        let scheduled = retitled
            .withDescription("  整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单  ")
            .withReminderSchedule(scheduledAt: reminderDate, timeSlot: "morning")
        XCTAssertEqual(scheduled.description, "整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单")
        XCTAssertEqual(scheduled.withExecutionState(.running).description, scheduled.description)
        XCTAssertEqual(scheduled.withPriority(.p0).description, scheduled.description)
        XCTAssertEqual(scheduled.withAppendedSubtask("Check description").description, scheduled.description)
        XCTAssertEqual(scheduled.scheduledAt, reminderDate)
        XCTAssertEqual(scheduled.timeSlot, "morning")
        let scheduledDecoded = try JSONDecoder().decode(VoiceTodo.self, from: JSONEncoder().encode(scheduled))
        XCTAssertEqual(scheduledDecoded.description, scheduled.description)
        XCTAssertEqual(scheduledDecoded.scheduledAt, reminderDate)
        XCTAssertEqual(scheduledDecoded.timeSlot, "morning")
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

    func testAppleWatchDeviceSourceRoundTripsAndLegacyValuesRemainStable() throws {
        let todo = VoiceTodo(title: "Watch capture", deviceSource: .appleWatch)
        let encoded = try JSONEncoder().encode(todo)
        let decoded = try JSONDecoder().decode(VoiceTodo.self, from: encoded)
        XCTAssertEqual(decoded.deviceSource, .appleWatch)
        XCTAssertTrue(String(data: encoded, encoding: .utf8)?.contains("appleWatch") == true)

        for (raw, expected) in [("iPhone", DeviceSource.iPhone), ("mac", .mac), ("iPad", .iPad)] {
            let decodedSource = try JSONDecoder().decode(DeviceSource.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(decodedSource, expected)
        }
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
            externalID: "EXAMPLE-90",
            externalURL: "https://linear.app/example/issue/EXAMPLE-90",
            teamKey: "EXAMPLE",
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
        XCTAssertEqual(sanitized.externalSync?.externalID, "EXAMPLE-90")
        XCTAssertEqual(sanitized.externalSync?.teamKey, "EXAMPLE")
        XCTAssertEqual(sanitized.externalSync?.syncState, .synced)
        XCTAssertEqual(sanitized.externalSync?.remoteUpdatedAt, "2026-11-09T13:30:00Z")
        XCTAssertNil(sanitized.externalSync?.externalURL)
        XCTAssertNil(sanitized.externalSync?.projectName)
        XCTAssertNil(sanitized.externalSync?.lastError)
    }
}
