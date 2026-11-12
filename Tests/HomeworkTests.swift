import XCTest
@testable import CampusScheduleCore

final class HomeworkTests: XCTestCase {
    private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private func snapshot() -> ScheduleSnapshot {
        var value = ScheduleSnapshot(now: now)
        value.profiles = [.init(id: "course", title: "程序设计", shortID: "AB234")]
        return value
    }
    private func assignment(items: [HomeworkSubtask] = [], deadline: Date? = nil) -> HomeworkAssignment {
        .init(courseKey: "course", title: "第五周作业", deadline: deadline, items: items)
    }

    func testNumberFormatIncludesBothBoundsAndRejectsInvalidIDs() {
        for number in ["H0000", "H9999", "H0123"] { XCTAssertTrue(HomeworkAssignment.isValidNumber(number)) }
        for number in ["h0000", "H00000", "H123", "H１２３４", "X0000", "HABCD"] {
            XCTAssertFalse(HomeworkAssignment.isValidNumber(number))
        }
    }

    func testNearlyExhaustedAllocatorFindsOnlyFreeNumber() {
        var used = Set((0..<10_000).map { String(format: "H%04d", $0) })
        used.remove("H0123")
        XCTAssertEqual(HomeworkAssignment.newNumber(excluding: used), "H0123")
        used.insert("H0123")
        XCTAssertNil(HomeworkAssignment.newNumber(excluding: used))
    }

    func testMultipleAssignmentsHaveUniqueNumbers() throws {
        var value = snapshot()
        for _ in 0..<100 { try value.upsertHomework(assignment()) }
        XCTAssertEqual(Set(value.homeworkRecords.map(\.number)).count, 100)
        XCTAssertTrue(value.homeworkRecords.allSatisfy { HomeworkAssignment.isValidNumber($0.number) })
        XCTAssertTrue(value.todos.isEmpty)
    }

    func testEditingPreservesNumberAndCreationDate() throws {
        var value = snapshot()
        try value.upsertHomework(assignment())
        let original = value.homeworkRecords[0]
        var edited = original
        edited.number = "invalid"
        edited.title = "新的作业标题"
        edited.createdAt = now.addingTimeInterval(900)
        try value.upsertHomework(edited)
        XCTAssertEqual(value.homeworkRecords[0].number, original.number)
        XCTAssertEqual(value.homeworkRecords[0].createdAt, original.createdAt)
        XCTAssertEqual(value.homeworkRecords.count, 1)
    }

    func testDeletedNumbersRemainReservedAndCapacityDoesNotPreventEditing() throws {
        var value = snapshot()
        try value.upsertHomework(assignment())
        let original = value.homeworkRecords[0]
        value.usedHomeworkNumbers = (0..<10_000).map { String(format: "H%04d", $0) }
        var edited = original
        edited.title = "仍可编辑"
        XCTAssertNoThrow(try value.upsertHomework(edited))
        value.removeHomework(original.id)
        XCTAssertTrue(value.usedHomeworkNumbers!.contains(original.number))
        XCTAssertThrowsError(try value.upsertHomework(assignment()))
        XCTAssertTrue(value.homeworkRecords.isEmpty)
        XCTAssertTrue(value.hasUserData)
    }

    func testExistingCourseIDCannotCollideWithHomeworkNumber() throws {
        var value = snapshot()
        value.profiles[0].shortID = "H1234"
        value.usedHomeworkNumbers = (0..<10_000).filter { $0 != 1234 && $0 != 5678 }.map { String(format: "H%04d", $0) }
        try value.upsertHomework(assignment())
        XCTAssertEqual(value.homeworkRecords[0].number, "H5678")
    }

    func testAllChildrenCompleteParentAndReopeningChildRestoresDeadline() throws {
        var value = snapshot()
        let item = assignment(items: [.init(title: "第一题"), .init(title: "报告")], deadline: now)
        try value.upsertHomework(item)
        value.toggleHomeworkSubtask(item.items[0].id, in: item.id)
        XCTAssertFalse(value.homeworkRecords[0].isCompleted)
        XCTAssertEqual(value.homeworkRecords[0].completedCount, 1)
        value.toggleHomeworkSubtask(item.items[1].id, in: item.id)
        XCTAssertTrue(value.homeworkRecords[0].isCompleted)
        XCTAssertTrue(value.pendingDeadlines.isEmpty)
        value.toggleHomeworkSubtask(item.items[0].id, in: item.id)
        XCTAssertFalse(value.homeworkRecords[0].isCompleted)
        XCTAssertEqual(value.pendingDeadlines.count, 1)
    }

