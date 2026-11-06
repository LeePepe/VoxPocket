import Foundation
import VoxCore

public struct TemporaryAudioStore: Sendable {
    public let storageLocations: VoxStorageLocations
    public init(storageLocations: VoxStorageLocations, fileManager: FileManager = .default) {
        self.storageLocations = storageLocations
        _ = fileManager
    }

    public func makeRecordingFileURL() throws -> URL {
        var directory = storageLocations.temporaryAudio
        // redline-allow: R1 injected storage location; this is the sole filesystem boundary.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // redline-allow: R1 injected storage location; enforce private permissions and backup exclusion.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        // redline-allow: R1 injected storage location; mark temporary audio backup-excluded.
        try directory.setResourceValues(values)
        return directory.appendingPathComponent("mic_\(UUID().uuidString).wav")
    }

    public func write(_ data: Data, to url: URL) throws {
        // redline-allow: R1 injected storage location.
        try data.write(to: url, options: .atomic)
    }

    public func read(from url: URL) throws -> Data {
        // redline-allow: R1 injected storage location.
        return try Data(contentsOf: url) // redline-allow: R1 injected storage location
    }

    public func remove(_ url: URL) throws {
        // redline-allow: R1 injected storage location.
        try FileManager.default.removeItem(at: url)
    }
}
