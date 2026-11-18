import Foundation
import CoreModels

/// 端侧 AI（Apple Intelligence `FoundationModels.LanguageModelSession`）对转写文本执行语义拆分后的结构化结果
public struct AITodoDecompositionResult: Codable, Equatable, Sendable {
    public let cleanTitle: String
    public let description: String
    public let timeSlot: String?
    public let dayOffset: Int
    public let explicitHour: Int?
    public let explicitMinute: Int?
    public let relativeMinutes: Int?
    public let priority: TodoPriority
    public let tags: [String]
    public let subtasks: [String]

    public init(
        cleanTitle: String,
        description: String = "",
        timeSlot: String? = nil,
        dayOffset: Int = 0,
        explicitHour: Int? = nil,
        explicitMinute: Int? = nil,
        relativeMinutes: Int? = nil,
        priority: TodoPriority = .p1,
        tags: [String] = [],
        subtasks: [String] = []
    ) {
        self.cleanTitle = cleanTitle
        self.description = description
        self.timeSlot = timeSlot
        self.dayOffset = dayOffset
        self.explicitHour = explicitHour
        self.explicitMinute = explicitMinute
        self.relativeMinutes = relativeMinutes
        self.priority = priority
        self.tags = tags
        self.subtasks = subtasks
    }
}

/// 端侧 AI 待办语义拆解协议（由 `FoundationModels.LanguageModelSession` 实现，单测可注入 Mock）
public protocol AITodoDecomposing: Sendable {
    func decompose(
        transcript: String,
        referenceDate: Date,
        anchorMinutesBySlot: [String: Int],
        knownProjectNames: [String]
    ) async throws -> AITodoDecompositionResult
}

public protocol VoiceTodoExtractionRunning: Sendable {
    func extractTodo(from rawTranscript: String, refinedText: String, availableProjects: [ProjectBinding]) async throws -> ExtractedTodoDraft
}

public struct ExtractedTodoDraft: Equatable, Sendable {
    public let title: String
    public let description: String
    public let taskPrompt: String
    public let matchedProjectKey: String?
    public let priority: TodoPriority
    public let tags: [String]
    public let subtasks: [String]
    public let scheduledAt: Date?
    public let timeSlot: String?

    public init(
        title: String,
        description: String = "",
        taskPrompt: String,
        matchedProjectKey: String?,
        priority: TodoPriority = .p1,
        tags: [String] = [],
        subtasks: [String] = [],
        scheduledAt: Date? = nil,
        timeSlot: String? = nil
    ) {
        self.title = title
        self.description = description
        self.taskPrompt = taskPrompt
        self.matchedProjectKey = matchedProjectKey
        self.priority = priority
        self.tags = VoiceTodo.normalizeTags(tags)
        self.subtasks = subtasks
        self.scheduledAt = scheduledAt
        self.timeSlot = timeSlot
    }
}