    func testParentToggleCompletesAndReopensAllChildren() throws {
        var value = snapshot()
        let item = assignment(items: [.init(title: "第一题"), .init(title: "第二题")])
        try value.upsertHomework(item)
        value.toggleHomework(item.id)
        XCTAssertTrue(value.homeworkRecords[0].items.allSatisfy(\.isCompleted))
        value.toggleHomework(item.id)
        XCTAssertTrue(value.homeworkRecords[0].items.allSatisfy { !$0.isCompleted })
    }

    func testSimpleHomeworkCanBeCompletedWithoutChildrenOrDeadline() throws {
        var value = snapshot()
        let item = assignment()
        try value.upsertHomework(item)
        XCTAssertTrue(value.pendingDeadlines.isEmpty)
        value.toggleHomework(item.id)
        XCTAssertTrue(value.homeworkRecords[0].isCompleted)
        value.toggleHomework(item.id)
        XCTAssertFalse(value.homeworkRecords[0].isCompleted)
    }

    func testValidationDoesNotReserveNumberOrModifySnapshotOnFailure() {
        var value = snapshot()
        let before = value
        var invalid = assignment()
        invalid.title = "  "
        XCTAssertThrowsError(try value.upsertHomework(invalid))
        invalid = assignment(items: [.init(title: " ")])
        XCTAssertThrowsError(try value.upsertHomework(invalid))
        invalid = assignment()
        invalid.courseKey = "missing"
        XCTAssertThrowsError(try value.upsertHomework(invalid))
        XCTAssertEqual(value, before)
    }

    func testOldSnapshotDecodesWithoutHomeworkFieldsAndNewSnapshotRoundTrips() throws {
        let old = try JSONEncoder().encode(snapshot())
        var value = try SharedRepository.decodeBackup(old)
        XCTAssertTrue(value.homeworkRecords.isEmpty)
        try value.upsertHomework(assignment(items: [.init(title: "报告")], deadline: now))
        let restored = try SharedRepository.decodeBackup(JSONEncoder().encode(value))
        XCTAssertEqual(value, restored)
        XCTAssertEqual(restored.homeworkRecords[0].number, value.homeworkRecords[0].number)
    }

    func testHomeworkOnlySnapshotIsProtectedFromBackupOverwrite() {
        var value = ScheduleSnapshot(now: now)
        value.homework = [assignment()]
        XCTAssertTrue(value.hasUserData)
    }

    func testHomeworkDeadlineAppearsInCorrectWeekAndCarriesNumber() throws {
        var value = snapshot()
        let monday = ScheduleFormat.monday(containing: now)
        let nextMonday = Calendar.current.date(byAdding: .day, value: 7, to: monday)!
        try value.upsertHomework(assignment(deadline: nextMonday.addingTimeInterval(3600)))
        XCTAssertTrue(WeekCalendarLayout(snapshot: value, monday: monday).deadlines.isEmpty)
        let deadlines = WeekCalendarLayout(snapshot: value, monday: nextMonday).deadlines
        XCTAssertEqual(deadlines.count, 1)
        XCTAssertEqual(deadlines[0].homeworkNumber, value.homeworkRecords[0].number)
        XCTAssertTrue(deadlines[0].displayTitle.hasPrefix("#H"))
    }

    func testReminderThresholdOverdueAndCompletedHomework() throws {
        var value = snapshot()
        try value.upsertHomework(assignment(deadline: now.addingTimeInterval(36 * 3600)))
        XCTAssertTrue(ReminderEngine.state(snapshot: value, at: now).deadlines.isEmpty)
        XCTAssertEqual(ReminderEngine.state(snapshot: value, at: now.addingTimeInterval(12 * 3600)).deadlines.count, 1)
        XCTAssertEqual(ReminderEngine.state(snapshot: value, at: now.addingTimeInterval(48 * 3600)).deadlines.count, 1)
        value.toggleHomework(value.homeworkRecords[0].id)
        XCTAssertTrue(ReminderEngine.state(snapshot: value, at: now.addingTimeInterval(48 * 3600)).deadlines.isEmpty)
    }

    func testWidgetTimelineIncludesHomeworkThresholdAndDueDate() throws {
        var value = snapshot()
        let due = now.addingTimeInterval(36 * 3600)
        try value.upsertHomework(assignment(deadline: due))
        let dates = ReminderEngine.timelineDates(snapshot: value, now: now)
        XCTAssertTrue(dates.contains(due))
        XCTAssertTrue(dates.contains(due.addingTimeInterval(-24 * 3600)))
    }
}
