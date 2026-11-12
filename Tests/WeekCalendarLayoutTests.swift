import XCTest
@testable import CampusScheduleCore

final class WeekCalendarLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))! }
    private func event(_ id: String, from start: TimeInterval, to end: TimeInterval) -> CourseOccurrence {
        .init(id: id, calendarID: "test", title: id, start: monday.addingTimeInterval(start),
            end: monday.addingTimeInterval(end), location: "A302", notes: "")
    }

    func testWeekBoundariesAndExamReplacementArePreserved() {
        var snapshot = ScheduleSnapshot(now: monday)
        let lesson = event("lesson", from: 9 * 3600, to: 10 * 3600)
        snapshot.occurrences = [lesson, event("previous", from: -3600, to: 0),
            event("next", from: 7 * 86400, to: 7 * 86400 + 3600)]
        snapshot.upsertExam(.marking(lesson))
        let layout = WeekCalendarLayout(snapshot: snapshot, monday: monday, calendar: calendar)
        XCTAssertEqual(layout.days.count, 7)
        XCTAssertEqual(layout.events.count, 1)
        XCTAssertTrue(layout.events[0].isExam)
        XCTAssertEqual(layout.placements[monday]?.count, 1)
    }

    func testCrossMidnightEventAppearsOnBothDays() {
        var snapshot = ScheduleSnapshot(now: monday)
        snapshot.occurrences = [event("overnight", from: 23 * 3600, to: 25 * 3600)]
        let layout = WeekCalendarLayout(snapshot: snapshot, monday: monday, calendar: calendar)
        XCTAssertEqual(layout.placements[layout.days[0]]?.count, 1)
        XCTAssertEqual(layout.placements[layout.days[1]]?.count, 1)
        XCTAssertEqual(layout.placements[layout.days[2]]?.count, 0)
    }

    func testLayoutPreservesOverlapLanesAndUnusualClassTimes() {
        var snapshot = ScheduleSnapshot(now: monday)
        snapshot.occurrences = [event("first", from: 735 * 60, to: 795 * 60),
            event("overlap", from: 750 * 60, to: 780 * 60)]
        snapshot.todos = [.init(title: "in week", deadline: monday.addingTimeInterval(60)),
            .init(title: "completed", deadline: monday, isCompleted: true),
            .init(title: "next week", deadline: monday.addingTimeInterval(7 * 86400))]
        let layout = WeekCalendarLayout(snapshot: snapshot, monday: monday, calendar: calendar)
        XCTAssertEqual(layout.placements[monday]?.map(\.lanes), [2, 2])
        XCTAssertEqual(layout.scale.position(for: 795) - layout.scale.position(for: 735), 63, accuracy: 0.001)
        XCTAssertEqual(layout.deadlines.map(\.title), ["in week"])
    }
}
