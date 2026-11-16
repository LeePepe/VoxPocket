import Foundation
import Synchronization

/// 自适应作息时间锚点学习器协议（深模块 Seam）
public protocol AdaptiveTimeAnchorLearning: AnyObject, Sendable {
    /// 解析目标提醒时间（支持 `(slot, #tag) -> slot -> coldStartDefault` 两级经验贝叶斯收缩与当日过期自动顺延）
    func resolveAnchor(
        for slot: HabitTimeSlot,
        dayOffset: Int,
        tags: [String],
        now: Date
    ) -> ResolvedHabitTimeAnchor

    /// 记录一次用户反馈信号并更新两级统计桶（自动持久化至沙盒 `time-anchor-habits.json`）
    @discardableResult
    func recordSignal(
        _ signal: HabitFeedbackSignal,
        for slot: HabitTimeSlot,
        tags: [String]
    ) -> ResolvedHabitTimeAnchor

    /// 导出当前所有 6 个时段的已学习锚点分钟表（用于注入 AI 提示词上下文）
    func currentAnchorSummary(for tags: [String], now: Date) -> [HabitTimeSlot: Int]

    /// 重置全部学习状态回冷启动默认值
    func resetAllHabits()
}

/// `global_plus_tag_two_level` 自适应作息时间习惯学习器默认实现
public final class AdaptiveTimeAnchorLearner: AdaptiveTimeAnchorLearning, Sendable {
    private final class SnapshotBox: Sendable {
        let mutex: Mutex<HabitTimeAnchorSnapshot>
        init(_ initial: HabitTimeAnchorSnapshot) {
            self.mutex = Mutex(initial)
        }
    }

    private let store: any HabitTimeAnchorStore
    private let calendar: Calendar
    private let box: SnapshotBox

