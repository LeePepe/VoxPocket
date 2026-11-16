import Foundation

/// 通知权限状态
public enum VoxNotificationAuthorizationStatus: String, Codable, Equatable, Hashable, Sendable {
    case notDetermined
    case provisional
    case authorized
    case denied
}

/// 通知中断级别
public enum VoxNotificationInterruptionPriority: String, Codable, Equatable, Hashable, Sendable {
    case high
    case normal
    case low
}

/// 待调度的独立通知请求模型（零业务模型耦合）
public struct VoxScheduledNotificationItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let itemID: UUID
    public var id: String { Self.notificationIdentifier(for: itemID) }
    public let title: String
    public let subtitle: String?
    public let body: String?
    public let fireDate: Date
    public let slot: HabitTimeSlot?
    public let tags: [String]
    public let priority: VoxNotificationInterruptionPriority

    public init(
        itemID: UUID,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        fireDate: Date,
        slot: HabitTimeSlot? = nil,
        tags: [String] = [],
        priority: VoxNotificationInterruptionPriority = .normal
    ) {
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.fireDate = fireDate
        self.slot = slot
        self.tags = tags
        self.priority = priority
    }

    public func withUpdatedFireDate(_ newFireDate: Date, slot: HabitTimeSlot? = nil) -> VoxScheduledNotificationItem {
        VoxScheduledNotificationItem(
            itemID: itemID,
            title: title,
            subtitle: subtitle,
            body: body,
            fireDate: newFireDate,
            slot: slot ?? self.slot,
            tags: tags,
            priority: priority
        )
    }

    public static func notificationIdentifier(for itemID: UUID) -> String {
        "vox.notification.todo.\(itemID.uuidString)"
    }
}

/// 通知快捷动作触发后的结构化回流事件
public struct VoxNotificationActionEvent: Codable, Equatable, Hashable, Sendable {
    public let itemID: UUID
    public let action: VoxNotificationQuickAction
    public let slot: HabitTimeSlot?
    public let tags: [String]
    public let previousFireDate: Date?
    public let rescheduledFireDate: Date?
    public let triggeredAt: Date

    public init(
        itemID: UUID,
        action: VoxNotificationQuickAction,
        slot: HabitTimeSlot?,
        tags: [String],
        previousFireDate: Date?,
        rescheduledFireDate: Date?,
        triggeredAt: Date = Date()
    ) {
        self.itemID = itemID
        self.action = action
        self.slot = slot
        self.tags = tags
        self.previousFireDate = previousFireDate
        self.rescheduledFireDate = rescheduledFireDate
        self.triggeredAt = triggeredAt
    }
}
