import Foundation
import VoxCore

// redline-allow: R1 filesystem operations use host-injected model cache locations only.
struct WhisperKitModelCacheAdapter: Sendable {
    let storageLocations: VoxStorageLocations
    func prepareDirectory() throws -> URL {
        let directory = storageLocations.modelCache
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    func reset(modelFolder: URL?) throws {
        let paths = [modelFolder, storageLocations.modelCache].compactMap { $0 }
            + storageLocations.modelCacheCleanupCandidates
        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        _ = try prepareDirectory()
    }
}
