import Foundation
import CoreModels

public protocol VoiceTodoExtractionRunning: Sendable {
    func extractTodo(from rawTranscript: String, refinedText: String, availableProjects: [ProjectBinding]) async throws -> ExtractedTodoDraft
}

public struct ExtractedTodoDraft: Equatable, Sendable {
    public let title: String
    public let taskPrompt: String
    public let matchedProjectKey: String?

    public init(title: String, taskPrompt: String, matchedProjectKey: String?) {
        self.title = title
        self.taskPrompt = taskPrompt
        self.matchedProjectKey = matchedProjectKey
    }
}

public protocol VoiceCaptureAndTodoUseCase: AnyObject, Sendable {
    func recordCompletedCapture(mode: CaptureMode, rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> (capture: VoiceCapture, todo: VoiceTodo?)
    func recordFailedCapture(mode: CaptureMode, stage: FailureStage, reason: String, rawTranscript: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> VoiceCapture
    func retryCapture(id: UUID, targetMode: CaptureMode?) async throws -> (capture: VoiceCapture, todo: VoiceTodo?)
    func convertCaptureToTodo(captureID: UUID) async throws -> VoiceTodo
    func updateTodo(_ todo: VoiceTodo) async throws -> VoiceTodo
    func runTodoWithAI(todoID: UUID, project: ProjectBinding, template: AIRunnerTemplate) async throws -> VoiceTodo
    func markTodoDone(todoID: UUID) async throws -> VoiceTodo
    func syncTodoToExternal(todoID: UUID) async throws -> VoiceTodo
    func refreshExternalTodos() async throws -> [VoiceTodo]
    func deleteCapture(id: UUID) async throws
    func deleteTodo(id: UUID) async throws
    func fetchCaptures() async throws -> [VoiceCapture]
    func fetchTodos() async throws -> [VoiceTodo]
}

public extension VoiceCaptureAndTodoUseCase {
    func syncTodoToExternal(todoID: UUID) async throws -> VoiceTodo {
        guard let existing = try await fetchTodos().first(where: { $0.id == todoID }) else {
            throw NSError(domain: "VoiceTodoUseCase", code: 404)
        }
        return existing
    }

    func refreshExternalTodos() async throws -> [VoiceTodo] {
        try await fetchTodos()
    }
}
