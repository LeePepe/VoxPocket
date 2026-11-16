import Foundation
import Synchronization
#if canImport(UserNotifications)
import UserNotifications
#endif

/// 本地通知底层中心适配协议（解耦 `UNUserNotificationCenter` 以便在无签名 CLI/SPM 测试与真机中复用同一深模块）
public protocol VoxNotificationCentering: Sendable {
    func registerReminderCategory() async
    func authorizationStatus() async -> VoxNotificationAuthorizationStatus
    func requestAuthorization(allowProvisional: Bool) async throws -> VoxNotificationAuthorizationStatus
    func addNotificationRequest(_ item: VoxScheduledNotificationItem) async throws
    func removeNotificationRequests(withIdentifiers identifiers: [String]) async
}

/// 原生本地通知调度与 4 动作交互闭环深模块协议
public protocol VoxNotificationScheduling: AnyObject, Sendable {
    /// 订阅锁屏 / 横幅 / Apple Watch 快捷通知动作回流事件流
    var actionEvents: AsyncStream<VoxNotificationActionEvent> { get }

    /// 暴露内部绑定的自适应时间习惯学习器
    var timeAnchorLearner: any AdaptiveTimeAnchorLearning { get }

    /// 注册 `vox.notification.todo.reminder` 分类与全部 4 个快捷动作
    func registerCategories() async

    /// 查询通知权限状态
    func authorizationStatus() async -> VoxNotificationAuthorizationStatus

    /// 请求通知授权（支持 `.provisional` 静默授权）
    @discardableResult
    func requestAuthorizationIfNeeded(allowProvisional: Bool) async throws -> VoxNotificationAuthorizationStatus

    /// 幂等调度或更新一条提醒通知
    @discardableResult
    func schedule(_ item: VoxScheduledNotificationItem) async throws -> VoxScheduledNotificationItem

    /// 按习惯时间槽（`morning / forenoon / noon / afternoon / evening / night`）自动计算习惯锚点并调度通知
    @discardableResult
    func scheduleUsingHabitAnchor(
        itemID: UUID,
        title: String,
        subtitle: String?,
        body: String?,
        slot: HabitTimeSlot,
        dayOffset: Int,
        tags: [String],
        priority: VoxNotificationInterruptionPriority,
        now: Date
    ) async throws -> (item: VoxScheduledNotificationItem, anchor: ResolvedHabitTimeAnchor)

    /// 用户在 UI 手动改期时：既向习惯学习器记录 `.manualOverride` ($\alpha = 0.35$)，又幂等重排本地通知
    @discardableResult
    func rescheduleManualOverride(
        itemID: UUID,
        title: String,
        subtitle: String?,
        body: String?,
        newFireDate: Date,
        slot: HabitTimeSlot?,
        tags: [String],
        priority: VoxNotificationInterruptionPriority
    ) async throws -> VoxScheduledNotificationItem

    /// 取消指定条目的本地通知
    func cancel(itemID: UUID) async

    /// 查询当前内存中登记的全部待触发通知
    func pendingItems() -> [VoxScheduledNotificationItem]

    /// 处理锁屏 / Apple Watch 快捷通知动作（`markDone`、`snooze15m`、`snooze1h`、`deferToNextAnchor`）
    @discardableResult
    func handleAction(
        identifier: String,
        itemID: UUID,
        slot: HabitTimeSlot?,
        tags: [String],
        now: Date
    ) async throws -> VoxNotificationActionEvent?
}

/// 内存态/测试态通知中心实现（同时作为未签名宿主环境的确定性回退）
public final class InMemoryVoxNotificationCenter: VoxNotificationCentering, Sendable {
    private struct State: Sendable {
        var didRegisterCategory = false
        var authStatus: VoxNotificationAuthorizationStatus = .authorized
        var requests: [String: VoxScheduledNotificationItem] = [:]
    }

    private let state = Mutex(State())

    public init(initialStatus: VoxNotificationAuthorizationStatus = .authorized) {
        state.withLock { $0.authStatus = initialStatus }
    }

    public func registerReminderCategory() async {
        state.withLock { $0.didRegisterCategory = true }
    }

    public func authorizationStatus() async -> VoxNotificationAuthorizationStatus {
        state.withLock { $0.authStatus }
    }

    public func requestAuthorization(allowProvisional: Bool) async throws -> VoxNotificationAuthorizationStatus {
        state.withLock { current in
            if current.authStatus == .notDetermined {
                current.authStatus = allowProvisional ? .provisional : .authorized
            }
            return current.authStatus
        }
    }

