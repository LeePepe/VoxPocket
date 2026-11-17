import Foundation

public enum CaptureMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case text
    case todo
}

public enum FailureStage: String, Codable, Equatable, Hashable, Sendable {
    case recording
    case asr
    case ai
}

public enum CaptureSessionState: Codable, Equatable, Hashable, Sendable {
    case idle
    case recording(mode: CaptureMode)
    case transcribing
    case refining(mode: CaptureMode)
    case completed
    case failed(stage: FailureStage, reason: String)
}

public enum DeviceSource: String, Codable, Equatable, Hashable, Sendable {
    case iPhone
    case mac
    case iPad
    case appleWatch
}

public struct VoiceCapture: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let mode: CaptureMode
    public let rawTranscript: String
    public let refinedText: String
    public let localAudioFileName: String?
    public let durationSeconds: TimeInterval
    public let deviceSource: DeviceSource
    public let state: CaptureSessionState
    public let linkedTodoID: UUID?
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID = UUID(), mode: CaptureMode = .text, rawTranscript: String = "", refinedText: String = "", localAudioFileName: String? = nil, durationSeconds: TimeInterval = 0, deviceSource: DeviceSource = .mac, state: CaptureSessionState = .idle, linkedTodoID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.mode = mode; self.rawTranscript = rawTranscript; self.refinedText = refinedText
        self.localAudioFileName = localAudioFileName; self.durationSeconds = durationSeconds; self.deviceSource = deviceSource
        self.state = state; self.linkedTodoID = linkedTodoID; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public func withState(_ state: CaptureSessionState, updatedAt: Date = Date()) -> VoiceCapture {
        VoiceCapture(id: id, mode: mode, rawTranscript: rawTranscript, refinedText: refinedText, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, state: state, linkedTodoID: linkedTodoID, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func withTranscript(raw: String, refined: String, state: CaptureSessionState, updatedAt: Date = Date()) -> VoiceCapture {
        VoiceCapture(id: id, mode: mode, rawTranscript: raw, refinedText: refined, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, state: state, linkedTodoID: linkedTodoID, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func withLinkedTodo(_ todoID: UUID?, updatedAt: Date = Date()) -> VoiceCapture {
        VoiceCapture(id: id, mode: mode, rawTranscript: rawTranscript, refinedText: refinedText, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, state: state, linkedTodoID: todoID, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func sanitizedForCloudSync() -> VoiceCapture {
        VoiceCapture(id: id, mode: mode, rawTranscript: "", refinedText: "", localAudioFileName: nil, durationSeconds: durationSeconds, deviceSource: deviceSource, state: state, linkedTodoID: linkedTodoID, createdAt: createdAt, updatedAt: updatedAt)
    }
}

public enum TodoExecutionState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case inbox
    case running
    case done
    case failed
}

public enum TodoPriority: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
}

public struct VoiceTodoSubtask: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let isCompleted: Bool
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    public func withCompleted(_ isCompleted: Bool) -> VoiceTodoSubtask {
        VoiceTodoSubtask(id: id, title: title, isCompleted: isCompleted, createdAt: createdAt)
    }

    public func withTitle(_ title: String) -> VoiceTodoSubtask {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return VoiceTodoSubtask(id: id, title: trimmed, isCompleted: isCompleted, createdAt: createdAt)
    }

    public func sanitizedForCloudSync() -> VoiceTodoSubtask {
        VoiceTodoSubtask(id: id, title: "", isCompleted: isCompleted, createdAt: createdAt)
    }
}

public enum ExternalTodoSyncState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case localOnly
    case pendingPush
    case synced
    case failed
}

public struct ExternalTodoSyncMetadata: Codable, Equatable, Hashable, Sendable {
    public let provider: String
    public let externalID: String?
    public let externalURL: String?
    public let teamKey: String
    public let projectName: String?
    public let syncState: ExternalTodoSyncState
    public let remoteUpdatedAt: String?
    public let lastError: String?

    public init(provider: String = "linear", externalID: String? = nil, externalURL: String? = nil, teamKey: String = "EXAMPLE", projectName: String? = nil, syncState: ExternalTodoSyncState = .localOnly, remoteUpdatedAt: String? = nil, lastError: String? = nil) {
        self.provider = provider; self.externalID = externalID; self.externalURL = externalURL; self.teamKey = teamKey
        self.projectName = projectName; self.syncState = syncState; self.remoteUpdatedAt = remoteUpdatedAt; self.lastError = lastError
    }

    public func withState(_ syncState: ExternalTodoSyncState, externalID: String?? = nil, externalURL: String?? = nil, teamKey: String? = nil, projectName: String?? = nil, remoteUpdatedAt: String?? = nil, lastError: String?? = nil) -> ExternalTodoSyncMetadata {
        ExternalTodoSyncMetadata(provider: provider, externalID: externalID ?? self.externalID, externalURL: externalURL ?? self.externalURL, teamKey: teamKey ?? self.teamKey, projectName: projectName ?? self.projectName, syncState: syncState, remoteUpdatedAt: remoteUpdatedAt ?? self.remoteUpdatedAt, lastError: lastError ?? self.lastError)
    }

    public func sanitizedForCloudSync() -> ExternalTodoSyncMetadata {
        ExternalTodoSyncMetadata(provider: provider, externalID: externalID, externalURL: nil, teamKey: teamKey, projectName: nil, syncState: syncState, remoteUpdatedAt: remoteUpdatedAt, lastError: nil)
    }
}

public enum AIRunnerKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case herdr
    case claudeCode
    case codex
    case customShell
}

