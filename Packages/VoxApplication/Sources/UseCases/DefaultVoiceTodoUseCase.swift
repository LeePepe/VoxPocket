import Foundation
import CoreModels
import Persistence
import PlatformAdapters
import VoxNotificationKit
import VoxKitBridge
import VoxRefine
import LokiKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 基于 iPhone / Mac 端侧 Apple Intelligence (`FoundationModels.LanguageModelSession`) 的纯 AI 语音待办语义拆解器
public struct DefaultOnDeviceAITodoDecomposer: AITodoDecomposing, Sendable {
    public typealias ModelCompletionHandler = @Sendable (_ instructions: String, _ prompt: String) async throws -> String

    private let customCompletion: ModelCompletionHandler?

    public init(customCompletion: ModelCompletionHandler? = nil) {
        self.customCompletion = customCompletion
    }

    public func decompose(
        transcript: String,
        referenceDate: Date = Date(),
        anchorMinutesBySlot: [String: Int] = [:],
        knownProjectNames: [String] = []
    ) async throws -> AITodoDecompositionResult {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AITodoDecompositionResult(cleanTitle: "Untitled task")
        }

        let isoFormatter = ISO8601DateFormatter()
        let refISO = isoFormatter.string(from: referenceDate)
        let anchorsDesc = anchorMinutesBySlot
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(String(format: "%02d:%02d", $0.value / 60, $0.value % 60))" }
            .joined(separator: ", ")

        // 遵循 VoxKit AppleIntelligenceProvider.swift:150 经验：使用紧凑单次 JSON 指令而非多字段复杂 @Generable，避免端侧受限解码 120s+ 超时
        let instructions = """
        You are an on-device Voice Todo semantic decomposer. Given the user's spoken transcript, output ONLY a single compact JSON object with these keys:
        {"cleanTitle":"string (MUST be a concise 4-10 character action phrase <= 14 chars that fits on a single line, e.g. 液态玻璃交互走查, 早间播客大纲润色, 取顺丰快递; strip reminder/imperative prefixes like 提醒我/帮我记一下 and time phrases)","description":"string (detailed background context, conditions, or full spoken summary when the utterance has more detail than cleanTitle)","timeSlot":"morning|forenoon|noon|afternoon|evening|night|null","dayOffset":0,"explicitHour":null,"explicitMinute":null,"relativeMinutes":null,"priority":"P0|P1|P2","tags":["#Tag"],"subtasks":["step 1"]}
        Current time: \(refISO). User habit anchors: \(anchorsDesc). Known projects: \(knownProjectNames.joined(separator: ", ")).
        User transcript: \(trimmed)
        """

        let rawJSON: String
        if let customCompletion {
            rawJSON = try await customCompletion(instructions, "Return JSON only.")
        } else {
            rawJSON = try await Self.invokeFoundationModels(instructions: instructions)
        }

