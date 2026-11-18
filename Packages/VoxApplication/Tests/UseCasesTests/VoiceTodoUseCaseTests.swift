import XCTest
import CoreModels
import Persistence
import PlatformAdapters
import VoxNotificationKit
@testable import UseCases

final class VoiceTodoUseCaseTests: XCTestCase {
    func testOnDeviceAITodoDecompositionAndHabitAnchorNotificationLifecycle() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let fixedNow = cal.date(from: DateComponents(timeZone: cal.timeZone, year: 2026, month: 11, day: 16, hour: 21, minute: 30))!

        let tempHabitURL = FileManager.default.temporaryDirectory.appendingPathComponent("todo-habit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempHabitURL) }
        let learner = AdaptiveTimeAnchorLearner(
            store: FileHabitTimeAnchorStore(fileURL: tempHabitURL),
            calendar: cal
        )
        let center = InMemoryVoxNotificationCenter()
        let scheduler = VoxNotificationScheduler(timeAnchorLearner: learner, center: center, calendar: cal)

        let aiDecomposer = DefaultOnDeviceAITodoDecomposer { instructions, _ in
            XCTAssertTrue(instructions.contains("提醒我早上取顺丰快递"))
            return """
            {
              "cleanTitle": "取顺丰快递",
              "timeSlot": "morning",
              "dayOffset": 0,
              "explicitHour": null,
              "explicitMinute": null,
              "relativeMinutes": null,
              "priority": "P0",
              "tags": ["快递", "#顺丰"],
              "subtasks": ["带上取件码", "顺路寄退货"]
            }
            """
        }

        let extractor = DefaultVoiceTodoExtractor(
            aiDecomposer: aiDecomposer,
            timeAnchorLearner: learner,
            calendar: cal,
            nowProvider: { fixedNow }
        )

        let captures = DefaultVoiceCaptureRepository()
        let todos = DefaultVoiceTodoRepository()
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let useCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: extractor,
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir),
            notificationScheduler: scheduler
        )

        let outcome = try await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "提醒我早上取顺丰快递，带上取件码并顺路寄退货",
            refinedText: "提醒我早上取顺丰快递，带上取件码并顺路寄退货。",
            localAudioFileName: nil,
            durationSeconds: 4,
            deviceSource: .iPhone
        )
        let created = try XCTUnwrap(outcome.todo)
        XCTAssertEqual(created.title, "取顺丰快递")
        XCTAssertEqual(created.priority, .p0)
        XCTAssertEqual(created.tags, ["#快递", "#顺丰"])
        XCTAssertEqual(created.subtasks.map(\.title), ["带上取件码", "顺路寄退货"])
        XCTAssertEqual(created.timeSlot, "morning")
        // Since fixedNow is 21:30 on Nov 16, morning (09:00) rolls over to Nov 17 at 09:00
        let scheduledAt = try XCTUnwrap(created.scheduledAt)
        XCTAssertEqual(cal.component(.day, from: scheduledAt), 17)
        XCTAssertEqual(cal.component(.hour, from: scheduledAt), 9)
        XCTAssertEqual(cal.component(.minute, from: scheduledAt), 0)
        XCTAssertEqual(scheduler.pendingItems().count, 1)

        // Manual reschedule to 08:30 updates VoiceTodo, reschedules notification, and feeds AdaptiveTimeAnchorLearner
        let manual830 = cal.date(from: DateComponents(timeZone: cal.timeZone, year: 2026, month: 11, day: 17, hour: 8, minute: 30))!
        let rescheduled = try await useCase.rescheduleTodoReminder(todoID: created.id, newDate: manual830, timeSlot: "morning")
        XCTAssertEqual(rescheduled.scheduledAt, manual830)
        XCTAssertEqual(scheduler.pendingItems().first?.fireDate, manual830)
        let learnedNext = learner.resolveAnchor(for: .morning, dayOffset: 1, tags: ["#快递"], now: fixedNow)
        XCTAssertLessThan(learnedNext.minutesFromMidnight, 540)

        // Marking done cancels pending notification
        _ = try await useCase.markTodoDone(todoID: created.id)
        XCTAssertTrue(scheduler.pendingItems().isEmpty)

        // Verify extreme relativeMinutes (Int.max) does not overflow and notification quick actions persist back to repository
        let overflowDecomposer = DefaultOnDeviceAITodoDecomposer { _, _ in
            """
            {
              "cleanTitle": "防止整数乘法溢出测试",
              "timeSlot": "evening",
              "dayOffset": 999999,
              "explicitHour": null,
              "explicitMinute": null,
              "relativeMinutes": \(Int.max),
              "priority": "P1",
              "tags": ["#安全"],
              "subtasks": []
            }
            """
        }
        let overflowExtractor = DefaultVoiceTodoExtractor(
            aiDecomposer: overflowDecomposer,
            timeAnchorLearner: learner,
            calendar: cal,
            nowProvider: { fixedNow }
        )
        let overflowUseCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: overflowExtractor,
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir),
            notificationScheduler: scheduler
        )
        let overflowOutcome = try await overflowUseCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "测试大整数",
            refinedText: "测试大整数",
            localAudioFileName: nil,
            durationSeconds: 1,
            deviceSource: .iPhone
        )
        let overflowTodo = try XCTUnwrap(overflowOutcome.todo)
        XCTAssertNotNil(overflowTodo.scheduledAt)

        // Verify long spoken utterance is decomposed into a concise <=14 char title + rich description
        let longSpeechDecomposer = DefaultOnDeviceAITodoDecomposer { instructions, _ in
            XCTAssertTrue(instructions.contains("description"))
            return """
            {
              "cleanTitle": "整理下周设计评审要展示的液态玻璃交互走查清单",
              "description": "整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单",
              "timeSlot": "morning",
              "dayOffset": 1,
              "explicitHour": null,
              "explicitMinute": null,
              "relativeMinutes": null,
              "priority": "P0",
              "tags": ["#VoxPocket", "#iOS", "#Glass"],
              "subtasks": ["录制声波走查", "验证原地展开"]
            }
            """
        }
        let longSpeechExtractor = DefaultVoiceTodoExtractor(
            aiDecomposer: longSpeechDecomposer,
            timeAnchorLearner: learner,
            calendar: cal,
            nowProvider: { fixedNow }
        )
        let longSpeechUseCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: longSpeechExtractor,
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir),
            notificationScheduler: scheduler
        )
        let longSpeechOutcome = try await longSpeechUseCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "提醒我明天早上整理下周设计评审要展示的液态玻璃交互走查清单",
            refinedText: "提醒我明天早上整理下周设计评审要展示的液态玻璃交互走查清单",
            localAudioFileName: nil,
            durationSeconds: 5,
            deviceSource: .iPhone
        )
        let longSpeechTodo = try XCTUnwrap(longSpeechOutcome.todo)
        XCTAssertLessThanOrEqual(longSpeechTodo.title.count, 14)
        XCTAssertEqual(longSpeechTodo.title, "整理液态玻璃交互走查清单")
        XCTAssertEqual(longSpeechTodo.description, "整理下周设计评审要展示的 iOS 26 液态玻璃底栏与原地展开交互走查清单")

        // Also verify deterministic fallbackSentenceSplit compacts >14 char spoken sentences into <=14 char title + description
        let fallbackResult = DefaultOnDeviceAITodoDecomposer.fallbackSentenceSplit(
            from: "提醒我明天早上把早间散步录下的播客大纲润色后发给搭档确认"
        )
        XCTAssertLessThanOrEqual(fallbackResult.cleanTitle.count, 14)
        XCTAssertFalse(fallbackResult.description.isEmpty)
        XCTAssertTrue(fallbackResult.description.contains("播客大纲"))

        // Triggering markDone via notificationScheduler updates the persisted VoiceTodo in the repository via actionEvents stream
        _ = try await scheduler.handleAction(
            identifier: VoxNotificationQuickAction.markDone.rawValue,
            itemID: overflowTodo.id,
            slot: .evening,
            tags: ["#安全"],
            now: fixedNow
        )
        try await Task.sleep(for: .milliseconds(50))
        let persistedAfterNotificationDone = try await todos.fetch(by: overflowTodo.id)
        XCTAssertEqual(persistedAfterNotificationDone?.executionState, .done)
    }

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
            teamKey: "CUSTOM",
            pushTransport: { todo, teamKey in
                XCTAssertEqual(teamKey, "CUSTOM")
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

        // Manual promote to Linear uses the configured teamKey ("CUSTOM")
        let promoted = try await useCase.syncTodoToExternal(todoID: localTodo.id)
        XCTAssertEqual(promoted.externalSync?.provider, "linear")
        XCTAssertEqual(promoted.externalSync?.externalID, "CUSTOM-101")
        XCTAssertEqual(promoted.externalSync?.teamKey, "CUSTOM")
        XCTAssertEqual(promoted.externalSync?.syncState, .synced)
        XCTAssertEqual(promoted.externalSync?.remoteUpdatedAt, "2026-11-09T13:30:00Z")

        // Simulate offline failure when marking done: local state must become .done and syncState .pendingPush
        await recorder.setShouldFailPush(true)
        let offlineDone = try await useCase.markTodoDone(todoID: promoted.id)
        XCTAssertEqual(offlineDone.executionState, .done)
        XCTAssertEqual(offlineDone.externalSync?.syncState, .pendingPush)
        XCTAssertNotNil(offlineDone.externalSync?.lastError)

        // Come back online with duplicate remote snapshots: refreshExternalTodos deduplicates and pushes .pendingPush first
        await recorder.setShouldFailPush(false)
        await recorder.setRemotePayload("""
        {
          "ok": true,
          "command": "list-issues",
          "issues": [
            {
              "id": "00000000-0000-0000-0000-000000000101",
              "identifier": "CUSTOM-101",
              "title": "Stale duplicate title",
              "state": "Todo",
              "stateType": "unstarted",
              "project": "Personal project",
              "priority": 2,
              "url": "https://linear.app/example/issue/CUSTOM-101",
              "createdAt": "2026-11-09T13:00:00Z",
              "updatedAt": "2026-11-09T13:40:00Z",
              "labels": []
            },
            {
              "id": "00000000-0000-0000-0000-000000000101",
              "identifier": "CUSTOM-101",
              "title": "Remote finalized title",
              "state": "In Progress",
              "stateType": "started",
              "project": "Personal project",
              "priority": 2,
              "url": "https://linear.app/example/issue/CUSTOM-101",
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

        // Verify that a concurrent local edit or deletion during an in-flight push is preserved and not overwritten/recreated
        let concurrentTodo = VoiceTodo(title: "Initial title")
        try await todos.save(concurrentTodo)

        let slowSyncService = LinearTodoSyncService(
            isEnabled: true,
            isAutoSyncEnabled: false,
            teamKey: "CUSTOM",
            pushTransport: { [todos] todo, teamKey in
                let edited = todo.withEdits(title: "Concurrent edit during push")
                try await todos.save(edited)
                return """
                {
                  "ok": true,
                  "command": "idea",
                  "issue": {
                    "id": "00000000-0000-0000-0000-000000000102",
                    "identifier": "\(teamKey)-102",
                    "title": "\(todo.title)",
                    "state": "Triage",
                    "stateType": "triage",
                    "project": "Personal project",
                    "priority": 0,
                    "url": "https://linear.app/example/issue/\(teamKey)-102",
                    "createdAt": "2026-11-09T13:00:00Z",
                    "updatedAt": "2026-11-09T13:30:00Z",
                    "labels": []
                  }
                }
                """.data(using: .utf8)!
            },
            pullTransport: { _ in Data("{\"ok\":true,\"issues\":[]}".utf8) }
        )
        let concurrentUseCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: runner,
            externalSync: slowSyncService
        )
        let merged = try await concurrentUseCase.syncTodoToExternal(todoID: concurrentTodo.id)
        XCTAssertEqual(merged.title, "Concurrent edit during push")
        XCTAssertEqual(merged.externalSync?.externalID, "CUSTOM-102")
        XCTAssertEqual(merged.externalSync?.syncState, .pendingPush)

        // Verify that deleting a todo while an external push is in flight does not resurrect the deleted item
        let deletedTodo = VoiceTodo(title: "To be deleted during push")
        try await todos.save(deletedTodo)
        let deletingSyncService = LinearTodoSyncService(
            isEnabled: true,
            isAutoSyncEnabled: false,
            teamKey: "CUSTOM",
            pushTransport: { [todos] todo, teamKey in
                try await todos.delete(by: todo.id)
                return """
                {
                  "ok": true,
                  "command": "idea",
                  "issue": {
                    "id": "00000000-0000-0000-0000-000000000103",
                    "identifier": "\(teamKey)-103",
                    "title": "\(todo.title)",
                    "state": "Triage",
                    "stateType": "triage",
                    "project": "Personal project",
                    "priority": 0,
                    "url": "https://linear.app/example/issue/\(teamKey)-103",
                    "createdAt": "2026-11-09T13:00:00Z",
                    "updatedAt": "2026-11-09T13:30:00Z",
                    "labels": []
                  }
                }
                """.data(using: .utf8)!
            },
            pullTransport: { _ in Data("{\"ok\":true,\"issues\":[]}".utf8) }
        )
        let deletingUseCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: runner,
            externalSync: deletingSyncService
        )
        _ = try await deletingUseCase.syncTodoToExternal(todoID: deletedTodo.id)
        let fetchedAfterDelete = try await todos.fetch(by: deletedTodo.id)
        XCTAssertNil(fetchedAfterDelete)
    }

    func testReconcileWatchTodoCaptureRecoversOrphanAndUnlinkedCapturesIdempotently() async throws {
        let captures = DefaultVoiceCaptureRepository()
        let todos = DefaultVoiceTodoRepository()
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let useCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir)
        )
        let basename = "\(UUID().uuidString).m4a"
        let orphan = VoiceCapture(
            mode: .todo,
            rawTranscript: "整理产品评审会议纪要",
            refinedText: "整理产品评审会议纪要。",
            localAudioFileName: basename,
            durationSeconds: 3,
            deviceSource: .appleWatch,
            state: .completed
        )
        try await captures.save(orphan)

        let converted = try await useCase.reconcileWatchTodoCapture(
            rawTranscript: orphan.rawTranscript,
            refinedText: orphan.refinedText,
            localAudioFileName: basename,
            durationSeconds: 3
        )
        let duplicate = try await useCase.reconcileWatchTodoCapture(
            rawTranscript: orphan.rawTranscript,
            refinedText: orphan.refinedText,
            localAudioFileName: basename,
            durationSeconds: 3
        )
        XCTAssertEqual(converted.id, duplicate.id)
        let savedCaptures = try await captures.fetchAll()
        let savedTodos = try await todos.fetchAll()
        XCTAssertEqual(savedCaptures.count, 1)
        XCTAssertEqual(savedTodos.count, 1)
        XCTAssertEqual(savedCaptures.first?.linkedTodoID, converted.id)
        XCTAssertEqual(savedTodos.first?.sourceCaptureID, orphan.id)
        XCTAssertEqual(savedTodos.first?.deviceSource, .appleWatch)
    }

    func testDispatchTodoToICloudAIAndStatusReportTransitions() async throws {
        let captures = DefaultVoiceCaptureRepository()
        let todos = DefaultVoiceTodoRepository()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usecase-icloud-orders-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let icloudSync = ICloudAIOrderSyncService(
            ordersDirectoryURL: tempDir,
            kvStore: InMemoryUbiquitousAIOrderKVStore()
        )
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let useCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: DefaultVoiceTodoExtractor(),
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir),
            icloudOrderSync: icloudSync
        )

        // Dispatching a missing todo throws todoNotFound
        do {
            _ = try await useCase.dispatchTodoToICloudAI(todoID: UUID())
            XCTFail("Expected todoNotFound error")
        } catch let error as VoiceTodoUseCaseError {
            XCTAssertEqual(error, .todoNotFound)
        }

        // Create a real todo and dispatch it to iCloud AI
        let todo = VoiceTodo(
            title: "验证跨端 AI 接单",
            description: "测试状态回流",
            priority: .p0,
            subtasks: [VoiceTodoSubtask(title: "子步骤 1"), VoiceTodoSubtask(title: "子步骤 2")]
        )
        try await todos.save(todo)

        let order = try await useCase.dispatchTodoToICloudAI(todoID: todo.id)
        XCTAssertEqual(order.todoID, todo.id)
        XCTAssertEqual(order.state, .queued)
        XCTAssertEqual(order.title, "")
        XCTAssertEqual(order.subtaskCount, 2)

        let afterDispatch = try await todos.fetch(by: todo.id)
        XCTAssertEqual(afterDispatch?.executionState, .running)

        // Publish claimed/running status report and verify repository updates
        _ = try await icloudSync.publishStatusReport(
            AIExecutionStatusReport(
                orderID: order.orderID,
                todoID: todo.id,
                state: .running,
                progressStage: "正在运行步骤 1",
                progressFraction: 0.5,
                assignedRunnerName: "Mac Agent"
            )
        )
        try await Task.sleep(for: .milliseconds(50))
        let duringRun = try await todos.fetch(by: todo.id)
        XCTAssertEqual(duringRun?.executionState, .running)
        XCTAssertEqual(duringRun?.lastExecutionSummary, "正在运行步骤 1")

        // Publish completed status report and verify todo transitions to .done
        _ = try await icloudSync.publishStatusReport(
            AIExecutionStatusReport(
                orderID: order.orderID,
                todoID: todo.id,
                state: .completed,
                progressStage: "执行完成",
                progressFraction: 1.0,
                outputSummary: "全部 2 步完成",
                assignedRunnerName: "Mac Agent"
            )
        )
        try await Task.sleep(for: .milliseconds(50))
        let afterCompleted = try await todos.fetch(by: todo.id)
        XCTAssertEqual(afterCompleted?.executionState, .done)
        XCTAssertEqual(afterCompleted?.lastExecutionSummary, "全部 2 步完成")

        // Publish failed status report and verify todo transitions to .failed
        _ = try await icloudSync.publishStatusReport(
            AIExecutionStatusReport(
                orderID: order.orderID,
                todoID: todo.id,
                state: .failed,
                progressStage: "执行失败",
                progressFraction: 1.0,
                outputSummary: "Runner exited 1",
                assignedRunnerName: "Mac Agent"
            )
        )
        try await Task.sleep(for: .milliseconds(50))
        let afterFailed = try await todos.fetch(by: todo.id)
        XCTAssertEqual(afterFailed?.executionState, .failed)
        XCTAssertEqual(afterFailed?.lastExecutionSummary, "Runner exited 1")
    }

    func testStage4CloudFallbackDecomposerAndDeterministicMultiStepAppend() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let fixedNow = cal.date(from: DateComponents(timeZone: cal.timeZone, year: 2026, month: 11, day: 18, hour: 10, minute: 0))!

        // 1. Verify cloud fallbackCompletion is used when on-device FoundationModels is unavailable
        let cloudDecomposer = DefaultOnDeviceAITodoDecomposer(fallbackCompletion: { instructions, _ in
            XCTAssertTrue(instructions.contains("紧急提醒我今晚8点半整理代码重构清单"))
            return """
            {
              "cleanTitle": "整理代码重构清单",
              "description": "今晚 20:30 紧急整理代码重构与单测回归清单",
              "timeSlot": "night",
              "dayOffset": 0,
              "explicitHour": 20,
              "explicitMinute": 30,
              "relativeMinutes": null,
              "priority": "P0",
              "tags": ["#Dev", "#VoxPocket"],
              "subtasks": ["跑通所有单测", "提交代码审查"]
            }
            """
        })
        let cloudResult = try await cloudDecomposer.decompose(
            transcript: "紧急提醒我今晚8点半整理代码重构清单，先跑通所有单测，再提交代码审查",
            referenceDate: fixedNow,
            knownProjectNames: ["VoxPocket"]
        )
        XCTAssertEqual(cloudResult.cleanTitle, "整理代码重构清单")
        XCTAssertEqual(cloudResult.priority, .p0)
        XCTAssertEqual(cloudResult.explicitHour, 20)
        XCTAssertEqual(cloudResult.explicitMinute, 30)
        XCTAssertEqual(cloudResult.subtasks, ["跑通所有单测", "提交代码审查"])

        // 2. Verify deterministic fallbackSentenceSplit extracts subtasks, priority, tags, and schedule offline
        let offlineResult = DefaultOnDeviceAITodoDecomposer.fallbackSentenceSplit(
            from: "紧急提醒我明天早上8点半整理下周设计评审要展示的液态玻璃交互走查清单，先录制声波走查，再验证双按钮侧滑手势 #VoxPocket",
            knownProjectNames: ["VoxPocket"]
        )
        XCTAssertLessThanOrEqual(offlineResult.cleanTitle.count, 14)
        XCTAssertEqual(offlineResult.priority, .p0)
        XCTAssertEqual(offlineResult.dayOffset, 1)
        XCTAssertEqual(offlineResult.timeSlot, "morning")
        XCTAssertEqual(offlineResult.explicitHour, 8)
        XCTAssertEqual(offlineResult.explicitMinute, 30)
        XCTAssertTrue(offlineResult.tags.contains("#VoxPocket"))
        XCTAssertEqual(offlineResult.subtasks, ["录制声波走查", "验证双按钮侧滑手势"])

        let lowPriRelative = DefaultOnDeviceAITodoDecomposer.fallbackSentenceSplit(
            from: "不急，30分钟后取顺丰快递；带上取件码；顺便寄退货 #快递"
        )
        XCTAssertEqual(lowPriRelative.priority, .p2)
        XCTAssertEqual(lowPriRelative.relativeMinutes, 30)
        XCTAssertTrue(lowPriRelative.tags.contains("#快递"))
        XCTAssertGreaterThanOrEqual(lowPriRelative.subtasks.count, 2)

        // 3. Verify appendVoiceToTodo runs Stage 4 decomposition and appends multiple subtasks + schedule + tags
        let tempHabitURL = FileManager.default.temporaryDirectory.appendingPathComponent("todo-append-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempHabitURL) }
        let learner = AdaptiveTimeAnchorLearner(store: FileHabitTimeAnchorStore(fileURL: tempHabitURL), calendar: cal)
        let center = InMemoryVoxNotificationCenter()
        let scheduler = VoxNotificationScheduler(timeAnchorLearner: learner, center: center, calendar: cal)
        let extractor = DefaultVoiceTodoExtractor(
            aiDecomposer: DefaultOnDeviceAITodoDecomposer(),
            timeAnchorLearner: learner,
            calendar: cal,
            nowProvider: { fixedNow }
        )
        let captures = DefaultVoiceCaptureRepository()
        let todos = DefaultVoiceTodoRepository()
        let sandboxDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let useCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: captures,
            todos: todos,
            extractor: extractor,
            runner: DefaultAIRunnerExecutionService(sandboxTasksDirectory: sandboxDir),
            notificationScheduler: scheduler
        )
        let created = try await useCase.recordCompletedCapture(
            mode: .todo,
            rawTranscript: "准备设计评审",
            refinedText: "准备设计评审",
            localAudioFileName: nil,
            durationSeconds: 2,
            deviceSource: .iPhone
        )
        let baseTodo = try XCTUnwrap(created.todo)
        XCTAssertTrue(baseTodo.subtasks.isEmpty)

        let appended = try await useCase.appendVoiceToTodo(
            todoID: baseTodo.id,
            rawTranscript: "紧急补充：今晚8点半前先核对降低透明度模式对比度，再导出明暗双态截图 #Glass",
            refinedText: "紧急补充：今晚8点半前先核对降低透明度模式对比度，再导出明暗双态截图 #Glass",
            localAudioFileName: nil,
            durationSeconds: 4,
            deviceSource: .iPhone
        )
        XCTAssertEqual(appended.addedSubtaskIDs.count, 2)
        XCTAssertEqual(appended.todo.subtasks.count, 2)
        XCTAssertEqual(appended.todo.priority, .p0)
        XCTAssertTrue(appended.todo.tags.contains("#Glass"))
        XCTAssertNotNil(appended.todo.scheduledAt)
        XCTAssertEqual(scheduler.pendingItems().count, 1)
    }
}
