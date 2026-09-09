import Foundation
import Darwin

public protocol PrivateModelConfigurationLoading: Sendable {
    func load(environment: [String: String]) async throws -> ModelRuntimeConfiguration
}

/// 配置只从用户沙箱读取；所有文件 I/O 都在 detached task 中执行。
public struct DefaultPrivateModelConfigurationLoader: PrivateModelConfigurationLoading {
    private let fileURL: URL?
    private static let maximumBytes = 64 * 1024

    public init(fileURL: URL? = nil) { self.fileURL = fileURL }

    public func load(environment: [String: String]) async throws -> ModelRuntimeConfiguration {
        try await Task.detached(priority: .userInitiated) {
            let url = try fileURL ?? Self.defaultFileURL()
            guard let data = try Self.readProtectedFile(url) else {
                return ModelRuntimeConfiguration(environmentValues: environment, loadedPrivateFile: false)
            }
            let defaults = try PrivateModelConfiguration.decode(data).environmentDefaults()
            var values = defaults.merging(environment.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { _, override in override }
            if environment["kimikey"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
               let legacy = environment["VOX_AZURE_FOUNDRY_API_KEY"],
               !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values["kimikey"] = legacy
            }
            return ModelRuntimeConfiguration(environmentValues: values, loadedPrivateFile: true)
        }.value
    }

    private static func defaultFileURL() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PrivateModelConfigurationError.unreadable
        }
        return support.appendingPathComponent("VoxPocket/config.private.json")
    }

    private static func readProtectedFile(_ url: URL) throws -> Data? {
        // O_NONBLOCK 防止命名管道卡住启动；O_NOFOLLOW 拒绝最终路径是符号链接。
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw PrivateModelConfigurationError.unreadable
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw PrivateModelConfigurationError.unreadable }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o600 else {
            throw PrivateModelConfigurationError.unsafeFile
        }
        guard info.st_size <= maximumBytes else { throw PrivateModelConfigurationError.oversized }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data: Data
        do { data = try handle.read(upToCount: maximumBytes + 1) ?? Data() }
        catch { throw PrivateModelConfigurationError.unreadable }
        guard data.count <= maximumBytes else { throw PrivateModelConfigurationError.oversized }
        do {
            var file = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try file.setResourceValues(values)
        } catch { throw PrivateModelConfigurationError.unreadable }
        return data
    }
}
