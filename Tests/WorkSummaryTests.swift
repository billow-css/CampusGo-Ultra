import XCTest
@testable import CampusScheduleCore

final class WorkSummaryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testCompletedItemsDoNotAppearOnDashboard() {
        var value = ScheduleSnapshot(now: now)
        value.todos = [.init(title: "done", deadline: now, isCompleted: true)]
        value.homework = [.init(number: "H1234", courseKey: "c", title: "done", deadline: now, isManuallyCompleted: true)]
        let result = WorkSummary(snapshot: value, now: now)
        XCTAssertEqual(result.pendingTodos, 0); XCTAssertEqual(result.pendingHomework, 0)
        XCTAssertNil(result.nextTodo); XCTAssertNil(result.nextHomework)
    }
    func testActualOverdueDeadlineTakesPriorityOverOldSchedule() {
        var value = ScheduleSnapshot(now: now)
        value.todos = [.init(title: "old schedule", scheduledAt: now.addingTimeInterval(-86400), deadline: now.addingTimeInterval(86400)),
            .init(title: "overdue", deadline: now.addingTimeInterval(-60))]
        let result = WorkSummary(snapshot: value, now: now)
        XCTAssertEqual(result.nextTodo?.title, "overdue")
        XCTAssertEqual(result.overdueTodos, 1)
    }
    func testEarlierOfScheduleAndDeadlineDeterminesNextItem() {
        var value = ScheduleSnapshot(now: now)
        value.todos = [.init(title: "first", scheduledAt: now.addingTimeInterval(5*3600), deadline: now.addingTimeInterval(3600)),
            .init(title: "second", scheduledAt: now.addingTimeInterval(2*3600))]
        XCTAssertEqual(WorkSummary(snapshot: value, now: now).nextTodo?.title, "first")
    }
    func testUndatedPinnedItemsAreChosenFirst() {
        var value = ScheduleSnapshot(now: now)
        value.todos = [.init(title: "normal"), .init(title: "pinned", isPinned: true)]
        value.homework = [.init(courseKey: "c", title: "normal"), .init(courseKey: "c", title: "pinned", isPinned: true)]
        let result = WorkSummary(snapshot: value, now: now)
        XCTAssertEqual(result.nextTodo?.title, "pinned")
        XCTAssertEqual(result.nextHomework?.title, "pinned")
    }
    func testTodayCountCountsEachTaskOnlyOnce() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: now)
        var value = ScheduleSnapshot(now: now)
        value.todos = [.init(title: "same day", scheduledAt: day.addingTimeInterval(3600), deadline: day.addingTimeInterval(7200)),
            .init(title: "tomorrow", deadline: day.addingTimeInterval(86400)), .init(title: "undated")]
        XCTAssertEqual(WorkSummary(snapshot: value, now: now, calendar: calendar).todayTodos, 1)
    }
    func testHomeworkUrgencyAndTwentyFourHourBoundary() {
        var value = ScheduleSnapshot(now: now)
        value.homework = [.init(courseKey: "c", title: "late", deadline: now.addingTimeInterval(-1)),
            .init(courseKey: "c", title: "now", deadline: now),
            .init(courseKey: "c", title: "boundary", deadline: now.addingTimeInterval(86400)),
            .init(courseKey: "c", title: "later", deadline: now.addingTimeInterval(86401))]
        let result = WorkSummary(snapshot: value, now: now)
        XCTAssertEqual(result.pendingHomework, 4)
        XCTAssertEqual(result.upcomingHomework, 2)
        XCTAssertEqual(result.overdueHomework, 1)
        XCTAssertEqual(result.nextHomework?.title, "late")
    }
    func testCompletedSubtasksRemoveHomeworkFromDashboard() {
        var value = ScheduleSnapshot(now: now)
        value.homework = [.init(courseKey: "c", title: "done", items: [.init(title: "one", isCompleted: true)]),
            .init(courseKey: "c", title: "pending", items: [.init(title: "two")])]
        let result = WorkSummary(snapshot: value, now: now)
        XCTAssertEqual(result.pendingHomework, 1)
        XCTAssertEqual(result.nextHomework?.title, "pending")
    }
}
