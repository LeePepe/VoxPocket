import Foundation

/// 单个时间槽（或 `slot + #tag`）的端侧统计桶
public struct HabitAnchorBucket: Codable, Equatable, Hashable, Sendable {
    public let slot: HabitTimeSlot
    public let normalizedTag: String?
    public let emaMinutes: Double
    public let sampleCount: Int
    public let updatedAt: Date

    public init(
        slot: HabitTimeSlot,
        normalizedTag: String? = nil,
        emaMinutes: Double,
        sampleCount: Int,
        updatedAt: Date = Date()
    ) {
        self.slot = slot
        self.normalizedTag = normalizedTag
        self.emaMinutes = emaMinutes
        self.sampleCount = sampleCount
        self.updatedAt = updatedAt
    }
}

/// 持久化在端侧沙盒 `time-anchor-habits.json` 的快照结构
public struct HabitTimeAnchorSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var globalSlotBuckets: [String: HabitAnchorBucket]
    public var tagSlotBuckets: [String: HabitAnchorBucket]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        globalSlotBuckets: [String: HabitAnchorBucket] = [:],
        tagSlotBuckets: [String: HabitAnchorBucket] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.globalSlotBuckets = globalSlotBuckets
        self.tagSlotBuckets = tagSlotBuckets
    }
}

/// 习惯时间锚点持久化存储协议
public protocol HabitTimeAnchorStore: Sendable {
    func loadSnapshot() throws -> HabitTimeAnchorSnapshot
    func saveSnapshot(_ snapshot: HabitTimeAnchorSnapshot) throws
}

/// 基于沙盒 JSON 文件的持久化实现（遵循宪法 IV/VI 边界输入校验与原子写入）
public struct FileHabitTimeAnchorStore: HabitTimeAnchorStore, Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("VoxPocket", isDirectory: true)
                .appendingPathComponent("time-anchor-habits.json", isDirectory: false)
        }
    }

    public func loadSnapshot() throws -> HabitTimeAnchorSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HabitTimeAnchorSnapshot()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HabitTimeAnchorSnapshot.self, from: data)
        return Self.sanitize(decoded)
    }

    public func saveSnapshot(_ snapshot: HabitTimeAnchorSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Self.sanitize(snapshot))
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func sanitize(_ snapshot: HabitTimeAnchorSnapshot) -> HabitTimeAnchorSnapshot {
        var cleanGlobal: [String: HabitAnchorBucket] = [:]
        for (key, bucket) in snapshot.globalSlotBuckets where bucket.emaMinutes.isFinite && bucket.sampleCount >= 0 {
            let clamped = min(max(bucket.emaMinutes, Double(bucket.slot.validMinuteRange.lowerBound)), Double(bucket.slot.validMinuteRange.upperBound))
            cleanGlobal[key] = HabitAnchorBucket(
                slot: bucket.slot,
                normalizedTag: nil,
                emaMinutes: clamped,
                sampleCount: bucket.sampleCount,
                updatedAt: bucket.updatedAt
            )
        }

        var cleanTags: [String: HabitAnchorBucket] = [:]
        for (key, bucket) in snapshot.tagSlotBuckets where bucket.emaMinutes.isFinite && bucket.sampleCount >= 0 {
            let clamped = min(max(bucket.emaMinutes, Double(bucket.slot.validMinuteRange.lowerBound)), Double(bucket.slot.validMinuteRange.upperBound))
            cleanTags[key] = HabitAnchorBucket(
                slot: bucket.slot,
                normalizedTag: bucket.normalizedTag,
                emaMinutes: clamped,
                sampleCount: bucket.sampleCount,
                updatedAt: bucket.updatedAt
            )
        }

        return HabitTimeAnchorSnapshot(
            schemaVersion: HabitTimeAnchorSnapshot.currentSchemaVersion,
            globalSlotBuckets: cleanGlobal,
            tagSlotBuckets: cleanTags
        )
    }
}
