import Foundation

/// 六大标准作息时间段（纯值类型，零外部业务耦合，可原样迁移至任意 App）
public enum HabitTimeSlot: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case morning
    case forenoon
    case noon
    case afternoon
    case evening
    case night

    /// 冷启动默认分钟数（自当日 00:00 起算）
    public var defaultMinutesFromMidnight: Int {
        switch self {
        case .morning:   540  // 09:00
        case .forenoon:  600  // 10:00
        case .noon:      750  // 12:30
        case .afternoon: 900  // 15:00
        case .evening:   1110 // 18:30
        case .night:     1230 // 20:30
        }
    }

    /// Winsorized 异常截断合法范围（自当日 00:00 起算的分钟数）
    public var validMinuteRange: ClosedRange<Int> {
        switch self {
        case .morning:   330...630   // 05:30...10:30
        case .forenoon:  510...720   // 08:30...12:00
        case .noon:      690...840   // 11:30...14:00
        case .afternoon: 810...1050  // 13:30...17:30
        case .evening:   1020...1230 // 17:00...20:30
        case .night:     1140...1410 // 19:00...23:30
        }
    }

    /// 中文展示名称
    public var localizedLabel: String {
        switch self {
        case .morning:   "早上"
        case .forenoon:  "上午"
        case .noon:      "中午"
        case .afternoon: "下午"
        case .evening:   "傍晚"
        case .night:     "晚上"
        }
    }

    /// 从小时（0..23）和分钟（0..59）推断最近的标准作息时段
    public static func inferSlot(fromMinutesFromMidnight minutes: Int) -> HabitTimeSlot {
        let clamped = max(0, min(1439, minutes))
        switch clamped {
        case ..<570:     return .morning
        case 570..<690:  return .forenoon
        case 690..<810:  return .noon
        case 810..<1020: return .afternoon
        case 1020..<1170: return .evening
        default:         return .night
        }
    }
}

/// 锁屏 / 横幅 / Apple Watch 通知分类与全部 4 个免解锁快捷交互动作
public enum VoxNotificationQuickAction: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case markDone          = "vox.notification.action.markDone"
    case snooze15m         = "vox.notification.action.snooze15m"
    case snooze1h          = "vox.notification.action.snooze1h"
    case deferToNextAnchor = "vox.notification.action.deferToNextAnchor"

    public static let categoryIdentifier = "vox.notification.todo.reminder"

    public var localizedTitle: String {
        switch self {
        case .markDone:          "✅ 完成"
        case .snooze15m:         "⏰ 15分钟后"
        case .snooze1h:          "⏰ 延后 1 小时"
        case .deferToNextAnchor: "🌙 推迟到今晚/明早"
        }
    }

    public static func parse(_ rawIdentifier: String) -> VoxNotificationQuickAction? {
        if let exact = VoxNotificationQuickAction(rawValue: rawIdentifier) {
            return exact
        }
        switch rawIdentifier {
        case "markDone":          return .markDone
        case "snooze15m":         return .snooze15m
        case "snooze1h":          return .snooze1h
        case "deferToNextAnchor": return .deferToNextAnchor
        default:                  return nil
        }
    }
}

/// 习惯时间锚点学习反馈信号
public enum HabitFeedbackSignal: Sendable, Equatable {
    /// 信号①：用户显式手动改期（高权重 α = 0.35）
    case manualOverride(newDate: Date)
    /// 信号②：用户在通知交互中点击延后（中权重 α = 0.20）
    case snoozed(targetDate: Date)
    /// 信号③：用户在提醒触发附近完成了事项（温和权重 α = 0.15）
    case completedNearNotification(completedAt: Date)

    public var alphaWeight: Double {
        switch self {
        case .manualOverride:            0.35
        case .snoozed:                   0.20
        case .completedNearNotification: 0.15
        }
    }

    public var observedDate: Date {
        switch self {
        case .manualOverride(let date),
             .snoozed(let date),
             .completedNearNotification(let date):
            return date
        }
    }
}

/// 时间锚点解析来源
public enum HabitAnchorResolutionSource: String, Codable, Equatable, Hashable, Sendable {
    case coldStartDefault
    case globalSlotLearned
    case tagContextualLearned
}

/// 解析后的个人习惯时间锚点
public struct ResolvedHabitTimeAnchor: Codable, Equatable, Hashable, Sendable {
    public let slot: HabitTimeSlot
    public let matchedTag: String?
    public let minutesFromMidnight: Int
    public let targetDate: Date
    public let didRollOverToNextDay: Bool
    public let source: HabitAnchorResolutionSource
    public let sampleCount: Int

    public var hour: Int { minutesFromMidnight / 60 }
    public var minute: Int { minutesFromMidnight % 60 }

    public init(
        slot: HabitTimeSlot,
        matchedTag: String?,
        minutesFromMidnight: Int,
        targetDate: Date,
        didRollOverToNextDay: Bool,
        source: HabitAnchorResolutionSource,
        sampleCount: Int
    ) {
        self.slot = slot
        self.matchedTag = matchedTag
        self.minutesFromMidnight = minutesFromMidnight
        self.targetDate = targetDate
        self.didRollOverToNextDay = didRollOverToNextDay
        self.source = source
        self.sampleCount = sampleCount
    }
}
