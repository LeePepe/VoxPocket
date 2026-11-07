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
    public typealias ProcessRunner = @Sendable (_ executable: String, _ arguments: [String], _ cwd: String) throws -> (Int32, String)
    private let processRunner: ProcessRunner?
    private let sandboxTasksDirectory: URL

    public init(processRunner: ProcessRunner? = nil, sandboxTasksDirectory: URL? = nil) {
        self.processRunner = processRunner
        self.sandboxTasksDirectory = sandboxTasksDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VoxPocket/Tasks", isDirectory: true)
    }

    public func execute(todo: VoiceTodo, project: ProjectBinding, template: AIRunnerTemplate) async throws -> AIRunnerExecutionResult {
        let startedAt = Date()
        let cwd = project.localDirectoryPath.isEmpty ? Self.fallbackDirectory() : project.localDirectoryPath
        try FileManager.default.createDirectory(at: sandboxTasksDirectory, withIntermediateDirectories: true)
        var taskFile = sandboxTasksDirectory.appendingPathComponent("\(todo.id.uuidString).md")
        let taskBody = "# Task\n\n\(todo.title)\n\n\(todo.taskPrompt)\n"
        try taskBody.data(using: .utf8)?.write(to: taskFile, options: .atomic)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try taskFile.setResourceValues(resourceValues)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: taskFile.path)
        let command = template.executableAndArguments(cwd: cwd, title: todo.title, prompt: todo.taskPrompt, taskFile: taskFile.path)
        let (exitCode, output) = try await Task.detached(priority: nil) { [processRunner] in
            if let processRunner { return try processRunner(command.executable, command.arguments, cwd) }
#if os(macOS)
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: outputData, as: UTF8.self))
#else
            return (Int32(-1), "Runner execution is supported on macOS only")
#endif
        }.value
        return AIRunnerExecutionResult(exitCode: exitCode, outputSummary: String(output.prefix(4096)), taskFilePath: taskFile.path, startedAt: startedAt, completedAt: Date())
    }

    private static func fallbackDirectory() -> String { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("VoxPocket").path ?? NSTemporaryDirectory() }
}
