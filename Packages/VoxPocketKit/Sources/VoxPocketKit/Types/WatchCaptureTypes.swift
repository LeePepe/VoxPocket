import Foundation
import CoreModels

public enum WatchCaptureError: Error, Equatable, Sendable {
    case unavailable
    case invalidMetadata(String)
    case invalidAudioFile
    case permissionDenied
    case alreadyRecording
    case notRecording
    case transportUnavailable
    case captureFailed
}

public struct WatchCaptureMetadata: Codable, Equatable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let maxDuration: TimeInterval = 60 * 60
    public static let maxFileBytes = 25 * 1024 * 1024

    public let version: Int
    public let captureID: UUID
    public let duration: TimeInterval
    public let source: DeviceSource
    public let audioType: String
    public let basename: String

    public init(captureID: UUID, duration: TimeInterval, source: DeviceSource = .appleWatch, audioType: String = "audio/mp4", basename: String) throws {
        guard Self.versionIsValid(Self.currentVersion), duration.isFinite, duration >= 0, duration <= Self.maxDuration else {
            throw WatchCaptureError.invalidMetadata("capture metadata out of bounds")
        }
        guard source == .appleWatch, audioType == "audio/mp4", Self.isSafeBasename(basename), basename == "\(captureID.uuidString).m4a" else {
            throw WatchCaptureError.invalidMetadata("capture metadata does not match the Watch contract")
        }
        self.version = Self.currentVersion
        self.captureID = captureID
        self.duration = duration
        self.source = source
        self.audioType = audioType
        self.basename = basename
    }

    private init(version: Int, captureID: UUID, duration: TimeInterval, source: DeviceSource, audioType: String, basename: String) throws {
        guard Self.versionIsValid(version), duration.isFinite, duration >= 0, duration <= Self.maxDuration,
              source == .appleWatch, audioType == "audio/mp4", Self.isSafeBasename(basename), basename == "\(captureID.uuidString).m4a" else {
            throw WatchCaptureError.invalidMetadata("capture metadata out of bounds")
        }
        self.version = version; self.captureID = captureID; self.duration = duration; self.source = source; self.audioType = audioType; self.basename = basename
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(version: c.decode(Int.self, forKey: .version),
                      captureID: c.decode(UUID.self, forKey: .captureID),
                      duration: c.decode(TimeInterval.self, forKey: .duration),
                      source: c.decode(DeviceSource.self, forKey: .source),
                      audioType: c.decode(String.self, forKey: .audioType),
                      basename: c.decode(String.self, forKey: .basename))
    }

    private enum CodingKeys: String, CodingKey { case version, captureID, duration, source, audioType, basename }
    private static func versionIsValid(_ value: Int) -> Bool { value == currentVersion }
    private static func isSafeBasename(_ value: String) -> Bool { !value.isEmpty && !value.contains("/") && !value.contains("\\") && value == value.lastPathComponent }
}

private extension String {
    var lastPathComponent: String { components(separatedBy: "/").last ?? self }
}

public enum WatchCaptureSyncStatus: Codable, Equatable, Sendable {
    case transferring
    case processingOnPhone
    case todoAdded(captureID: UUID, title: String, todoID: UUID)
    case failed(captureID: UUID, reason: String)
}

public struct WatchCaptureReceipt: Codable, Equatable, Sendable {
    public let captureID: UUID
    public let status: WatchCaptureSyncStatus
    public init(captureID: UUID, status: WatchCaptureSyncStatus) { self.captureID = captureID; self.status = status }
}

public struct WatchAudioCapture: Equatable, Sendable {
    public let captureID: UUID
    public let fileURL: URL
    public let duration: TimeInterval
    public init(captureID: UUID, fileURL: URL, duration: TimeInterval) { self.captureID = captureID; self.fileURL = fileURL; self.duration = duration }
}

public struct WatchAudioLevel: Equatable, Sendable {
    public let captureID: UUID
    public let normalizedLevel: Float
    public let elapsed: TimeInterval
    public init(captureID: UUID, normalizedLevel: Float, elapsed: TimeInterval = 0) {
        self.captureID = captureID
        self.normalizedLevel = normalizedLevel.isFinite ? min(max(normalizedLevel, 0), 1) : 0
        self.elapsed = elapsed.isFinite ? max(0, elapsed) : 0
    }
}