    public init(
        store: any HabitTimeAnchorStore = FileHabitTimeAnchorStore(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.calendar = calendar
        let initial = (try? store.loadSnapshot()) ?? HabitTimeAnchorSnapshot()
        self.box = SnapshotBox(initial)
    }

    public func resolveAnchor(
        for slot: HabitTimeSlot,
        dayOffset: Int = 0,
        tags: [String] = [],
        now: Date = Date()
    ) -> ResolvedHabitTimeAnchor {
        let snapshot = box.mutex.withLock { $0 }
        return resolveFromSnapshot(
            snapshot,
            slot: slot,
            dayOffset: dayOffset,
            tags: tags,
            now: now
        )
    }

    @discardableResult
    public func recordSignal(
        _ signal: HabitFeedbackSignal,
        for slot: HabitTimeSlot,
        tags: [String] = []
    ) -> ResolvedHabitTimeAnchor {
        let observedDate = signal.observedDate
        let rawMinutes = minutesFromMidnight(for: observedDate)
        let clampedMinutes = Double(
            min(
                max(rawMinutes, slot.validMinuteRange.lowerBound),
                slot.validMinuteRange.upperBound
            )
        )
        let baseAlpha = signal.alphaWeight
        let normalizedTags = Self.normalizeTagKeys(tags)

        let updatedSnapshot = box.mutex.withLock { snapshot -> HabitTimeAnchorSnapshot in
            var next = snapshot
            let slotKey = slot.rawValue
            let existingGlobal = next.globalSlotBuckets[slotKey]
            let defaultMinutes = Double(slot.defaultMinutesFromMidnight)
            let globalPrior = existingGlobal?.emaMinutes ?? defaultMinutes
            let globalCount = existingGlobal?.sampleCount ?? 0
            // 仅 manualOverride / snoozed 在冷启动首样本适度加速，completion 保持原始 α 以抑制异常值
            let effectiveGlobalAlpha: Double
            switch signal {
            case .manualOverride where globalCount == 0:
                effectiveGlobalAlpha = min(0.55, baseAlpha * 1.4)
            case .snoozed:
                effectiveGlobalAlpha = min(0.45, baseAlpha * 1.6)
            default:
                effectiveGlobalAlpha = baseAlpha
            }
            let updatedGlobalEMA = (1.0 - effectiveGlobalAlpha) * globalPrior + effectiveGlobalAlpha * clampedMinutes
            next.globalSlotBuckets[slotKey] = HabitAnchorBucket(
                slot: slot,
                normalizedTag: nil,
                emaMinutes: updatedGlobalEMA,
                sampleCount: globalCount + 1,
                updatedAt: observedDate
            )

            for tag in normalizedTags {
                let tagKey = Self.tagBucketKey(slot: slot, normalizedTag: tag)
                let existingTag = next.tagSlotBuckets[tagKey]
                let tagCount = existingTag?.sampleCount ?? 0
                let tagPrior = existingTag?.emaMinutes ?? defaultMinutes
                // 恢复首样本 manualOverride 锚定与 snooze/completion 按 2.2x α 插值，由外部经验贝叶斯收缩 λ = n/(n+2) 控制样本数平滑
                let updatedTagEMA: Double
                if tagCount == 0 {
                    switch signal {
                    case .manualOverride:
                        updatedTagEMA = clampedMinutes
                    case .snoozed:
                        let effectiveAlpha = min(0.70, baseAlpha * 2.5)
                        updatedTagEMA = (1.0 - effectiveAlpha) * updatedGlobalEMA + effectiveAlpha * clampedMinutes
                    case .completedNearNotification:
                        updatedTagEMA = (1.0 - baseAlpha) * updatedGlobalEMA + baseAlpha * clampedMinutes
                    }
                } else {
                    let effectiveTagAlpha = (signal.alphaWeight >= 0.35) ? min(0.75, baseAlpha * 1.8) : min(0.70, baseAlpha * 3.0)
                    updatedTagEMA = (1.0 - effectiveTagAlpha) * tagPrior + effectiveTagAlpha * clampedMinutes
                }
                next.tagSlotBuckets[tagKey] = HabitAnchorBucket(
                    slot: slot,
                    normalizedTag: tag,
                    emaMinutes: updatedTagEMA,
                    sampleCount: tagCount + 1,
                    updatedAt: observedDate
                )
            }
            snapshot = next
            return next
        }

        try? store.saveSnapshot(updatedSnapshot)
        return resolveFromSnapshot(
            updatedSnapshot,
            slot: slot,
            dayOffset: 0,
            tags: tags,
            now: observedDate
        )
    }

    public func currentAnchorSummary(for tags: [String] = [], now: Date = Date()) -> [HabitTimeSlot: Int] {
        let snapshot = box.mutex.withLock { $0 }
        var map: [HabitTimeSlot: Int] = [:]
        for slot in HabitTimeSlot.allCases {
            let resolved = resolveFromSnapshot(snapshot, slot: slot, dayOffset: 0, tags: tags, now: now)
            map[slot] = resolved.minutesFromMidnight
        }
        return map
    }

    public func resetAllHabits() {
        let empty = HabitTimeAnchorSnapshot()
        box.mutex.withLock { $0 = empty }
        try? store.saveSnapshot(empty)
    }

    // MARK: - Internal Resolution Math

    private func resolveFromSnapshot(
        _ snapshot: HabitTimeAnchorSnapshot,
        slot: HabitTimeSlot,
        dayOffset: Int,
        tags: [String],
        now: Date
    ) -> ResolvedHabitTimeAnchor {
        let slotKey = slot.rawValue
        let globalBucket = snapshot.globalSlotBuckets[slotKey]
        let defaultMinutes = Double(slot.defaultMinutesFromMidnight)

        // 第一级：全局 slot 锚点 EMA（内部已包含与 defaultMinutes 的指数平滑）
        let globalSamples = globalBucket?.sampleCount ?? 0
        let globalEstimate: Double = (globalBucket != nil && globalSamples > 0)
            ? globalBucket!.emaMinutes
            : defaultMinutes

        // 第二级：(slot, #tag) 条件锚点对全局 slot 锚点的经验贝叶斯收缩 λ_tag = n / (n + 2)
        let normalizedTags = Self.normalizeTagKeys(tags)
        var bestTagBucket: HabitAnchorBucket?
        for tag in normalizedTags {
            let key = Self.tagBucketKey(slot: slot, normalizedTag: tag)
            if let candidate = snapshot.tagSlotBuckets[key],
               candidate.sampleCount > (bestTagBucket?.sampleCount ?? 0) {
                bestTagBucket = candidate
            }
        }

        let rawResolvedMinutes: Double
        let source: HabitAnchorResolutionSource
        let matchedTag: String?
        let totalSamples: Int

        if let tagBucket = bestTagBucket, tagBucket.sampleCount > 0 {
            let n = Double(tagBucket.sampleCount)
            let lambdaTag = n / (n + 2.0)
            rawResolvedMinutes = lambdaTag * tagBucket.emaMinutes + (1.0 - lambdaTag) * globalEstimate
            source = .tagContextualLearned
            matchedTag = tagBucket.normalizedTag
            totalSamples = tagBucket.sampleCount
        } else if globalSamples > 0 {
            rawResolvedMinutes = globalEstimate
            source = .globalSlotLearned
            matchedTag = nil
            totalSamples = globalSamples
        } else {
            rawResolvedMinutes = defaultMinutes
            source = .coldStartDefault
            matchedTag = nil
            totalSamples = 0
        }

        // 对齐至 5 分钟粒度并截断在合法时间窗内
        let roundedToFive = Int((rawResolvedMinutes / 5.0).rounded()) * 5
        let finalMinutes = min(
            max(roundedToFive, slot.validMinuteRange.lowerBound),
            slot.validMinuteRange.upperBound
        )

        let (targetDate, rolledOver) = buildTargetDate(
            minutesFromMidnight: finalMinutes,
            dayOffset: max(0, dayOffset),
            now: now
        )

        return ResolvedHabitTimeAnchor(
            slot: slot,
            matchedTag: matchedTag,
            minutesFromMidnight: finalMinutes,
            targetDate: targetDate,
            didRollOverToNextDay: rolledOver,
            source: source,
            sampleCount: totalSamples
        )
    }

    private func buildTargetDate(
        minutesFromMidnight: Int,
        dayOffset: Int,
        now: Date
    ) -> (Date, Bool) {
        let startOfToday = calendar.startOfDay(for: now)
        let requestedDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) ?? startOfToday
        let candidate = calendar.date(byAdding: .minute, value: minutesFromMidnight, to: requestedDay)
            ?? now.addingTimeInterval(3600)

        // 当 dayOffset == 0 且目标时间已过去（或距现在不足 60 秒）时，智能顺延到明天同一习惯锚点
        if dayOffset == 0 && candidate <= now.addingTimeInterval(60) {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: candidate)
                ?? candidate.addingTimeInterval(86_400)
            return (nextDay, true)
        }
        return (candidate, false)
    }

    private func minutesFromMidnight(for date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 9) * 60 + (components.minute ?? 0)
    }

    public static func normalizeTagKeys(_ tags: [String]) -> [String] {
        var result: [String] = []
        for raw in tags {
            var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while cleaned.hasPrefix("#") {
                cleaned.removeFirst()
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleaned.isEmpty, !result.contains(cleaned) else { continue }
            result.append(cleaned)
        }
        return result
    }

    private static func tagBucketKey(slot: HabitTimeSlot, normalizedTag: String) -> String {
        "\(slot.rawValue)#\(normalizedTag)"
    }
}
