import Foundation
import CoreModels

public struct AIRunnerExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let outputSummary: String
    public let taskFilePath: String
    public let startedAt: Date
    public let completedAt: Date
    public init(exitCode: Int32, outputSummary: String, taskFilePath: String, startedAt: Date, completedAt: Date) {
        self.exitCode = exitCode; self.outputSummary = outputSummary; self.taskFilePath = taskFilePath; self.startedAt = startedAt; self.completedAt = completedAt
    }
}

public protocol AIRunnerExecutionService: AnyObject, Sendable {
    func execute(todo: VoiceTodo, project: ProjectBinding, template: AIRunnerTemplate) async throws -> AIRunnerExecutionResult
}

public final class DefaultAIRunnerExecutionService: AIRunnerExecutionService, Sendable {
    public typealias ProcessRunner = @Sendable (_ command: String, _ cwd: String) throws -> (Int32, String)
    private let processRunner: ProcessRunner?

    public init(processRunner: ProcessRunner? = nil) { self.processRunner = processRunner }

    public func execute(todo: VoiceTodo, project: ProjectBinding, template: AIRunnerTemplate) async throws -> AIRunnerExecutionResult {
        let startedAt = Date()
        let cwd = project.localDirectoryPath.isEmpty ? Self.fallbackDirectory() : project.localDirectoryPath
        let taskDirectory = URL(fileURLWithPath: cwd).appendingPathComponent(".voxpocket/tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
        let taskFile = taskDirectory.appendingPathComponent("\(todo.id.uuidString).md")
        let taskBody = "# Task\n\n\(todo.title)\n\n\(todo.taskPrompt)\n"
        try taskBody.data(using: .utf8)?.write(to: taskFile, options: .atomic)
        let command = template.interpolate(cwd: cwd, title: todo.title, prompt: todo.taskPrompt, taskFile: taskFile.path)
        let (exitCode, output) = try await Task.detached(priority: nil) { [processRunner] in
            if let processRunner { return try processRunner(command, cwd) }
#if os(macOS)
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]; process.currentDirectoryURL = URL(fileURLWithPath: cwd); process.standardOutput = pipe; process.standardError = pipe
            try process.run(); process.waitUntilExit()
            return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
#else
            return (Int32(-1), "Runner execution is supported on macOS only")
#endif
        }.value
        return AIRunnerExecutionResult(exitCode: exitCode, outputSummary: String(output.prefix(4096)), taskFilePath: taskFile.path, startedAt: startedAt, completedAt: Date())
    }

    private static func fallbackDirectory() -> String { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("VoxPocket").path ?? NSTemporaryDirectory() }
}