        if let parsed = Self.parseJSONResponse(rawJSON, fallbackTranscript: trimmed) {
            return parsed
        }
        return Self.fallbackSentenceSplit(from: trimmed)
    }

    private static func invokeFoundationModels(instructions: String) async throws -> String {
        // 在 UI 自动化测试或离线 Demo 播种中跳过端侧大模型 XPC 调用，避免 iOS Simulator FoundationModels daemon 超时阻塞主流程
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        if env["VOXPOCKET_UI_TEST_HOST"] == "1" || env["VOX_DEMO_SEED"] == "1" || env["XCTestConfigurationFilePath"] != nil || args.contains("--vox-ui-test-host") {
            throw NSError(domain: "DefaultOnDeviceAITodoDecomposer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Skipped in UI test / demo mode"])
        }
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else {
            throw NSError(domain: "DefaultOnDeviceAITodoDecomposer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence unavailable"])
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Output compact JSON only.")
        return response.content
        #else
        throw NSError(domain: "DefaultOnDeviceAITodoDecomposer", code: 2, userInfo: [NSLocalizedDescriptionKey: "FoundationModels unavailable"])
        #endif
    }

    internal static func parseJSONResponse(_ raw: String, fallbackTranscript: String) -> AITodoDecompositionResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIdx = trimmed.firstIndex(of: "{"),
              let endIdx = trimmed.lastIndex(of: "}") else {
            return nil
        }
        let jsonSlice = String(trimmed[startIdx...endIdx])
        guard let data = jsonSlice.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let rawTitle = (dict["cleanTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawDescription = (dict["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let (cleanTitle, compactedDescription) = compactActionTitle(from: rawTitle.isEmpty ? fallbackTranscript : rawTitle, fallbackContext: fallbackTranscript)
        let resolvedDescription = !rawDescription.isEmpty ? rawDescription : compactedDescription

        let rawSlot = (dict["timeSlot"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let timeSlot: String? = (rawSlot != nil && rawSlot != "null" && !rawSlot!.isEmpty && HabitTimeSlot(rawValue: rawSlot!) != nil)
            ? rawSlot
            : nil

        let dayOffset = max(0, (dict["dayOffset"] as? Int) ?? 0)
        let explicitHour = dict["explicitHour"] as? Int
        let explicitMinute = dict["explicitMinute"] as? Int
        let relativeMinutes = dict["relativeMinutes"] as? Int

        let rawPriority = ((dict["priority"] as? String) ?? "P1").uppercased()
        let priority = TodoPriority(rawValue: rawPriority) ?? .p1

        let rawTags = (dict["tags"] as? [String]) ?? []
        let tags = VoiceTodo.normalizeTags(rawTags)

        let rawSubtasks = (dict["subtasks"] as? [String]) ?? []
        let subtasks = rawSubtasks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return AITodoDecompositionResult(
            cleanTitle: cleanTitle.isEmpty ? "Untitled task" : cleanTitle,
            description: resolvedDescription,
            timeSlot: timeSlot,
            dayOffset: dayOffset,
            explicitHour: explicitHour,
            explicitMinute: explicitMinute,
            relativeMinutes: relativeMinutes,
            priority: priority,
            tags: tags,
            subtasks: subtasks
        )
    }

    internal static func fallbackSentenceSplit(from source: String) -> AITodoDecompositionResult {
        let normalizedSource = source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = normalizedSource.split(whereSeparator: { ".!?。！？\n".contains($0) }).first.map(String.init) ?? normalizedSource
        let (shortTitle, extractedDescription) = compactActionTitle(from: sentence, fallbackContext: normalizedSource)
        return AITodoDecompositionResult(
            cleanTitle: shortTitle.isEmpty ? "Untitled task" : shortTitle,
            description: extractedDescription
        )
    }

    internal static func compactActionTitle(from value: String, fallbackContext: String = "") -> (title: String, description: String) {
        let fullSource = (fallbackContext.isEmpty ? value : fallbackContext)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！？.!?"))
        var candidate = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！？.!?"))

        let reminderPrefixes = [
            "请提醒我", "麻烦提醒我", "帮我提醒一下", "提醒我一下", "提醒我",
            "帮我记一下", "帮我记录一下", "帮我记个待办", "记一下", "记得",
            "需要", "我要", "待办：", "待办:"
        ]
        for prefix in reminderPrefixes where candidate.hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let timePrefixes = [
            "今天早上", "今天上午", "今天中午", "今天下午", "今天傍晚", "今天晚上",
            "明天早上", "明天上午", "明天中午", "明天下午", "明天傍晚", "明天晚上",
            "后天早上", "后天上午", "后天下午", "后天晚上",
            "下周一", "下周二", "下周三", "下周四", "下周五", "下周",
            "早上", "上午", "中午", "下午", "傍晚", "晚上", "今晚", "明早", "明天", "今天"
        ]
        for prefix in timePrefixes where candidate.hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let strippedContext = candidate
        guard candidate.count > 14 else {
            let desc = (fullSource.count > candidate.count && fullSource != candidate) ? fullSource : ""
            return (candidate, desc)
        }

        // First clause before comma/semicolon
        if let firstClause = candidate.split(whereSeparator: { "，,；;：:—-".contains($0) }).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !firstClause.isEmpty {
            candidate = firstClause
        }

        // Strip verbose relative modifier clauses ("要展示的", "录下的", etc.) when still > 14 chars
        if candidate.count > 14 {
            let clausePatterns = [
                "下周设计评审要展示的",
                "设计评审要展示的",
                "早间散步录下的",
                "刚才散步想到的",
                "散步录下的"
            ]
            for pattern in clausePatterns where candidate.contains(pattern) {
                candidate = candidate.replacingOccurrences(of: pattern, with: "")
            }
        }

        if candidate.count > 14, let deRange = candidate.range(of: "的") {
            let suffixAfterDe = String(candidate[deRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (4...12).contains(suffixAfterDe.count) {
                candidate = suffixAfterDe
            }
        }

        if candidate.count > 14 {
            candidate = String(candidate.prefix(14)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let finalDescription = !strippedContext.isEmpty ? strippedContext : fullSource
        return (candidate, finalDescription)
    }

    internal static func compactTitle(_ value: String) -> String {
        compactActionTitle(from: value).title
    }
}

public struct DefaultVoiceTodoExtractor: VoiceTodoExtractionRunning {
    private let aiDecomposer: any AITodoDecomposing
    private let timeAnchorLearner: any AdaptiveTimeAnchorLearning
    private let nowProvider: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        aiDecomposer: any AITodoDecomposing = DefaultOnDeviceAITodoDecomposer(),
        timeAnchorLearner: any AdaptiveTimeAnchorLearning = AdaptiveTimeAnchorLearner(),
        calendar: Calendar = .current,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.aiDecomposer = aiDecomposer
        self.timeAnchorLearner = timeAnchorLearner
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    public func extractTodo(from rawTranscript: String, refinedText: String, availableProjects: [ProjectBinding]) async throws -> ExtractedTodoDraft {
        let source = refinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawTranscript : refinedText
        let promptSource = source.isEmpty ? rawTranscript : source
        let now = nowProvider()

        let anchorSummary = timeAnchorLearner.currentAnchorSummary(for: [], now: now)
        var anchorMap: [String: Int] = [:]
        for (slot, minutes) in anchorSummary {
            anchorMap[slot.rawValue] = minutes
        }

        let decomposition: AITodoDecompositionResult
        if let aiResult = try? await aiDecomposer.decompose(
            transcript: promptSource,
            referenceDate: now,
            anchorMinutesBySlot: anchorMap,
            knownProjectNames: availableProjects.map(\.displayName)
        ) {
            decomposition = aiResult
        } else {
            decomposition = DefaultOnDeviceAITodoDecomposer.fallbackSentenceSplit(from: source)
        }

        let (scheduledAt, resolvedSlot) = resolveSchedule(from: decomposition, now: now)

        var promptLines = [
            "## Goal",
            promptSource.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "## Context",
            "Created from a voice capture."
        ]
        if !decomposition.subtasks.isEmpty {
            promptLines.append("")
            for step in decomposition.subtasks {
                promptLines.append("- [ ] \(step)")
            }
        }

        return ExtractedTodoDraft(
            title: decomposition.cleanTitle.isEmpty ? "Untitled task" : decomposition.cleanTitle,
            description: decomposition.description,
            taskPrompt: promptLines.joined(separator: "\n"),
            matchedProjectKey: ProjectBinding.matchProjectKey(in: source, bindings: availableProjects),
            priority: decomposition.priority,
            tags: decomposition.tags,
            subtasks: decomposition.subtasks,
            scheduledAt: scheduledAt,
            timeSlot: resolvedSlot
        )
    }

    private func resolveSchedule(from result: AITodoDecompositionResult, now: Date) -> (Date?, String?) {
        if let relativeMinutes = result.relativeMinutes, relativeMinutes > 0 {
            let clampedMinutes = min(relativeMinutes, 525_600) // 上限 365 天，防止大模型输出极端整数触发乘法溢出
            let fireDate = now.addingTimeInterval(TimeInterval(clampedMinutes) * 60.0)
            let comps = calendar.dateComponents([.hour, .minute], from: fireDate)
            let mins = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
            let slot = HabitTimeSlot.inferSlot(fromMinutesFromMidnight: mins)
            return (fireDate, slot.rawValue)
        }

        if let hour = result.explicitHour, (0..<24).contains(hour) {
            let minute = max(0, min(59, result.explicitMinute ?? 0))
            let clampedDayOffset = max(0, min(result.dayOffset, 365))
            let startOfToday = calendar.startOfDay(for: now)
            let baseDay = calendar.date(byAdding: .day, value: clampedDayOffset, to: startOfToday) ?? startOfToday
            var target = calendar.date(byAdding: .minute, value: hour * 60 + minute, to: baseDay) ?? now.addingTimeInterval(3600)
            if clampedDayOffset == 0 && target <= now.addingTimeInterval(60) {
                target = calendar.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86_400)
            }
            let inferredSlot = result.timeSlot.flatMap(HabitTimeSlot.init(rawValue:))
                ?? HabitTimeSlot.inferSlot(fromMinutesFromMidnight: hour * 60 + minute)
            return (target, inferredSlot.rawValue)
        }

        if let slotRaw = result.timeSlot, let habitSlot = HabitTimeSlot(rawValue: slotRaw) {
            let clampedDayOffset = max(0, min(result.dayOffset, 365))
            let resolved = timeAnchorLearner.resolveAnchor(
                for: habitSlot,
                dayOffset: clampedDayOffset,
                tags: result.tags,
                now: now
            )
            return (resolved.targetDate, habitSlot.rawValue)
        }

        return (nil, nil)
    }
}

public enum VoiceTodoUseCaseError: Error, LocalizedError, Sendable {
    case captureNotFound
    case todoNotFound
    case projectNotFound
    case inconsistentWatchCapture
    public var errorDescription: String? {
        switch self { case .captureNotFound: "Capture not found"; case .todoNotFound: "Todo not found"; case .projectNotFound: "Project not found"; case .inconsistentWatchCapture: "Inconsistent Watch capture state" }
    }
}

public final class DefaultVoiceCaptureAndTodoUseCase: VoiceCaptureAndTodoUseCase, Sendable {
    private let captures: any VoiceCaptureRepository
    private let todos: any VoiceTodoRepository
    private let extractor: any VoiceTodoExtractionRunning
    private let runner: any AIRunnerExecutionService
    private let externalSync: any TodoExternalSyncService
    private let notificationScheduler: any VoxNotificationScheduling
    private let projects: @Sendable () -> [ProjectBinding]
    private let telemetry: any TelemetryService
    private let actionEventsTask: Task<Void, Never>?

    public init(
        captures: any VoiceCaptureRepository,
        todos: any VoiceTodoRepository,
        extractor: (any VoiceTodoExtractionRunning)? = nil,
        runner: any AIRunnerExecutionService,
        externalSync: any TodoExternalSyncService = NoopTodoExternalSyncService(),
        notificationScheduler: any VoxNotificationScheduling = VoxNotificationScheduler(),
        projects: @escaping @Sendable () -> [ProjectBinding] = { [] },
        telemetry: any TelemetryService = NoopTelemetryService()
    ) {
        self.captures = captures
        self.todos = todos
        self.extractor = extractor ?? DefaultVoiceTodoExtractor(timeAnchorLearner: notificationScheduler.timeAnchorLearner)
        self.runner = runner
        self.externalSync = externalSync
        self.notificationScheduler = notificationScheduler
        self.projects = projects
        self.telemetry = telemetry

        let todosRepo = todos
        let eventsStream = notificationScheduler.actionEvents
        self.actionEventsTask = Task {
            for await event in eventsStream {
                switch event.action {
                case .markDone:
                    _ = try? await todosRepo.update(id: event.itemID) { current in
                        current
                            .withExecutionState(.done, completedAt: event.triggeredAt)
                            .withReminder(scheduledAt: nil, timeSlot: current.timeSlot, updatedAt: event.triggeredAt)
                    }
                case .snooze15m, .snooze1h, .deferToNextAnchor:
                    if let newDate = event.rescheduledFireDate {
                        _ = try? await todosRepo.update(id: event.itemID) { current in
                            current.withReminder(
                                scheduledAt: newDate,
                                timeSlot: event.slot?.rawValue ?? current.timeSlot,
                                updatedAt: event.triggeredAt
                            )
                        }
                    }
                }
            }
        }
    }

    deinit {
        actionEventsTask?.cancel()
    }

    public var localNotificationScheduler: any VoxNotificationScheduling {
        notificationScheduler
    }

    public func recordCompletedCapture(mode: CaptureMode, rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> (capture: VoiceCapture, todo: VoiceTodo?) {
        let capture = VoiceCapture(mode: mode, rawTranscript: rawTranscript, refinedText: refinedText, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, state: .completed)
        try await captures.save(capture)
        let todo: VoiceTodo?
        if mode == .todo {
            let draft = try await extractor.extractTodo(from: rawTranscript, refinedText: refinedText, availableProjects: projects())
            var created = VoiceTodo(
                title: draft.title,
                description: draft.description,
                taskPrompt: draft.taskPrompt,
                rawTranscript: rawTranscript,
                projectKey: draft.matchedProjectKey,
                priority: draft.priority,
                tags: draft.tags,
                subtasks: draft.subtasks.map { VoiceTodoSubtask(title: $0) },
                scheduledAt: draft.scheduledAt,
                timeSlot: draft.timeSlot,
                sourceCaptureID: capture.id,
                localAudioFileName: localAudioFileName,
                durationSeconds: durationSeconds,
                deviceSource: deviceSource
            )
            try await todos.save(created)
            await syncNotificationSchedule(for: created)
            if externalSync.isEnabled && externalSync.isAutoSyncEnabled {
                created = await pushBestEffort(created, fallbackStateOnFailure: .pendingPush)
            }
            todo = created
            try await captures.save(capture.withLinkedTodo(created.id))
        } else { todo = nil }
        telemetry.track(name: "capture.completed", properties: ["duration_ms": String(Int(durationSeconds * 1000)), "mode": mode.rawValue, "source": deviceSource.rawValue])
        return (todo == nil ? capture : capture.withLinkedTodo(todo!.id), todo)
    }

    public func reconcileWatchTodoCapture(rawTranscript: String, refinedText: String, localAudioFileName: String, durationSeconds: TimeInterval) async throws -> VoiceTodo {
        let matchedCaptures = try await captures.fetchAll().filter { $0.localAudioFileName == localAudioFileName }
        let matchedTodos = try await todos.fetchAll().filter { $0.localAudioFileName == localAudioFileName }
        guard matchedCaptures.count <= 1, matchedTodos.count <= 1,
              matchedCaptures.allSatisfy({ $0.deviceSource == .appleWatch && $0.mode == .todo && $0.durationSeconds == durationSeconds }),
              matchedTodos.allSatisfy({ $0.deviceSource == .appleWatch && $0.durationSeconds == durationSeconds }) else {
            throw VoiceTodoUseCaseError.inconsistentWatchCapture
        }
        if let todo = matchedTodos.first {
            guard let sourceID = todo.sourceCaptureID else { throw VoiceTodoUseCaseError.inconsistentWatchCapture }
            if let source = try await captures.fetch(by: sourceID) {
                guard source.localAudioFileName == localAudioFileName, source.deviceSource == .appleWatch,
                      source.mode == .todo, source.durationSeconds == durationSeconds else {
                    throw VoiceTodoUseCaseError.inconsistentWatchCapture
                }
            }
            if let capture = matchedCaptures.first {
                guard todo.sourceCaptureID == capture.id,
                      capture.linkedTodoID == nil || capture.linkedTodoID == todo.id else {
                    throw VoiceTodoUseCaseError.inconsistentWatchCapture
                }
                if capture.linkedTodoID == nil, let fresh = try await captures.fetch(by: capture.id) {
                    guard fresh.linkedTodoID == nil || fresh.linkedTodoID == todo.id else {
                        throw VoiceTodoUseCaseError.inconsistentWatchCapture
                    }
                    try await captures.save(fresh.withLinkedTodo(todo.id))
                }
            }
            return todo
        }
        if let capture = matchedCaptures.first {
            guard capture.linkedTodoID == nil else { throw VoiceTodoUseCaseError.inconsistentWatchCapture }
            return try await convertCaptureToTodo(captureID: capture.id)
        }
        let result = try await recordCompletedCapture(
            mode: .todo,
            rawTranscript: rawTranscript,
            refinedText: refinedText,
            localAudioFileName: localAudioFileName,
            durationSeconds: durationSeconds,
            deviceSource: .appleWatch
        )
        guard let todo = result.todo else { throw VoiceTodoUseCaseError.inconsistentWatchCapture }
        return todo
    }

    public func recordFailedCapture(mode: CaptureMode, stage: FailureStage, reason: String, rawTranscript: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> VoiceCapture {
        let capture = VoiceCapture(mode: mode, rawTranscript: rawTranscript, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, state: .failed(stage: stage, reason: reason))
        try await captures.save(capture)
        telemetry.track(name: "capture.failed", properties: ["duration_ms": String(Int(durationSeconds * 1000)), "mode": mode.rawValue, "source": deviceSource.rawValue])
        return capture
    }

    public func retryCapture(id: UUID, targetMode: CaptureMode?) async throws -> (capture: VoiceCapture, todo: VoiceTodo?) {
        guard let old = try await captures.fetch(by: id) else { throw VoiceTodoUseCaseError.captureNotFound }
        return try await recordCompletedCapture(mode: targetMode ?? old.mode, rawTranscript: old.rawTranscript, refinedText: old.refinedText, localAudioFileName: old.localAudioFileName, durationSeconds: old.durationSeconds, deviceSource: old.deviceSource)
    }

    public func convertCaptureToTodo(captureID: UUID) async throws -> VoiceTodo {
        guard let capture = try await captures.fetch(by: captureID) else { throw VoiceTodoUseCaseError.captureNotFound }
        let draft = try await extractor.extractTodo(from: capture.rawTranscript, refinedText: capture.refinedText, availableProjects: projects())
        var todo = VoiceTodo(
            title: draft.title,
            description: draft.description,
            taskPrompt: draft.taskPrompt,
            rawTranscript: capture.rawTranscript,
            projectKey: draft.matchedProjectKey,
            priority: draft.priority,
            tags: draft.tags,
            subtasks: draft.subtasks.map { VoiceTodoSubtask(title: $0) },
            scheduledAt: draft.scheduledAt,
            timeSlot: draft.timeSlot,
            sourceCaptureID: capture.id,
            localAudioFileName: capture.localAudioFileName,
            durationSeconds: capture.durationSeconds,
            deviceSource: capture.deviceSource
        )
        try await todos.save(todo)
        await syncNotificationSchedule(for: todo)
        if externalSync.isEnabled && externalSync.isAutoSyncEnabled {
            todo = await pushBestEffort(todo, fallbackStateOnFailure: .pendingPush)
        }
        try await captures.save(capture.withLinkedTodo(todo.id))
        return todo
    }

    public func updateTodo(_ todo: VoiceTodo) async throws -> VoiceTodo {
        try await todos.save(todo)
        await syncNotificationSchedule(for: todo)
        guard todo.externalSync != nil else { return todo }
        let queued = try await todos.update(id: todo.id) { current in
            current.withExternalSync(self.pendingMetadata(for: current), updatedAt: current.updatedAt)
        } ?? todo.withExternalSync(pendingMetadata(for: todo), updatedAt: todo.updatedAt)
        guard externalSync.isEnabled else { return queued }
        return await pushBestEffort(queued, fallbackStateOnFailure: .pendingPush)
    }

    public func rescheduleTodoReminder(todoID: UUID, newDate: Date, timeSlot: String? = nil) async throws -> VoiceTodo {
        guard let current = try await todos.fetch(by: todoID) else {
            throw VoiceTodoUseCaseError.todoNotFound
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
        let mins = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
        let resolvedSlot = timeSlot.flatMap(HabitTimeSlot.init(rawValue:))
            ?? current.timeSlot.flatMap(HabitTimeSlot.init(rawValue:))
            ?? HabitTimeSlot.inferSlot(fromMinutesFromMidnight: mins)
        let updated = current.withReminder(scheduledAt: newDate, timeSlot: resolvedSlot.rawValue)
        try await todos.save(updated)

        let priorityLevel: VoxNotificationInterruptionPriority = (updated.priority == .p0) ? .high : ((updated.priority == .p2) ? .low : .normal)
        _ = try? await notificationScheduler.rescheduleManualOverride(
            itemID: updated.id,
            title: updated.title,
            subtitle: updated.tags.isEmpty ? nil : updated.tags.joined(separator: " "),
            body: nil,
            newFireDate: newDate,
            slot: resolvedSlot,
            tags: updated.tags,
            priority: priorityLevel
        )
        return updated
    }

    public func runTodoWithAI(todoID: UUID, project: ProjectBinding, template: AIRunnerTemplate) async throws -> VoiceTodo {
        guard let todo = try await todos.fetch(by: todoID) else { throw VoiceTodoUseCaseError.todoNotFound }
        let started = todo.withExecutionState(.running, runnerKind: template.kind, startedAt: Date())
        try await todos.save(started)
        do {
            let result = try await runner.execute(todo: started, project: project, template: template)
            let completed = started.withExecutionState(result.exitCode == 0 ? .done : .failed, summary: result.outputSummary, completedAt: Date())
            try await todos.save(completed); return completed
        } catch {
            let failed = started.withExecutionState(.failed, summary: "Runner failed", completedAt: Date())
            try? await todos.save(failed); throw error
        }
    }

    public func markTodoDone(todoID: UUID) async throws -> VoiceTodo {
        guard let done = try await todos.update(id: todoID, transform: { current in
            current.withExecutionState(.done, completedAt: Date())
        }) else { throw VoiceTodoUseCaseError.todoNotFound }
        await notificationScheduler.cancel(itemID: todoID)
        if let slotRaw = done.timeSlot, let habitSlot = HabitTimeSlot(rawValue: slotRaw) {
            _ = notificationScheduler.timeAnchorLearner.recordSignal(
                .completedNearNotification(completedAt: done.lastCompletedAt ?? Date()),
                for: habitSlot,
                tags: done.tags
            )
        }
        guard done.externalSync != nil || (externalSync.isEnabled && externalSync.isAutoSyncEnabled) else {
            return done
        }
        let queued = try await todos.update(id: todoID) { current in
            current.withExternalSync(self.pendingMetadata(for: current), updatedAt: current.updatedAt)
        } ?? done.withExternalSync(pendingMetadata(for: done), updatedAt: done.updatedAt)
        guard externalSync.isEnabled else { return queued }
        return await pushBestEffort(queued, fallbackStateOnFailure: .pendingPush)
    }

    public func syncTodoToExternal(todoID: UUID) async throws -> VoiceTodo {
        guard let pending = try await todos.update(id: todoID, transform: { current in
            current.withExternalSync(self.pendingMetadata(for: current), updatedAt: current.updatedAt)
        }) else { throw VoiceTodoUseCaseError.todoNotFound }
        return await pushBestEffort(pending, fallbackStateOnFailure: .failed)
    }

    public func refreshExternalTodos() async throws -> [VoiceTodo] {
        guard externalSync.isEnabled else { return try await todos.fetchAll() }
        let initialTodos = try await todos.fetchAll()
        for item in initialTodos where item.externalSync?.syncState == .pendingPush {
            guard let latest = try await todos.fetch(by: item.id),
                  latest.externalSync?.syncState == .pendingPush else { continue }
            _ = await pushBestEffort(latest, fallbackStateOnFailure: .pendingPush)
        }
        guard let snapshots = try? await externalSync.fetchRemoteSnapshots() else {
            return try await todos.fetchAll()
        }
        let snapshotsByID = Dictionary(
            snapshots.map { ($0.externalID, $0) },
            uniquingKeysWith: { first, second in
                (second.remoteUpdatedAt ?? "") >= (first.remoteUpdatedAt ?? "") ? second : first
            }
        )
        let currentTodos = try await todos.fetchAll()
        for item in currentTodos {
            guard let externalID = item.externalSync?.externalID,
                  let remote = snapshotsByID[externalID] else { continue }
            _ = try await todos.update(id: item.id) { current in
                guard let metadata = current.externalSync,
                      metadata.syncState != .pendingPush,
                      metadata.externalID == externalID else {
                    return nil
                }
                let isNewer: Bool
                if let remoteUpdated = remote.remoteUpdatedAt, let localRemoteUpdated = metadata.remoteUpdatedAt {
                    isNewer = remoteUpdated > localRemoteUpdated
                } else {
                    isNewer = remote.remoteUpdatedAt != nil && metadata.remoteUpdatedAt == nil
                }
                guard isNewer else { return nil }
                let updatedMeta = metadata.withState(
                    .synced,
                    externalID: .some(remote.externalID),
                    externalURL: remote.externalURL != nil ? .some(remote.externalURL) : nil,
                    teamKey: remote.teamKey,
                    projectName: remote.projectName != nil ? .some(remote.projectName) : nil,
                    remoteUpdatedAt: .some(remote.remoteUpdatedAt),
                    lastError: .some(nil)
                )
                return current
                    .withEdits(title: remote.title)
                    .withExecutionState(
                        remote.executionState,
                        summary: current.lastExecutionSummary,
                        startedAt: current.lastStartedAt,
                        completedAt: remote.executionState == .done ? (current.lastCompletedAt ?? Date()) : current.lastCompletedAt
                    )
                    .withExternalSync(updatedMeta)
            }
        }
        return try await todos.fetchAll()
    }

    public func deleteCapture(id: UUID) async throws { try await captures.delete(by: id) }
    public func deleteTodo(id: UUID) async throws {
        await notificationScheduler.cancel(itemID: id)
        try await todos.delete(by: id)
    }
    public func fetchCaptures() async throws -> [VoiceCapture] { try await captures.fetchAll() }
    public func fetchTodos() async throws -> [VoiceTodo] { try await todos.fetchAll() }

    private func syncNotificationSchedule(for todo: VoiceTodo) async {
        guard todo.executionState != .done, let fireDate = todo.scheduledAt else {
            await notificationScheduler.cancel(itemID: todo.id)
            return
        }
        let slot = todo.timeSlot.flatMap(HabitTimeSlot.init(rawValue:))
        let priorityLevel: VoxNotificationInterruptionPriority = (todo.priority == .p0) ? .high : ((todo.priority == .p2) ? .low : .normal)
        let item = VoxScheduledNotificationItem(
            itemID: todo.id,
            title: todo.title,
            subtitle: todo.tags.isEmpty ? nil : todo.tags.joined(separator: " "),
            body: nil,
            fireDate: fireDate,
            slot: slot,
            tags: todo.tags,
            priority: priorityLevel
        )
        _ = try? await notificationScheduler.schedule(item)
    }

    private func pendingMetadata(for todo: VoiceTodo) -> ExternalTodoSyncMetadata {
        if let existing = todo.externalSync {
            let resolvedTeam = existing.externalID != nil ? existing.teamKey : externalSync.configuredTeamKey
            return existing.withState(.pendingPush, teamKey: resolvedTeam)
        }
        return ExternalTodoSyncMetadata(teamKey: externalSync.configuredTeamKey, syncState: .pendingPush)
    }

    private func pushBestEffort(_ snapshot: VoiceTodo, fallbackStateOnFailure: ExternalTodoSyncState) async -> VoiceTodo {
        let baseMeta = pendingMetadata(for: snapshot)
        do {
            let syncedMeta = try await externalSync.pushTodo(snapshot)
            let updated = try? await todos.update(id: snapshot.id) { current in
                let localChangedDuringPush = current.title != snapshot.title
                    || current.description != snapshot.description
                    || current.taskPrompt != snapshot.taskPrompt
                    || current.executionState != snapshot.executionState
                    || current.projectKey != snapshot.projectKey
                    || current.updatedAt != snapshot.updatedAt
                let finalMeta = localChangedDuringPush ? syncedMeta.withState(.pendingPush) : syncedMeta
                return current.withExternalSync(finalMeta, updatedAt: current.updatedAt)
            }
            return updated ?? snapshot.withExternalSync(syncedMeta)
        } catch {
            let failedMeta = baseMeta.withState(fallbackStateOnFailure, lastError: .some(error.localizedDescription))
            let updated = try? await todos.update(id: snapshot.id) { current in
                let localChangedDuringPush = current.title != snapshot.title
                    || current.description != snapshot.description
                    || current.taskPrompt != snapshot.taskPrompt
                    || current.executionState != snapshot.executionState
                    || current.projectKey != snapshot.projectKey
                    || current.updatedAt != snapshot.updatedAt
                let targetState = localChangedDuringPush ? ExternalTodoSyncState.pendingPush : fallbackStateOnFailure
                return current.withExternalSync(failedMeta.withState(targetState), updatedAt: current.updatedAt)
            }
            return updated ?? snapshot.withExternalSync(failedMeta)
        }
    }
}
