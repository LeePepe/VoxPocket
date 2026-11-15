import Foundation
import Synchronization
#if canImport(AVFoundation)
import AVFoundation
#endif

/// WCSession 临时文件必须在回调返回前取得所有权；元数据先落盘，目录 rename 为提交点。
public final class WatchInboxStore: Sendable {
    public let directory: URL
    private let lock = Mutex<Void>(())
    public init(directory: URL) { self.directory = directory }

    public func claim(_ source: URL, metadata: WatchCaptureMetadata) throws -> URL {
        try lock.withLock { _ in
            try WatchAudioFileValidation.validate(source)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.resolvingSymlinksInPath().appendingPathComponent(metadata.captureID.uuidString, isDirectory: true)
            let owned = destination.appendingPathComponent(metadata.basename)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try readMetadata(destination) == metadata else { throw WatchCaptureError.invalidAudioFile }
                try WatchAudioFileValidation.validate(owned)
                return owned
            }
            let staging = directory.resolvingSymlinksInPath().appendingPathComponent("\(metadata.captureID.uuidString).staging", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try JSONEncoder().encode(metadata).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
            let stagedAudio = staging.appendingPathComponent(metadata.basename)
            if !FileManager.default.fileExists(atPath: stagedAudio.path) {
                let partial = staging.appendingPathComponent("\(UUID().uuidString).part")
                defer { try? FileManager.default.removeItem(at: partial) }
                try FileManager.default.copyItem(at: source, to: partial)
                try WatchAudioFileValidation.validateRegularFile(partial, maxBytes: WatchCaptureMetadata.maxFileBytes)
                try FileManager.default.moveItem(at: partial, to: stagedAudio)
            }
            try WatchAudioFileValidation.validate(stagedAudio)
            try FileManager.default.moveItem(at: staging, to: destination)
            return owned
        }
    }

    public func recover() throws -> [(URL, WatchCaptureMetadata)] {
        try lock.withLock { _ in
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            var result: [(URL, WatchCaptureMetadata)] = []
            for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                guard (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
                if entry.pathExtension == "m4a" {
                    if let recovered = try recoverLegacy(entry) { result.append(recovered) }
                    continue
                }
                let name = entry.deletingPathExtension().lastPathComponent
                guard let id = UUID(uuidString: name), let metadata = try? readMetadata(entry), metadata.captureID == id else { continue }
                let audio = entry.appendingPathComponent(metadata.basename)
                guard (try? WatchAudioFileValidation.validate(audio)) != nil else { continue }
                if entry.pathExtension == "staging" {
                    let destination = directory.appendingPathComponent(id.uuidString, isDirectory: true)
                    if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: entry, to: destination) }
                    result.append((destination.appendingPathComponent(metadata.basename), metadata))
                } else if entry.lastPathComponent == id.uuidString { result.append((audio, metadata)) }
            }
            return result
        }
    }

    private func readMetadata(_ folder: URL) throws -> WatchCaptureMetadata {
        let url = folder.appendingPathComponent("metadata.json")
        try WatchAudioFileValidation.validateRegularFile(url, maxBytes: 4096)
        return try JSONDecoder().decode(WatchCaptureMetadata.self, from: Data(contentsOf: url))
    }

    private func recoverLegacy(_ url: URL) throws -> (URL, WatchCaptureMetadata)? {
        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), url.lastPathComponent == "\(id.uuidString).m4a" else { return nil }
        try WatchAudioFileValidation.validate(url)
        #if canImport(AVFoundation)
        guard let audio = try? AVAudioPlayer(contentsOf: url) else { return nil }
        let metadata = try WatchCaptureMetadata(captureID: id, duration: audio.duration, basename: url.lastPathComponent)
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(metadata).write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
        let owned = folder.appendingPathComponent(metadata.basename)
        if !FileManager.default.fileExists(atPath: owned.path) { try FileManager.default.copyItem(at: url, to: owned) }
        return (owned, metadata)
        #else
        return nil
        #endif
    }
}

public enum WatchAudioFileValidation {
    public static func validate(_ url: URL) throws {
        guard url.pathExtension.lowercased() == "m4a" else { throw WatchCaptureError.invalidAudioFile }
        try validateRegularFile(url, maxBytes: WatchCaptureMetadata.maxFileBytes)
    }
    public static func validateRegularFile(_ url: URL, maxBytes: Int) throws {
        guard url.isFileURL else { throw WatchCaptureError.invalidAudioFile }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
              size > 0, size <= maxBytes, url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
            throw WatchCaptureError.invalidAudioFile
        }
    }
}
