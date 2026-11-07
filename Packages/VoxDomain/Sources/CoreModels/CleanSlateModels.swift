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
    public let id: UUID; public let title: String; public let taskPrompt: String; public let rawTranscript: String
    public let projectKey: String?; public let assignedRunnerKind: AIRunnerKind?; public let executionState: TodoExecutionState
    public let lastExecutionSummary: String?; public let lastStartedAt: Date?; public let lastCompletedAt: Date?
    public let sourceCaptureID: UUID?; public let localAudioFileName: String?; public let durationSeconds: TimeInterval
    public let deviceSource: DeviceSource; public let createdAt: Date; public let updatedAt: Date

    public init(id: UUID = UUID(), title: String, taskPrompt: String = "", rawTranscript: String = "", projectKey: String? = nil, assignedRunnerKind: AIRunnerKind? = nil, executionState: TodoExecutionState = .inbox, lastExecutionSummary: String? = nil, lastStartedAt: Date? = nil, lastCompletedAt: Date? = nil, sourceCaptureID: UUID? = nil, localAudioFileName: String? = nil, durationSeconds: TimeInterval = 0, deviceSource: DeviceSource = .mac, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.taskPrompt = taskPrompt; self.rawTranscript = rawTranscript; self.projectKey = projectKey; self.assignedRunnerKind = assignedRunnerKind; self.executionState = executionState; self.lastExecutionSummary = lastExecutionSummary; self.lastStartedAt = lastStartedAt; self.lastCompletedAt = lastCompletedAt; self.sourceCaptureID = sourceCaptureID; self.localAudioFileName = localAudioFileName; self.durationSeconds = durationSeconds; self.deviceSource = deviceSource; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public func withEdits(title: String? = nil, taskPrompt: String? = nil, projectKey: String?? = nil, assignedRunnerKind: AIRunnerKind?? = nil, updatedAt: Date = Date()) -> VoiceTodo {
        VoiceTodo(id: id, title: title ?? self.title, taskPrompt: taskPrompt ?? self.taskPrompt, rawTranscript: rawTranscript, projectKey: projectKey ?? self.projectKey, assignedRunnerKind: assignedRunnerKind ?? self.assignedRunnerKind, executionState: executionState, lastExecutionSummary: lastExecutionSummary, lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func withExecutionState(_ state: TodoExecutionState, summary: String? = nil, runnerKind: AIRunnerKind?? = nil, startedAt: Date? = nil, completedAt: Date? = nil, updatedAt: Date = Date()) -> VoiceTodo {
        VoiceTodo(id: id, title: title, taskPrompt: taskPrompt, rawTranscript: rawTranscript, projectKey: projectKey, assignedRunnerKind: runnerKind ?? assignedRunnerKind, executionState: state, lastExecutionSummary: summary, lastStartedAt: startedAt, lastCompletedAt: completedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, createdAt: createdAt, updatedAt: updatedAt)
    }

    public func sanitizedForCloudSync() -> VoiceTodo {
        VoiceTodo(id: id, title: "", taskPrompt: "", rawTranscript: "", projectKey: projectKey, assignedRunnerKind: assignedRunnerKind, executionState: executionState, lastExecutionSummary: nil, lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt, sourceCaptureID: sourceCaptureID, localAudioFileName: nil, durationSeconds: durationSeconds, deviceSource: deviceSource, createdAt: createdAt, updatedAt: updatedAt)
    }
}
