#if os(macOS)
import Darwin
import Foundation
import LokiKit
import Synchronization

enum BenchmarkFailure: String, Error {
    case unsafePath, unsafeFile, invalidManifest, invalidAudio, unauthorized, unavailable
    case recognitionFailed, timeout, missingModel, invalidConfiguration, emptyResult
}

/// 不求值日志消息，也不保存正文或上下文；评测不能接入任何日志后端。
final class SilentBenchmarkLogger: Logger {
    private let level = Mutex(LogLevel.critical)
    var minimumLevel: LogLevel {
        get { level.withLock { $0 } }
        set { level.withLock { $0 = newValue } }
    }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String,
             file: String, function: String, line: Int) {}
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, context: [String: Any],
             file: String, function: String, line: Int) {}
}

struct BenchmarkManifest: Decodable, Sendable {
    let audio_file: String
    let reference_text: String
    let locale: String
    let duration_seconds: Double
    let cold_runs: Int
    let warm_runs: Int
}

enum ProtectedBenchmarkFiles {
    static var sandbox: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket")
    }

    static func validateDirectory(_ url: URL, beneath root: URL) throws {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        guard path.hasPrefix(base + "/"), url.resolvingSymlinksInPath().path == path else {
            throw BenchmarkFailure.unsafePath
        }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700 else {
            throw BenchmarkFailure.unsafeFile
        }
    }

    static func read(_ url: URL, beneath root: URL, maximumBytes: Int) throws -> Data {
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
              url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
            throw BenchmarkFailure.unsafePath
        }
        let parent = try openParent(of: url)
        defer { close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw BenchmarkFailure.unsafeFile }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o600,
              info.st_size > 0, info.st_size <= maximumBytes else { throw BenchmarkFailure.unsafeFile }
        guard let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            .read(upToCount: maximumBytes + 1), data.count <= maximumBytes else {
            throw BenchmarkFailure.unsafeFile
        }
        return data
    }

    static func write<T: Encodable>(_ value: T, to url: URL, beneath root: URL) throws {
        try writeData(JSONEncoder().encode(value), to: url, beneath: root)
    }

    static func writeData(_ data: Data, to url: URL, beneath root: URL) throws {
        try validateDirectory(url.deletingLastPathComponent(), beneath: root)
        let parent = try openParent(of: url)
        defer { close(parent) }
        var info = stat()
        guard fstat(parent, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700 else {
            throw BenchmarkFailure.unsafeFile
        }
        let fd = openat(parent, url.lastPathComponent, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BenchmarkFailure.unsafeFile }
        defer { close(fd) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
    }

    /// 每个路径分量都通过目录描述符解析，避免祖先目录在检查后被换成符号链接。
    private static func openParent(of url: URL) throws -> Int32 {
        let parts = url.pathComponents.dropFirst().dropLast()
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw BenchmarkFailure.unsafePath }
        for part in parts {
            let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else { throw BenchmarkFailure.unsafePath }
            descriptor = next
        }
        return descriptor
    }

    static func manifest(in root: URL) throws -> BenchmarkManifest {
        try validateDirectory(root, beneath: sandbox)
        let data = try read(root.appendingPathComponent("manifest.json"), beneath: root, maximumBytes: 65536)
        guard let manifest = try? JSONDecoder().decode(BenchmarkManifest.self, from: data),
              manifest.audio_file == "sample.m4a", manifest.cold_runs == 1, manifest.warm_runs == 5,
              !manifest.reference_text.isEmpty, manifest.reference_text.count <= 10000,
              manifest.duration_seconds > 0, manifest.duration_seconds < 60,
              ["zh-Hans", "zh_CN", "zh-CN"].contains(manifest.locale) else {
            throw BenchmarkFailure.invalidManifest
        }
        return manifest
    }
}
#endif
