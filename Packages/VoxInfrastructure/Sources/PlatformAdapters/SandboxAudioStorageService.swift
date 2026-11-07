import Foundation

public protocol SandboxAudioStorageService: AnyObject, Sendable {
    func store(data: Data, fileName: String) async throws -> String
    func resolve(fileName: String) async -> URL?
    func remove(fileName: String) async throws
    func cleanRetainedFiles() async throws
}

public final class DefaultSandboxAudioStorageService: SandboxAudioStorageService, Sendable {
    private let directory: URL
    private let retentionLimit: Int

    public init(directory: URL? = nil, retentionLimit: Int = 100) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VoxPocket/AudioCaptures", isDirectory: true)
        self.retentionLimit = max(0, retentionLimit)
    }

    public func store(data: Data, fileName: String) async throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        let url = directory.appendingPathComponent(safeName)
        try data.write(to: url, options: .atomic)
        try excludeFromBackup(url)
        try await cleanRetainedFiles()
        return safeName
    }

    public func resolve(fileName: String) async -> URL? {
        let url = directory.appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func remove(fileName: String) async throws { try FileManager.default.removeItem(at: directory.appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent)) }

    public func cleanRetainedFiles() async throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast < (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast }
        if files.count > retentionLimit { for file in files.prefix(files.count - retentionLimit) { try FileManager.default.removeItem(at: file) } }
    }

    private func excludeFromBackup(_ url: URL) throws { var url = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values) }
}