    public func addNotificationRequest(_ item: VoxScheduledNotificationItem) async throws {
        state.withLock { $0.requests[item.id] = item }
    }

    public func removeNotificationRequests(withIdentifiers identifiers: [String]) async {
        state.withLock { current in
            for id in identifiers {
                current.requests.removeValue(forKey: id)
            }
        }
    }

    public func storedRequests() -> [VoxScheduledNotificationItem] {
        state.withLock { Array($0.requests.values) }
    }
}

#if canImport(UserNotifications)
/// Apple 原生 `UNUserNotificationCenter` 生产环境适配器
public final class SystemUserNotificationCenterAdapter: VoxNotificationCentering, @unchecked Sendable {
    // Sendable: UNUserNotificationCenter.current() is thread-safe for category registration and request scheduling.
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private var availableCenter: UNUserNotificationCenter? {
        // 仅在具备有效 App Bundle (.app) 宿主中调用 UNUserNotificationCenter.current()，且在 UI 自动化测试或命令行 xctest 中跳过
        let env = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app",
              env["XCTestConfigurationFilePath"] == nil,
              env["VOXPOCKET_UI_TEST_HOST"] != "1",
              env["VOX_DEMO_SEED"] != "1" else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    public func registerReminderCategory() async {
        guard let center = availableCenter else { return }
        let actions: [UNNotificationAction] = VoxNotificationQuickAction.allCases.map { action in
            UNNotificationAction(
                identifier: action.rawValue,
                title: action.localizedTitle,
                options: [] // 免解锁直接后台处理
            )
        }
        let category = UNNotificationCategory(
            identifier: VoxNotificationQuickAction.categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let existing = await center.notificationCategories()
        var merged = existing.filter { $0.identifier != VoxNotificationQuickAction.categoryIdentifier }
        merged.insert(category)
        center.setNotificationCategories(merged)
    }

    public func authorizationStatus() async -> VoxNotificationAuthorizationStatus {
        guard let center = availableCenter else { return .provisional }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .provisional:   return .provisional
        case .ephemeral:     return .authorized
        @unknown default:    return .authorized
        }
    }

    public func requestAuthorization(allowProvisional: Bool) async throws -> VoxNotificationAuthorizationStatus {
        guard let center = availableCenter else { return .provisional }
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        #if os(iOS) || os(macOS) || os(watchOS) || os(visionOS)
        if allowProvisional {
            options.insert(.provisional)
        }
        #endif
        let granted = try await center.requestAuthorization(options: options)
        if !granted {
            return await authorizationStatus()
        }
        return await authorizationStatus()
    }

    public func addNotificationRequest(_ item: VoxScheduledNotificationItem) async throws {
        guard let center = availableCenter else { return }
        center.removePendingNotificationRequests(withIdentifiers: [item.id])
        center.removeDeliveredNotifications(withIdentifiers: [item.id])

        let content = UNMutableNotificationContent()
        content.title = item.title
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        if let body = item.body, !body.isEmpty {
            content.body = body
        }
        content.sound = .default
        content.categoryIdentifier = VoxNotificationQuickAction.categoryIdentifier
        var userInfo: [String: Any] = [
            "itemID": item.itemID.uuidString,
            "tags": item.tags
        ]
        if let slot = item.slot {
            userInfo["slot"] = slot.rawValue
        }
        content.userInfo = userInfo

        switch item.priority {
        case .high:
            content.interruptionLevel = .timeSensitive
        case .normal:
            content.interruptionLevel = .active
        case .low:
            content.interruptionLevel = .passive
        }

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: item.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
        try await center.add(request)
    }

    public func removeNotificationRequests(withIdentifiers identifiers: [String]) async {
        guard let center = availableCenter else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
#endif

/// `VoxNotificationScheduler` 核心深模块实现
public final class VoxNotificationScheduler: VoxNotificationScheduling, Sendable {
    public let timeAnchorLearner: any AdaptiveTimeAnchorLearning
    public let actionEvents: AsyncStream<VoxNotificationActionEvent>

    private let center: any VoxNotificationCentering
    private let calendar: Calendar
    private let continuation: AsyncStream<VoxNotificationActionEvent>.Continuation
    private let scheduledByID: Mutex<[UUID: VoxScheduledNotificationItem]>

    public init(
        timeAnchorLearner: any AdaptiveTimeAnchorLearning = AdaptiveTimeAnchorLearner(),
        center: (any VoxNotificationCentering)? = nil,
        calendar: Calendar = .current
    ) {
        self.timeAnchorLearner = timeAnchorLearner
        #if canImport(UserNotifications)
        let env = ProcessInfo.processInfo.environment
        if let center {
            self.center = center
        } else if Bundle.main.bundleIdentifier != nil,
                  Bundle.main.bundleURL.pathExtension == "app",
                  env["XCTestConfigurationFilePath"] == nil,
                  env["VOXPOCKET_UI_TEST_HOST"] != "1",
                  env["VOX_DEMO_SEED"] != "1" {
            self.center = SystemUserNotificationCenterAdapter(calendar: calendar)
        } else {
            self.center = InMemoryVoxNotificationCenter()
        }
        #else
        self.center = center ?? InMemoryVoxNotificationCenter()
        #endif
        self.calendar = calendar
        self.scheduledByID = Mutex([:])

        var capturedContinuation: AsyncStream<VoxNotificationActionEvent>.Continuation!
        self.actionEvents = AsyncStream { cont in
            capturedContinuation = cont
        }
        self.continuation = capturedContinuation
    }

    public func registerCategories() async {
        await center.registerReminderCategory()
    }

    public func authorizationStatus() async -> VoxNotificationAuthorizationStatus {
        await center.authorizationStatus()
    }

    @discardableResult
    public func requestAuthorizationIfNeeded(allowProvisional: Bool = true) async throws -> VoxNotificationAuthorizationStatus {
        let current = await center.authorizationStatus()
        guard current == .notDetermined else { return current }
        return try await center.requestAuthorization(allowProvisional: allowProvisional)
    }

    @discardableResult
    public func schedule(_ item: VoxScheduledNotificationItem) async throws -> VoxScheduledNotificationItem {
        _ = try? await requestAuthorizationIfNeeded(allowProvisional: true)
        try await center.addNotificationRequest(item)
        scheduledByID.withLock { $0[item.itemID] = item }
        return item
    }

    @discardableResult
    public func scheduleUsingHabitAnchor(
        itemID: UUID,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        slot: HabitTimeSlot,
        dayOffset: Int = 0,
        tags: [String] = [],
        priority: VoxNotificationInterruptionPriority = .normal,
        now: Date = Date()
    ) async throws -> (item: VoxScheduledNotificationItem, anchor: ResolvedHabitTimeAnchor) {
        let anchor = timeAnchorLearner.resolveAnchor(
            for: slot,
            dayOffset: dayOffset,
            tags: tags,
            now: now
        )
        let item = VoxScheduledNotificationItem(
            itemID: itemID,
            title: title,
            subtitle: subtitle,
            body: body,
            fireDate: anchor.targetDate,
            slot: slot,
            tags: tags,
            priority: priority
        )
        let scheduled = try await schedule(item)
        return (scheduled, anchor)
    }

    @discardableResult
    public func rescheduleManualOverride(
        itemID: UUID,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        newFireDate: Date,
        slot: HabitTimeSlot? = nil,
        tags: [String] = [],
        priority: VoxNotificationInterruptionPriority = .normal
    ) async throws -> VoxScheduledNotificationItem {
        let comps = calendar.dateComponents([.hour, .minute], from: newFireDate)
        let minutes = (comps.hour ?? 9) * 60 + (comps.minute ?? 0)
        let effectiveSlot = slot ?? HabitTimeSlot.inferSlot(fromMinutesFromMidnight: minutes)
        _ = timeAnchorLearner.recordSignal(
            .manualOverride(newDate: newFireDate),
            for: effectiveSlot,
            tags: tags
        )
        let item = VoxScheduledNotificationItem(
            itemID: itemID,
            title: title,
            subtitle: subtitle,
            body: body,
            fireDate: newFireDate,
            slot: effectiveSlot,
            tags: tags,
            priority: priority
        )
        return try await schedule(item)
    }

    public func cancel(itemID: UUID) async {
        scheduledByID.withLock { _ = $0.removeValue(forKey: itemID) }
        let identifier = VoxScheduledNotificationItem.notificationIdentifier(for: itemID)
        await center.removeNotificationRequests(withIdentifiers: [identifier])
    }

    public func pendingItems() -> [VoxScheduledNotificationItem] {
        scheduledByID.withLock {
            Array($0.values).sorted { $0.fireDate < $1.fireDate }
        }
    }

    @discardableResult
    public func handleAction(
        identifier: String,
        itemID: UUID,
        slot: HabitTimeSlot? = nil,
        tags: [String] = [],
        now: Date = Date()
    ) async throws -> VoxNotificationActionEvent? {
        guard let quickAction = VoxNotificationQuickAction.parse(identifier) else {
            return nil
        }

        let existing = scheduledByID.withLock { $0[itemID] }
        let effectiveSlot = slot ?? existing?.slot
        let effectiveTags = tags.isEmpty ? (existing?.tags ?? []) : tags
        let previousFireDate = existing?.fireDate

        switch quickAction {
        case .markDone:
            await cancel(itemID: itemID)
            if let effectiveSlot {
                _ = timeAnchorLearner.recordSignal(
                    .completedNearNotification(completedAt: now),
                    for: effectiveSlot,
                    tags: effectiveTags
                )
            }
            let event = VoxNotificationActionEvent(
                itemID: itemID,
                action: .markDone,
                slot: effectiveSlot,
                tags: effectiveTags,
                previousFireDate: previousFireDate,
                rescheduledFireDate: nil,
                triggeredAt: now
            )
            continuation.yield(event)
            return event

        case .snooze15m, .snooze1h:
            let deltaSeconds: TimeInterval = (quickAction == .snooze15m) ? 15 * 60 : 60 * 60
            // 通知延后以用户在锁屏/手表点击按钮的当前时刻 `now` 为基准（若提醒尚未触发则取 `max(now, previousFireDate)`）
            let baseDate: Date
            if let previousFireDate, previousFireDate > now, previousFireDate.timeIntervalSince(now) <= 3600 {
                baseDate = previousFireDate
            } else {
                baseDate = now
            }
            let newFireDate = baseDate.addingTimeInterval(deltaSeconds)
            if let effectiveSlot {
                _ = timeAnchorLearner.recordSignal(
                    .snoozed(targetDate: newFireDate),
                    for: effectiveSlot,
                    tags: effectiveTags
                )
            }
            let updatedItem = (existing ?? VoxScheduledNotificationItem(
                itemID: itemID,
                title: "待办提醒",
                fireDate: newFireDate,
                slot: effectiveSlot,
                tags: effectiveTags
            )).withUpdatedFireDate(newFireDate, slot: effectiveSlot)
            _ = try await schedule(updatedItem)

            let event = VoxNotificationActionEvent(
                itemID: itemID,
                action: quickAction,
                slot: effectiveSlot,
                tags: effectiveTags,
                previousFireDate: previousFireDate,
                rescheduledFireDate: newFireDate,
                triggeredAt: now
            )
            continuation.yield(event)
            return event

        case .deferToNextAnchor:
            // 若当前小时 < 18，推迟到今日已学习的傍晚/晚上锚点；否则推迟到明早（.morning, dayOffset = 1）锚点
            let currentHour = calendar.component(.hour, from: now)
            let targetSlot: HabitTimeSlot
            let dayOffset: Int
            if currentHour < 18 {
                targetSlot = (effectiveSlot == .evening) ? .night : .evening
                dayOffset = 0
            } else {
                targetSlot = .morning
                dayOffset = 1
            }

            let resolvedAnchor = timeAnchorLearner.resolveAnchor(
                for: targetSlot,
                dayOffset: dayOffset,
                tags: effectiveTags,
                now: now
            )
            if let effectiveSlot {
                _ = timeAnchorLearner.recordSignal(
                    .snoozed(targetDate: resolvedAnchor.targetDate),
                    for: effectiveSlot,
                    tags: effectiveTags
                )
            }
            let updatedItem = (existing ?? VoxScheduledNotificationItem(
                itemID: itemID,
                title: "待办提醒",
                fireDate: resolvedAnchor.targetDate,
                slot: targetSlot,
                tags: effectiveTags
            )).withUpdatedFireDate(resolvedAnchor.targetDate, slot: targetSlot)
            _ = try await schedule(updatedItem)

            let event = VoxNotificationActionEvent(
                itemID: itemID,
                action: .deferToNextAnchor,
                slot: targetSlot,
                tags: effectiveTags,
                previousFireDate: previousFireDate,
                rescheduledFireDate: resolvedAnchor.targetDate,
                triggeredAt: now
            )
            continuation.yield(event)
            return event
        }
    }
}
