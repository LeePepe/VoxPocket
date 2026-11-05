import Foundation

public struct VoxStorageLocations: Sendable, Equatable {
    public let temporaryAudio: URL
    public let modelCache: URL
    public let modelCacheCleanupCandidates: [URL]
    public init(temporaryAudio: URL, modelCache: URL, modelCacheCleanupCandidates: [URL] = []) {
        self.temporaryAudio = temporaryAudio
        self.modelCache = modelCache
        self.modelCacheCleanupCandidates = modelCacheCleanupCandidates
    }
}
