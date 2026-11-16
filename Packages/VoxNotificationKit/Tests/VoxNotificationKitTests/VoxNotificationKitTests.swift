import XCTest
@testable import VoxNotificationKit

final class VoxNotificationKitTests: XCTestCase {
    private var fixedCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return cal
    }

    private func makeDate(year: Int = 2026, month: Int = 11, day: Int = 16, hour: Int, minute: Int) -> Date {
        let cal = fixedCalendar
        let comps = DateComponents(
            timeZone: cal.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        )
        return cal.date(from: comps)!
    }

    func testColdStartDefaultAnchorsAndSmartNextDayRollover() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-habit-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = FileHabitTimeAnchorStore(fileURL: tempURL)
        let learner = AdaptiveTimeAnchorLearner(store: store, calendar: fixedCalendar)

        // Expected cold-start default minutes: 09:00, 10:00, 12:30, 15:00, 18:30, 20:30
        XCTAssertEqual(HabitTimeSlot.morning.defaultMinutesFromMidnight, 540)
        XCTAssertEqual(HabitTimeSlot.forenoon.defaultMinutesFromMidnight, 600)
        XCTAssertEqual(HabitTimeSlot.noon.defaultMinutesFromMidnight, 750)
        XCTAssertEqual(HabitTimeSlot.afternoon.defaultMinutesFromMidnight, 900)
        XCTAssertEqual(HabitTimeSlot.evening.defaultMinutesFromMidnight, 1110)
        XCTAssertEqual(HabitTimeSlot.night.defaultMinutesFromMidnight, 1230)

        // At 07:30, resolving .morning (dayOffset=0) schedules today at 09:00 without rollover
        let earlyNow = makeDate(hour: 7, minute: 30)
        let todayMorning = learner.resolveAnchor(for: .morning, dayOffset: 0, tags: ["#快递"], now: earlyNow)
        XCTAssertEqual(todayMorning.source, .coldStartDefault)
        XCTAssertEqual(todayMorning.hour, 9)
        XCTAssertEqual(todayMorning.minute, 0)
        XCTAssertFalse(todayMorning.didRollOverToNextDay)
        XCTAssertEqual(fixedCalendar.component(.day, from: todayMorning.targetDate), 16)

        // At 21:35, resolving .morning (dayOffset=0) automatically rolls over to tomorrow (17th) at 09:00
        let nightNow = makeDate(hour: 21, minute: 35)
        let rolledMorning = learner.resolveAnchor(for: .morning, dayOffset: 0, tags: ["#快递"], now: nightNow)
        XCTAssertEqual(rolledMorning.hour, 9)
        XCTAssertEqual(rolledMorning.minute, 0)
        XCTAssertTrue(rolledMorning.didRollOverToNextDay)
        XCTAssertEqual(fixedCalendar.component(.day, from: rolledMorning.targetDate), 17)
    }

    func testTwoLevelGlobalPlusTagEmpiricalBayesConvergenceAndPersistence() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-habit-two-level-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = FileHabitTimeAnchorStore(fileURL: tempURL)
        let learner = AdaptiveTimeAnchorLearner(store: store, calendar: fixedCalendar)

        // User overrides #快递 morning reminder to 08:30 three times
        let override830 = makeDate(hour: 8, minute: 30)
        _ = learner.recordSignal(.manualOverride(newDate: override830), for: .morning, tags: ["#快递"])
        _ = learner.recordSignal(.manualOverride(newDate: override830), for: .morning, tags: ["快递"])
        let afterThree = learner.recordSignal(.manualOverride(newDate: override830), for: .morning, tags: ["#快递"])

        XCTAssertEqual(afterThree.source, .tagContextualLearned)
        XCTAssertEqual(afterThree.matchedTag, "快递")
        // Converged from 540 (09:00) toward 510 (08:30), aligned to 5-minute grid
        XCTAssertLessThanOrEqual(afterThree.minutesFromMidnight, 520)
        XCTAssertGreaterThanOrEqual(afterThree.minutesFromMidnight, 510)

        // Reload from disk to verify persistence in time-anchor-habits.json
        let reloadedLearner = AdaptiveTimeAnchorLearner(store: store, calendar: fixedCalendar)
        let resolvedFromDisk = reloadedLearner.resolveAnchor(
            for: .morning,
            dayOffset: 1,
            tags: ["#快递"],
            now: makeDate(hour: 20, minute: 0)
        )
        XCTAssertEqual(resolvedFromDisk.source, .tagContextualLearned)
        XCTAssertEqual(resolvedFromDisk.minutesFromMidnight, afterThree.minutesFromMidnight)

        // Unrelated tag (#读书) falls back to globalSlotLearned (which has higher shrinkage toward 09:00 than #快递)
        let unrelatedTagAnchor = reloadedLearner.resolveAnchor(
            for: .morning,
            dayOffset: 1,
            tags: ["#读书"],
            now: makeDate(hour: 20, minute: 0)
        )
        XCTAssertEqual(unrelatedTagAnchor.source, .globalSlotLearned)
        XCTAssertNil(unrelatedTagAnchor.matchedTag)
    }

    func testWinsorizedClampingProtectsAgainstMidnightOutlier() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-habit-outlier-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = FileHabitTimeAnchorStore(fileURL: tempURL)
        let learner = AdaptiveTimeAnchorLearner(store: store, calendar: fixedCalendar)

        // Accidental completion at 02:10 AM (130 min from midnight) for a .morning task
        let accidental2AM = makeDate(hour: 2, minute: 10)
        let resolved = learner.recordSignal(
            .completedNearNotification(completedAt: accidental2AM),
            for: .morning,
            tags: ["#快递"]
        )

        // Must never drop below .morning.validMinuteRange.lowerBound (05:30 = 330m), and single completion moves gently
        XCTAssertGreaterThanOrEqual(resolved.minutesFromMidnight, HabitTimeSlot.morning.validMinuteRange.lowerBound)
        XCTAssertGreaterThanOrEqual(resolved.minutesFromMidnight, 490)
    }

    func testAllFourQuickActionsUpdateScheduleAndFeedHabitLearner() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-scheduler-actions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = FileHabitTimeAnchorStore(fileURL: tempURL)
        let learner = AdaptiveTimeAnchorLearner(store: store, calendar: fixedCalendar)
        let center = InMemoryVoxNotificationCenter()
        let scheduler = VoxNotificationScheduler(
            timeAnchorLearner: learner,
            center: center,
            calendar: fixedCalendar
        )

        await scheduler.registerCategories()
        let auth = await scheduler.authorizationStatus()
        XCTAssertEqual(auth, .authorized)

        // Verify all 4 actions exist on VoxNotificationQuickAction
        XCTAssertEqual(
            VoxNotificationQuickAction.allCases.map(\.rawValue),
            [
                "vox.notification.action.markDone",
                "vox.notification.action.snooze15m",
                "vox.notification.action.snooze1h",
                "vox.notification.action.deferToNextAnchor"
            ]
        )

        let todoID = UUID()
        let morningNow = makeDate(hour: 8, minute: 0)
        let (scheduled, initialAnchor) = try await scheduler.scheduleUsingHabitAnchor(
            itemID: todoID,
            title: "取顺丰快递",
            subtitle: "#快递",
            slot: .morning,
            dayOffset: 0,
            tags: ["#快递"],
            priority: .high,
            now: morningNow
        )
        XCTAssertEqual(initialAnchor.minutesFromMidnight, 540)
        XCTAssertFalse(initialAnchor.didRollOverToNextDay)
        XCTAssertEqual(scheduler.pendingItems().count, 1)
        XCTAssertEqual(scheduled.title, "取顺丰快递")

        // Action 1: snooze15m at 09:00 -> reschedules to 09:15 and records snooze signal
        let nineAM = makeDate(day: 16, hour: 9, minute: 0)
        let rawSnooze15 = try await scheduler.handleAction(
            identifier: VoxNotificationQuickAction.snooze15m.rawValue,
            itemID: todoID,
            slot: .morning,
            tags: ["#快递"],
            now: nineAM
        )
        let snooze15Event = try XCTUnwrap(rawSnooze15)
        XCTAssertEqual(snooze15Event.action, .snooze15m)
        XCTAssertEqual(snooze15Event.rescheduledFireDate, nineAM.addingTimeInterval(15 * 60))

        // Action 2: snooze1h at 09:15 -> reschedules to 10:15 and shifts morning habit anchor later
        let nineFifteen = makeDate(day: 16, hour: 9, minute: 15)
        let rawSnooze1h = try await scheduler.handleAction(
            identifier: VoxNotificationQuickAction.snooze1h.rawValue,
            itemID: todoID,
            slot: .morning,
            tags: ["#快递"],
            now: nineFifteen
        )
        let snooze1hEvent = try XCTUnwrap(rawSnooze1h)
        XCTAssertEqual(snooze1hEvent.action, .snooze1h)
        XCTAssertEqual(snooze1hEvent.rescheduledFireDate, nineFifteen.addingTimeInterval(60 * 60))
        let shiftedMorning = learner.resolveAnchor(for: .morning, dayOffset: 1, tags: ["#快递"], now: nineFifteen)
        XCTAssertGreaterThan(shiftedMorning.minutesFromMidnight, 540)

        // Action 3: deferToNextAnchor before 18:00 (at 10:15) -> defers to today's .evening anchor (18:30)
        let tenFifteen = makeDate(day: 16, hour: 10, minute: 15)
        let rawDeferEvening = try await scheduler.handleAction(
            identifier: VoxNotificationQuickAction.deferToNextAnchor.rawValue,
            itemID: todoID,
            slot: .morning,
            tags: ["#快递"],
            now: tenFifteen
        )
        let deferEveningEvent = try XCTUnwrap(rawDeferEvening)
        XCTAssertEqual(deferEveningEvent.action, .deferToNextAnchor)
        XCTAssertEqual(deferEveningEvent.slot, .evening)
        let deferredEveningDate = try XCTUnwrap(deferEveningEvent.rescheduledFireDate)
        XCTAssertEqual(fixedCalendar.component(.day, from: deferredEveningDate), 16)
        XCTAssertEqual(fixedCalendar.component(.hour, from: deferredEveningDate), 18)
        XCTAssertEqual(fixedCalendar.component(.minute, from: deferredEveningDate), 30)

        // Action 3b: deferToNextAnchor after 18:00 (at 19:00) -> defers to tomorrow's .morning anchor
        let sevenPM = makeDate(day: 16, hour: 19, minute: 0)
        let rawDeferMorning = try await scheduler.handleAction(
            identifier: VoxNotificationQuickAction.deferToNextAnchor.rawValue,
            itemID: todoID,
            slot: .evening,
            tags: ["#快递"],
            now: sevenPM
        )
        let deferMorningEvent = try XCTUnwrap(rawDeferMorning)
        XCTAssertEqual(deferMorningEvent.action, .deferToNextAnchor)
        XCTAssertEqual(deferMorningEvent.slot, .morning)
        let deferredMorningDate = try XCTUnwrap(deferMorningEvent.rescheduledFireDate)
        XCTAssertEqual(fixedCalendar.component(.day, from: deferredMorningDate), 17)

        // Action 4: markDone -> removes pending notification and emits markDone event
        let rawMarkDone = try await scheduler.handleAction(
            identifier: VoxNotificationQuickAction.markDone.rawValue,
            itemID: todoID,
            slot: .morning,
            tags: ["#快递"],
            now: makeDate(day: 17, hour: 9, minute: 20)
        )
        let markDoneEvent = try XCTUnwrap(rawMarkDone)
        XCTAssertEqual(markDoneEvent.action, .markDone)
        XCTAssertNil(markDoneEvent.rescheduledFireDate)
        XCTAssertTrue(scheduler.pendingItems().isEmpty)
        XCTAssertTrue(center.storedRequests().isEmpty)
    }
}
