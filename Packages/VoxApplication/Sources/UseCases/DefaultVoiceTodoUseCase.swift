import Foundation
import CoreModels
import Persistence
import PlatformAdapters
import VoxKitBridge
import VoxRefine
import LokiKit

public struct DefaultVoiceTodoExtractor: VoiceTodoExtractionRunning {
    public init() {}

    public func extractTodo(from rawTranscript: String, refinedText: String, availableProjects: [ProjectBinding]) async throws -> ExtractedTodoDraft {
        let source = refinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawTranscript : refinedText
        let sentence = source.split(whereSeparator: { ".!?。！？\n".contains($0) }).first.map(String.init) ?? source
        let title = Self.compactTitle(sentence)
        let promptSource = source.isEmpty ? rawTranscript : source
        let prompt = "## Goal\n\(promptSource.trimmingCharacters(in: .whitespacesAndNewlines))\n\n## Context\nCreated from a voice capture."
        return ExtractedTodoDraft(title: title.isEmpty ? "Untitled task" : title, taskPrompt: prompt, matchedProjectKey: ProjectBinding.matchProjectKey(in: source, bindings: availableProjects))
    }

    private static func compactTitle(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 60 else { return normalized }
        return String(normalized.prefix(57)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

public enum VoiceTodoUseCaseError: Error, LocalizedError, Sendable {
    case captureNotFound
    case todoNotFound
    case projectNotFound
    public var errorDescription: String? {
        switch self { case .captureNotFound: "Capture not found"; case .todoNotFound: "Todo not found"; case .projectNotFound: "Project not found" }
    }
}

public final class DefaultVoiceCaptureAndTodoUseCase: VoiceCaptureAndTodoUseCase, Sendable {
    private let captures: any VoiceCaptureRepository
    private let todos: any VoiceTodoRepository
    private let extractor: any VoiceTodoExtractionRunning
    private let runner: any AIRunnerExecutionService
    private let projects: @Sendable () -> [ProjectBinding]
    private let telemetry: any TelemetryService

    public init(captures: any VoiceCaptureRepository, todos: any VoiceTodoRepository, extractor: any VoiceTodoExtractionRunning = DefaultVoiceTodoExtractor(), runner: any AIRunnerExecutionService, projects: @escaping @Sendable () -> [ProjectBinding] = { [] }, telemetry: any TelemetryService = NoopTelemetryService()) {
        self.captures = captures; self.todos = todos; self.extractor = extractor; self.runner = runner; self.projects = projects; self.telemetry = telemetry
    }

    public func recordCompletedCapture(mode: CaptureMode, rawTranscript: String, refinedText: String, localAudioFileName: String?, durationSeconds: TimeInterval, deviceSource: DeviceSource) async throws -> (capture: VoiceCapture, todo: VoiceTodo?) {
        let capture = VoiceCapture(mode: mode, rawTranscript: rawTranscript, refinedText: refinedText, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource, state: .completed)
        try await captures.save(capture)
        let todo: VoiceTodo?
        if mode == .todo {
            let draft = try await extractor.extractTodo(from: rawTranscript, refinedText: refinedText, availableProjects: projects())
            todo = VoiceTodo(title: draft.title, taskPrompt: draft.taskPrompt, rawTranscript: rawTranscript, projectKey: draft.matchedProjectKey, sourceCaptureID: capture.id, localAudioFileName: localAudioFileName, durationSeconds: durationSeconds, deviceSource: deviceSource)
            try await todos.save(todo!)
            try await captures.save(capture.withLinkedTodo(todo!.id))
        } else { todo = nil }
        telemetry.track(name: "capture.completed", properties: ["duration_ms": String(Int(durationSeconds * 1000)), "mode": mode.rawValue, "source": deviceSource.rawValue])
        return (todo == nil ? capture : capture.withLinkedTodo(todo!.id), todo)
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
        let todo = VoiceTodo(title: draft.title, taskPrompt: draft.taskPrompt, rawTranscript: capture.rawTranscript, projectKey: draft.matchedProjectKey, sourceCaptureID: capture.id, localAudioFileName: capture.localAudioFileName, durationSeconds: capture.durationSeconds, deviceSource: capture.deviceSource)
        try await todos.save(todo); try await captures.save(capture.withLinkedTodo(todo.id)); return todo
    }

    public func updateTodo(_ todo: VoiceTodo) async throws -> VoiceTodo { try await todos.save(todo); return todo }

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

    public func markTodoDone(todoID: UUID) async throws -> VoiceTodo { guard let todo = try await todos.fetch(by: todoID) else { throw VoiceTodoUseCaseError.todoNotFound }; let done = todo.withExecutionState(.done, completedAt: Date()); try await todos.save(done); return done }
    public func deleteCapture(id: UUID) async throws { try await captures.delete(by: id) }
    public func deleteTodo(id: UUID) async throws { try await todos.delete(by: id) }
    public func fetchCaptures() async throws -> [VoiceCapture] { try await captures.fetchAll() }
    public func fetchTodos() async throws -> [VoiceTodo] { try await todos.fetchAll() }
}