public protocol VoiceCaptureAndTodoUseCase: AnyObject, Sendable {
    func recordCompletedCapture(mode: CaptureMode, rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> (capture: VoiceCapture, todo: VoiceTodo?)
    func appendVoiceToTodo(todoID: UUID, rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> (todo: VoiceTodo, addedSubtaskIDs: [UUID])
    func reconcileWatchTodoCapture(rawTranscript: String, refinedText: String, localAudioFileName: String, durationSeconds: TimeInterval) async throws -> VoiceTodo
    func recordFailedCapture(mode: CaptureMode, stage: FailureStage, reason: String, rawTranscript: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> VoiceCapture
    func retryCapture(id: UUID, targetMode: CaptureMode?) async throws -> (capture: VoiceCapture, todo: VoiceTodo?)
    func convertCaptureToTodo(captureID: UUID) async throws -> VoiceTodo
    func updateTodo(_ todo: VoiceTodo) async throws -> VoiceTodo
    func rescheduleTodoReminder(todoID: UUID, newDate: Date, timeSlot: String?) async throws -> VoiceTodo
    func runTodoWithAI(todoID: UUID, project: ProjectBinding, template: AIRunnerTemplate) async throws -> VoiceTodo
    func dispatchTodoToICloudAI(todoID: UUID) async throws -> ICloudAIExecutionOrder
    var aiOrderStatusReports: AsyncStream<AIExecutionStatusReport> { get }
    func markTodoDone(todoID: UUID) async throws -> VoiceTodo
    func syncTodoToExternal(todoID: UUID) async throws -> VoiceTodo
    func refreshExternalTodos() async throws -> [VoiceTodo]
    func deleteCapture(id: UUID) async throws
    func deleteTodo(id: UUID) async throws
    func fetchCaptures() async throws -> [VoiceCapture]
    func fetchTodos() async throws -> [VoiceTodo]
}

public extension VoiceCaptureAndTodoUseCase {
    func appendVoiceToTodo(todoID: UUID, rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> (todo: VoiceTodo, addedSubtaskIDs: [UUID]) {
        let cleaned = (refinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawTranscript : refinedText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRaw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleaned : rawTranscript
        _ = try await recordCompletedCapture(
            mode: .text,
            rawTranscript: effectiveRaw,
            refinedText: cleaned,
            localAudioFileName: localAudioFileName,
            durationSeconds: durationSeconds,
            deviceSource: deviceSource
        )
        guard let current = try await fetchTodos().first(where: { $0.id == todoID }) else {
            throw NSError(domain: "VoiceTodoUseCase", code: 404)
        }
        let decomposition = DefaultOnDeviceAITodoDecomposer.fallbackSentenceSplit(from: cleaned)
        let subtaskTitles = decomposition.subtasks.count >= 2 ? decomposition.subtasks : [cleaned]
        let existingIDs = Set(current.subtasks.map(\.id))
        var updated = current
        for title in subtaskTitles where !title.isEmpty {
            updated = updated.withAppendedSubtask(title)
        }
        if !decomposition.tags.isEmpty {
            updated = updated.withTags(VoiceTodo.normalizeTags(updated.tags + decomposition.tags))
        }
        if decomposition.priority == .p0 && updated.priority != .p0 {
            updated = updated.withPriority(.p0)
        }
        let saved = try await updateTodo(updated)
        let addedIDs = saved.subtasks.map(\.id).filter { !existingIDs.contains($0) }
        return (saved, addedIDs)
    }

    func rescheduleTodoReminder(todoID: UUID, newDate: Date, timeSlot: String?) async throws -> VoiceTodo {
        guard let existing = try await fetchTodos().first(where: { $0.id == todoID }) else {
            throw NSError(domain: "VoiceTodoUseCase", code: 404)
        }
        return try await updateTodo(existing.withReminder(scheduledAt: newDate, timeSlot: timeSlot))
    }

    func reconcileWatchTodoCapture(rawTranscript: String, refinedText: String, localAudioFileName: String, durationSeconds: TimeInterval) async throws -> VoiceTodo {
        let outcome = try await recordCompletedCapture(
            mode: .todo,
            rawTranscript: rawTranscript,
            refinedText: refinedText,
            localAudioFileName: localAudioFileName,
            durationSeconds: durationSeconds,
            deviceSource: .appleWatch
        )
        guard let todo = outcome.todo else {
            throw NSError(domain: "VoiceTodoUseCase", code: 500)
        }
        return todo
    }

    func syncTodoToExternal(todoID: UUID) async throws -> VoiceTodo {
        guard let existing = try await fetchTodos().first(where: { $0.id == todoID }) else {
            throw NSError(domain: "VoiceTodoUseCase", code: 404)
        }
        return existing
    }

    func dispatchTodoToICloudAI(todoID: UUID) async throws -> ICloudAIExecutionOrder {
        guard let existing = try await fetchTodos().first(where: { $0.id == todoID }) else {
            throw NSError(domain: "VoiceTodoUseCase", code: 404)
        }
        return ICloudAIExecutionOrder(from: existing).sanitizedForCloudSync()
    }

    var aiOrderStatusReports: AsyncStream<AIExecutionStatusReport> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func refreshExternalTodos() async throws -> [VoiceTodo] {
        try await fetchTodos()
    }
}
