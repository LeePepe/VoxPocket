import Foundation
import VoxCore
import VoxSpeech

public actor WorkflowAudioCapture {
    package nonisolated let suppliedSession: (any SpeechSession)?
    private let configuration: WorkflowExecutionConfiguration
    private let language: Locale
    private var sessions: [NodeKindID: Task<any SpeechSession, Error>] = [:]

    package init(configuration: WorkflowExecutionConfiguration, language: Locale, suppliedSession: (any SpeechSession)?) {
        self.configuration = configuration
        self.language = language
        self.suppliedSession = suppliedSession
    }

    package func prepare(_ kinds: [NodeKindID]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for kind in Set(kinds) where kind != .speechWhisperKitLocal || configuration.speechFactories[kind] != nil {
                group.addTask {
                    do { _ = try await self.session(for: kind) }
                    catch { if Task.isCancelled || error is CancellationError { throw CancellationError() } }
                }
            }
            try await group.waitForAll()
        }
        try Task.checkCancellation()
    }

    package func session(for kind: NodeKindID) async throws -> any SpeechSession {
        try Task.checkCancellation()
        if let suppliedSession { return suppliedSession }
        let task: Task<any SpeechSession, Error>
        if let existing = sessions[kind] { task = existing }
        else {
            task = Task { [configuration, language] in
                let source = try await configuration.speechSource(for: kind)
                return try await source.startSession(language: language)
            }
            sessions[kind] = task
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    package func finish(cancelled: Bool) async {
        if let suppliedSession {
            if cancelled { await suppliedSession.cancel() } else { await suppliedSession.stop() }
        }
        let tasks = Array(sessions.values)
        if cancelled { tasks.forEach { $0.cancel() } }
        for task in tasks {
            if case .success(let session) = await task.result {
                if cancelled { await session.cancel() } else { await session.stop() }
            }
        }
    }
}