public struct AIRunnerTemplate: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let kind: AIRunnerKind
    public let name: String
    public let commandTemplate: String
    public let isBuiltIn: Bool

    public init(id: UUID = UUID(), kind: AIRunnerKind, name: String, commandTemplate: String, isBuiltIn: Bool = false) {
        precondition(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition(!commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        self.id = id; self.kind = kind; self.name = name; self.commandTemplate = commandTemplate; self.isBuiltIn = isBuiltIn
    }

    public static let herdrDefault = AIRunnerTemplate(kind: .herdr, name: "Herdr", commandTemplate: "herdr run --cwd {{cwd}} --title {{title}} --prompt {{prompt}} --task-file {{task_file}}", isBuiltIn: true)
    public static let claudeCodeDefault = AIRunnerTemplate(kind: .claudeCode, name: "Claude Code", commandTemplate: "claude --cwd {{cwd}} --print {{prompt}}", isBuiltIn: true)
    public static let codexDefault = AIRunnerTemplate(kind: .codex, name: "Codex", commandTemplate: "codex exec --cd {{cwd}} {{prompt}}", isBuiltIn: true)
    public static let customShellDefault = AIRunnerTemplate(kind: .customShell, name: "Custom shell", commandTemplate: "{{prompt}}", isBuiltIn: true)
    public static let defaultPresets = [herdrDefault, claudeCodeDefault, codexDefault, customShellDefault]

    public static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public func interpolate(cwd: String, title: String, prompt: String, taskFile: String) -> String {
        precondition(!cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        precondition(!commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return commandTemplate.replacingOccurrences(of: "{{cwd}}", with: Self.shellEscape(cwd))
            .replacingOccurrences(of: "{{title}}", with: Self.shellEscape(title))
            .replacingOccurrences(of: "{{prompt}}", with: Self.shellEscape(prompt))
            .replacingOccurrences(of: "{{task_file}}", with: Self.shellEscape(taskFile))
    }

    public func executableAndArguments(cwd: String, taskFile: String) -> (executable: String, arguments: [String]) {
        switch kind {
        case .herdr: return ("herdr", ["run", "--cwd", cwd, "--task-file", taskFile])
        case .claudeCode: return ("claude", ["--cwd", cwd, "--task-file", taskFile])
        case .codex: return ("codex", ["exec", "--cd", cwd, "--task-file", taskFile])
        case .customShell:
            let values = ["{{cwd}}": cwd, "{{task_file}}": taskFile]
            let tokens = commandTemplate.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let executable = tokens.first ?? ""
            let args = tokens.dropFirst().compactMap { token -> String? in
                if token == "{{title}}" || token == "{{prompt}}" { return nil }
                return values[token] ?? token
            }
            return (executable, args)
        }
    }
}

public struct ProjectBinding: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let projectKey: String
    public let displayName: String
    public let matchKeywords: [String]
    public let localDirectoryPath: String
    public let defaultRunnerKind: AIRunnerKind

    public init(id: UUID = UUID(), projectKey: String, displayName: String, matchKeywords: [String] = [], localDirectoryPath: String, defaultRunnerKind: AIRunnerKind = .herdr) {
        self.id = id; self.projectKey = projectKey; self.displayName = displayName; self.matchKeywords = matchKeywords; self.localDirectoryPath = localDirectoryPath; self.defaultRunnerKind = defaultRunnerKind
    }

    public func matches(spokenText: String) -> Bool {
        let text = spokenText.localizedLowercase
        return ([projectKey, displayName] + matchKeywords).contains { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) }
    }

    public static func matchProjectKey(in text: String, bindings: [ProjectBinding]) -> String? {
        bindings.first(where: { $0.matches(spokenText: text) })?.projectKey
    }
}

public struct VoiceTodo: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID; public let title: String; public let description: String; public let taskPrompt: String; public let rawTranscript: String
    public let projectKey: String?; public let assignedRunnerKind: AIRunnerKind?; public let executionState: TodoExecutionState
    public let priority: TodoPriority; public let tags: [String]; public let subtasks: [VoiceTodoSubtask]
    public let scheduledAt: Date?; public let timeSlot: String?
    public let lastExecutionSummary: String?; public let lastStartedAt: Date?; public let lastCompletedAt: Date?
    public let sourceCaptureID: UUID?; public let localAudioFileName: String?; public let durationSeconds: TimeInterval
    public let deviceSource: DeviceSource; public let externalSync: ExternalTodoSyncMetadata?; public let createdAt: Date; public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, description, taskPrompt, rawTranscript, projectKey, assignedRunnerKind, executionState
        case priority, tags, subtasks
        case scheduledAt, timeSlot
        case lastExecutionSummary, lastStartedAt, lastCompletedAt, sourceCaptureID, localAudioFileName
        case durationSeconds, deviceSource, externalSync, createdAt, updatedAt
    }

    public static func normalizeTags(_ tags: [String]) -> [String] {
        var result: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let formatted = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
            if !result.contains(formatted) {
                result.append(formatted)
            }
            if result.count >= 3 { break }
        }
        return result
    }

    public init(id: UUID = UUID(), title: String, description: String = "", taskPrompt: String = "", rawTranscript: String = "", projectKey: String? = nil, assignedRunnerKind: AIRunnerKind? = nil, executionState: TodoExecutionState = .inbox, priority: TodoPriority = .p1, tags: [String] = [], subtasks: [VoiceTodoSubtask] = [], scheduledAt: Date? = nil, timeSlot: String? = nil, lastExecutionSummary: String? = nil, lastStartedAt: Date? = nil, lastCompletedAt: Date? = nil, sourceCaptureID: UUID? = nil, localAudioFileName: String? = nil, durationSeconds: TimeInterval = 0, deviceSource: DeviceSource = .mac, externalSync: ExternalTodoSyncMetadata? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.description = description; self.taskPrompt = taskPrompt; self.rawTranscript = rawTranscript; self.projectKey = projectKey; self.assignedRunnerKind = assignedRunnerKind; self.executionState = executionState; self.priority = priority; self.tags = Self.normalizeTags(tags); self.subtasks = subtasks; self.scheduledAt = scheduledAt; self.timeSlot = timeSlot; self.lastExecutionSummary = lastExecutionSummary; self.lastStartedAt = lastStartedAt; self.lastCompletedAt = lastCompletedAt; self.sourceCaptureID = sourceCaptureID; self.localAudioFileName = localAudioFileName; self.durationSeconds = durationSeconds; self.deviceSource = deviceSource; self.externalSync = externalSync; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        taskPrompt = try container.decode(String.self, forKey: .taskPrompt)
        rawTranscript = try container.decode(String.self, forKey: .rawTranscript)
        projectKey = try container.decodeIfPresent(String.self, forKey: .projectKey)
        assignedRunnerKind = try container.decodeIfPresent(AIRunnerKind.self, forKey: .assignedRunnerKind)
        executionState = try container.decode(TodoExecutionState.self, forKey: .executionState)
        priority = try container.decodeIfPresent(TodoPriority.self, forKey: .priority) ?? .p1
        tags = Self.normalizeTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        subtasks = try container.decodeIfPresent([VoiceTodoSubtask].self, forKey: .subtasks) ?? []
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
        timeSlot = try container.decodeIfPresent(String.self, forKey: .timeSlot)
        lastExecutionSummary = try container.decodeIfPresent(String.self, forKey: .lastExecutionSummary)
        lastStartedAt = try container.decodeIfPresent(Date.self, forKey: .lastStartedAt)
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
        sourceCaptureID = try container.decodeIfPresent(UUID.self, forKey: .sourceCaptureID)
        localAudioFileName = try container.decodeIfPresent(String.self, forKey: .localAudioFileName)
        durationSeconds = try container.decode(TimeInterval.self, forKey: .durationSeconds)
        deviceSource = try container.decode(DeviceSource.self, forKey: .deviceSource)
        externalSync = try container.decodeIfPresent(ExternalTodoSyncMetadata.self, forKey: .externalSync)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func withEdits(title: String? = nil, description: String? = nil, taskPrompt: String? = nil, projectKey: String?? = nil, assignedRunnerKind: AIRunnerKind?? = nil, priority: TodoPriority? = nil, tags: [String]? = nil, subtasks: [VoiceTodoSubtask]? = nil, scheduledAt: Date?? = nil, timeSlot: String?? = nil, updatedAt: Date = Date()) -> VoiceTodo {
        VoiceTodo(id: id, title: title ?? self.title, description: description ?? self.description, taskPrompt: taskPrompt ?? self.taskPrompt, rawTranscript: rawTranscript, projectKey: projectKey ?? self.projectKey, assignedRunnerKind: assignedRunnerKind ?? self.assignedRunnerKind, executionState: executionState, priority: priority ?? self.priority, tags: tags ?? self.tags, subtasks: subtasks ?? self.subtasks, scheduledAt: scheduledAt ?? self.scheduledAt, timeSlot: timeSlot ?? self.timeSlot, lastExecutionSummary: lastExecutionSummary, lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, externalSync: externalSync, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func withReminder(scheduledAt: Date?, timeSlot: String?, updatedAt: Date = Date()) -> VoiceTodo {
        withEdits(scheduledAt: .some(scheduledAt), timeSlot: .some(timeSlot), updatedAt: updatedAt)
    }

    public func withReminderSchedule(scheduledAt: Date?, timeSlot: String?, updatedAt: Date = Date()) -> VoiceTodo {
        withReminder(scheduledAt: scheduledAt, timeSlot: timeSlot, updatedAt: updatedAt)
    }

    public func withExecutionState(_ state: TodoExecutionState, summary: String? = nil, runnerKind: AIRunnerKind?? = nil, startedAt: Date? = nil, completedAt: Date? = nil, updatedAt: Date = Date()) -> VoiceTodo {
        VoiceTodo(id: id, title: title, description: description, taskPrompt: taskPrompt, rawTranscript: rawTranscript, projectKey: projectKey, assignedRunnerKind: runnerKind ?? assignedRunnerKind, executionState: state, priority: priority, tags: tags, subtasks: subtasks, scheduledAt: scheduledAt, timeSlot: timeSlot, lastExecutionSummary: summary, lastStartedAt: startedAt, lastCompletedAt: completedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, externalSync: externalSync, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func withExternalSync(_ externalSync: ExternalTodoSyncMetadata?, updatedAt: Date = Date()) -> VoiceTodo {
        VoiceTodo(id: id, title: title, description: description, taskPrompt: taskPrompt, rawTranscript: rawTranscript, projectKey: projectKey, assignedRunnerKind: assignedRunnerKind, executionState: executionState, priority: priority, tags: tags, subtasks: subtasks, scheduledAt: scheduledAt, timeSlot: timeSlot, lastExecutionSummary: lastExecutionSummary, lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, externalSync: externalSync, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func withPriority(_ priority: TodoPriority, updatedAt: Date = Date()) -> VoiceTodo {
        withEdits(priority: priority, updatedAt: updatedAt)
    }

    public func withTitle(_ title: String, updatedAt: Date = Date()) -> VoiceTodo {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return withEdits(title: trimmed, updatedAt: updatedAt)
    }

    public func withDescription(_ description: String, updatedAt: Date = Date()) -> VoiceTodo {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return withEdits(description: trimmed, updatedAt: updatedAt)
    }

    public func withTags(_ tags: [String], updatedAt: Date = Date()) -> VoiceTodo {
        withEdits(tags: Self.normalizeTags(tags), updatedAt: updatedAt)
    }

    public func withAddedTag(_ rawTag: String, updatedAt: Date = Date()) -> VoiceTodo {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        let formatted = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        guard !tags.contains(formatted), tags.count < 3 else { return self }
        return withTags(tags + [formatted], updatedAt: updatedAt)
    }

    public func withRemovedTag(_ rawTag: String, updatedAt: Date = Date()) -> VoiceTodo {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        let formatted = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        guard tags.contains(formatted) else { return self }
        return withTags(tags.filter { $0 != formatted }, updatedAt: updatedAt)
    }

    public func withToggledTag(_ rawTag: String, updatedAt: Date = Date()) -> VoiceTodo {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        let formatted = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        if tags.contains(formatted) {
            return withRemovedTag(formatted, updatedAt: updatedAt)
        }
        return withAddedTag(formatted, updatedAt: updatedAt)
    }

    public func withAppendedSubtask(_ subtaskTitle: String, createdAt: Date = Date(), updatedAt: Date = Date()) -> VoiceTodo {
        let trimmed = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        let appended = subtasks + [VoiceTodoSubtask(title: trimmed, isCompleted: false, createdAt: createdAt)]
        let updatedPrompt = taskPrompt.isEmpty ? "- [ ] \(trimmed)" : "\(taskPrompt)\n- [ ] \(trimmed)"
        return VoiceTodo(id: id, title: title, description: description, taskPrompt: updatedPrompt, rawTranscript: rawTranscript, projectKey: projectKey, assignedRunnerKind: assignedRunnerKind, executionState: executionState, priority: priority, tags: tags, subtasks: appended, scheduledAt: scheduledAt, timeSlot: timeSlot, lastExecutionSummary: lastExecutionSummary, lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, externalSync: externalSync, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func withToggledSubtask(_ subtaskID: UUID, updatedAt: Date = Date()) -> VoiceTodo {
        let updatedSubtasks = subtasks.map { item in
            item.id == subtaskID ? item.withCompleted(!item.isCompleted) : item
        }
        return withEdits(subtasks: updatedSubtasks, updatedAt: updatedAt)
    }

    public func withUpdatedSubtaskTitle(_ subtaskID: UUID, title: String, updatedAt: Date = Date()) -> VoiceTodo {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, subtasks.contains(where: { $0.id == subtaskID }) else { return self }
        let updatedSubtasks = subtasks.map { item in
            item.id == subtaskID ? item.withTitle(trimmed) : item
        }
        return withEdits(subtasks: updatedSubtasks, updatedAt: updatedAt)
    }

    public func sanitizedForCloudSync() -> VoiceTodo {
        VoiceTodo(id: id, title: "", description: "", taskPrompt: "", rawTranscript: "", projectKey: projectKey, assignedRunnerKind: assignedRunnerKind, executionState: executionState, priority: priority, tags: [], subtasks: subtasks.map { $0.sanitizedForCloudSync() }, scheduledAt: scheduledAt, timeSlot: timeSlot, lastExecutionSummary: nil, lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: nil, durationSeconds: durationSeconds, deviceSource: deviceSource, externalSync: externalSync?.sanitizedForCloudSync(), createdAt: createdAt, updatedAt: updatedAt)
    }
}

// MARK: - iCloud AI Execution Order & Live Status Reporting (`✨ AI do it` Cross-Device Engine)

public enum AIOrderExecutionState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case queued
    case claimedByMac
    case running
    case completed
    case failed

    public var isTerminal: Bool {
        self == .completed || self == .failed
    }

    public var localizedBadgeLabel: String {
        switch self {
        case .queued: "☁️ 已上传 iCloud · 等待 Mac 接单"
        case .claimedByMac: "⚡ Mac 已接单 · 准备启动 AI"
        case .running: "⚡ Mac 已接单 · AI 执行中"
        case .completed: "✅ AI 已完成"
        case .failed: "⚠️ AI 执行失败 · 点击重试"
        }
    }
}

public struct AIExecutionStatusReport: Codable, Equatable, Hashable, Sendable {
    public let orderID: UUID
    public let todoID: UUID
    public let state: AIOrderExecutionState
    public let progressStage: String
    public let progressFraction: Double
    public let outputSummary: String?
    public let assignedRunnerName: String?
    public let updatedAt: Date

    public init(
        orderID: UUID,
        todoID: UUID,
        state: AIOrderExecutionState,
        progressStage: String,
        progressFraction: Double = 0.0,
        outputSummary: String? = nil,
        assignedRunnerName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.orderID = orderID
        self.todoID = todoID
        self.state = state
        self.progressStage = progressStage
        self.progressFraction = min(1.0, max(0.0, progressFraction))
        self.outputSummary = outputSummary
        self.assignedRunnerName = assignedRunnerName
        self.updatedAt = updatedAt
    }
}

public struct ICloudAIExecutionOrder: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID { orderID }
    public let orderID: UUID
    public let todoID: UUID
    public let title: String
    public let description: String
    public let subtasks: [String]
    public let tags: [String]
    public let priority: String
    public let projectKey: String?
    public let state: AIOrderExecutionState
    public let progressStage: String
    public let progressFraction: Double
    public let outputSummary: String?
    public let assignedRunnerName: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        orderID: UUID = UUID(),
        todoID: UUID,
        title: String,
        description: String = "",
        subtasks: [String] = [],
        tags: [String] = [],
        priority: String = "P1",
        projectKey: String? = nil,
        state: AIOrderExecutionState = .queued,
        progressStage: String = "已上传 iCloud · 等待 Mac 接单",
        progressFraction: Double = 0.05,
        outputSummary: String? = nil,
        assignedRunnerName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.orderID = orderID
        self.todoID = todoID
        self.title = title
        self.description = description
        self.subtasks = subtasks
        self.tags = tags
        self.priority = priority
        self.projectKey = projectKey
        self.state = state
        self.progressStage = progressStage
        self.progressFraction = min(1.0, max(0.0, progressFraction))
        self.outputSummary = outputSummary
        self.assignedRunnerName = assignedRunnerName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from todo: VoiceTodo, orderID: UUID = UUID(), now: Date = Date()) {
        self.init(
            orderID: orderID,
            todoID: todo.id,
            title: todo.title,
            description: todo.description.isEmpty ? todo.taskPrompt : todo.description,
            subtasks: todo.subtasks.map(\.title),
            tags: todo.tags,
            priority: todo.priority.rawValue,
            projectKey: todo.projectKey,
            state: .queued,
            progressStage: "已上传 iCloud · 等待 Mac 接单",
            progressFraction: 0.08,
            outputSummary: nil,
            assignedRunnerName: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    public func applying(_ report: AIExecutionStatusReport) -> ICloudAIExecutionOrder {
        ICloudAIExecutionOrder(
            orderID: orderID,
            todoID: todoID,
            title: title,
            description: description,
            subtasks: subtasks,
            tags: tags,
            priority: priority,
            projectKey: projectKey,
            state: report.state,
            progressStage: report.progressStage,
            progressFraction: report.progressFraction,
            outputSummary: report.outputSummary ?? outputSummary,
            assignedRunnerName: report.assignedRunnerName ?? assignedRunnerName,
            createdAt: createdAt,
            updatedAt: report.updatedAt
        )
    }

    public func withState(
        _ state: AIOrderExecutionState,
        progressStage: String,
        progressFraction: Double,
        outputSummary: String? = nil,
        assignedRunnerName: String? = nil,
        updatedAt: Date = Date()
    ) -> ICloudAIExecutionOrder {
        ICloudAIExecutionOrder(
            orderID: orderID,
            todoID: todoID,
            title: title,
            description: description,
            subtasks: subtasks,
            tags: tags,
            priority: priority,
            projectKey: projectKey,
            state: state,
            progressStage: progressStage,
            progressFraction: progressFraction,
            outputSummary: outputSummary ?? self.outputSummary,
            assignedRunnerName: assignedRunnerName ?? self.assignedRunnerName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public var formattedButtonLabel: String {
        switch state {
        case .queued:
            return "☁️ 已上传 iCloud · 等待 Mac 接单"
        case .claimedByMac:
            return "⚡ Mac 已接单 · \(progressStage)"
        case .running:
            return "⚡ Mac 已接单 · AI 执行中: \(progressStage)"
        case .completed:
            let summary = (outputSummary ?? progressStage).trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? "✅ AI 已完成" : "✅ AI 已完成 · \(summary)"
        case .failed:
            let reason = (outputSummary ?? progressStage).trimmingCharacters(in: .whitespacesAndNewlines)
            return reason.isEmpty ? "⚠️ AI 执行失败 · 点击重试" : "⚠️ AI 执行失败 · \(reason)"
        }
    }
}

public struct UserAIRunnerConfig: Codable, Equatable, Hashable, Sendable {
    public var isAutoPickupEnabled: Bool
    public var runnerDisplayName: String
    public var scriptPathOrCommand: String
    public var defaultWorkingDirectory: String
    public var pollIntervalSeconds: Double

    public init(
        isAutoPickupEnabled: Bool = true,
        runnerDisplayName: String = "Mac AI Agent",
        scriptPathOrCommand: String = "herdr run --cwd {{cwd}} --title {{title}} --order-file {{order_file}} --status-file {{status_file}}",
        defaultWorkingDirectory: String = ".",
        pollIntervalSeconds: Double = 2.0
    ) {
        self.isAutoPickupEnabled = isAutoPickupEnabled
        self.runnerDisplayName = runnerDisplayName
        self.scriptPathOrCommand = scriptPathOrCommand
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.pollIntervalSeconds = max(0.2, pollIntervalSeconds)
    }

    public func interpolateCommand(
        order: ICloudAIExecutionOrder,
        orderFilePath: String,
        statusFilePath: String
    ) -> String {
        let subtasksJSON: String = {
            guard let data = try? JSONEncoder().encode(order.subtasks),
                  let str = String(data: data, encoding: .utf8) else {
                return "[]"
            }
            return str
        }()
        let resolvedCwd = defaultWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "."
            : defaultWorkingDirectory

        return scriptPathOrCommand
            .replacingOccurrences(of: "{{order_file}}", with: AIRunnerTemplate.shellEscape(orderFilePath))
            .replacingOccurrences(of: "{{status_file}}", with: AIRunnerTemplate.shellEscape(statusFilePath))
            .replacingOccurrences(of: "{{title}}", with: AIRunnerTemplate.shellEscape(order.title))
            .replacingOccurrences(of: "{{description}}", with: AIRunnerTemplate.shellEscape(order.description))
            .replacingOccurrences(of: "{{subtasks_json}}", with: AIRunnerTemplate.shellEscape(subtasksJSON))
            .replacingOccurrences(of: "{{cwd}}", with: AIRunnerTemplate.shellEscape(resolvedCwd))
    }
}

