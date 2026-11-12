import XCTest
@testable import CampusScheduleCore

final class ExamTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    private func course(_ day: Int, id: String = UUID().uuidString) -> CourseOccurrence {
        .init(id: id, calendarID: "school", title: "软件工程", start: date(day), end: date(day,12), location: "C404", notes: "课程备注")
    }
    private func snapshot(_ events: [CourseOccurrence] = []) -> ScheduleSnapshot {
        var value = ScheduleSnapshot(now: date(11))
        value.occurrences = events
        value.registerCourses(events)
        return value
    }
    private func state(_ value: ScheduleSnapshot, now: Date) -> ReminderState {
        ReminderEngine.state(snapshot: value, at: now, calendar: calendar)
    }

    func testMarkingOnlyReplacesOneOccurrenceAndKeepsCourseIDAndTeacher() {
        let first = course(11), second = course(18)
        var value = snapshot([first,second])
        let shortID = value.profiles[0].shortID
        value.profiles[0].teacher = "王老师"
        XCTAssertTrue(value.upsertExam(.marking(first)))
        XCTAssertEqual(value.schedule.count, 2)
        XCTAssertEqual(value.schedule.filter(\.isExam).count, 1)
        XCTAssertTrue(value.schedule.contains { $0.id == second.id && !$0.isExam })
        XCTAssertEqual(value.profile(for: value.schedule[0])?.shortID, shortID)
        XCTAssertEqual(value.profile(for: value.schedule[0])?.teacher, "王老师")
    }
    func testCancellingMarkRestoresOriginalCourseExactly() {
        let original = course(11)
        var value = snapshot([original])
        let exam = ExamRecord.marking(original)
        value.upsertExam(exam)
        value.removeExam(exam.id)
        XCTAssertEqual(value.schedule, [original])
    }
    func testManualExamCreatesProfileAndAppearsOnItsActualDate() {
        var value = snapshot()
        let exam = ExamRecord(title: "线性代数期末考试", start: date(18), end: date(18,12), location: "A201")
        value.upsertExam(exam)
        XCTAssertEqual(value.schedule.count, 1)
        XCTAssertTrue(value.schedule[0].isExam)
        XCTAssertEqual(value.schedule[0].start, date(18))
        XCTAssertEqual(value.profile(for: value.schedule[0])?.shortID.count, 5)
    }
    func testManualExamCanUseExistingCourseMetadata() {
        let original = course(11)
        var value = snapshot([original])
        value.upsertExam(.init(title: "软件工程期中考试", start: date(16), end: date(16,12), linkedCourseKey: original.courseKey))
        XCTAssertEqual(value.profiles.count, 1)
        XCTAssertEqual(value.schedule.filter(\.isExam).first?.courseKey, original.courseKey)
    }
    func testMarkSurvivesCalendarRefreshWithChangedEventIdentifier() {
        let first = course(11)
        var value = snapshot([first])
        value.upsertExam(.marking(first))
        value.occurrences = [course(11,id:"refreshed-id")]
        XCTAssertEqual(value.schedule.count, 1)
        XCTAssertTrue(value.schedule[0].isExam)
    }
    func testExamEditsPersistWithoutLeavingOriginalCourseBehind() throws {
        let original = course(11)
        var value = snapshot([original])
        var exam = ExamRecord.marking(original)
        value.upsertExam(exam)
        exam.start = date(12); exam.end = date(12,12); exam.location = "考试楼B102"
        value.upsertExam(exam)
        let loaded = try JSONDecoder().decode(ScheduleSnapshot.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(loaded.examRecords.count, 1)
        XCTAssertEqual(loaded.schedule.count, 1)
        XCTAssertEqual(loaded.schedule[0].start, date(12))
        XCTAssertEqual(loaded.schedule[0].location, "考试楼B102")
    }
    func testInvalidExamsAreNotSaved() {
        var value = snapshot()
        XCTAssertFalse(value.upsertExam(.init(title:"   ",start:date(12),end:date(12,12))))
        XCTAssertFalse(value.upsertExam(.init(title:"考试",start:date(12),end:date(12))))
        XCTAssertFalse(value.upsertExam(.init(title:"考试",start:date(12),end:date(11))))
        XCTAssertTrue(value.examRecords.isEmpty)
    }
    func testSevenDayReminderIncludesExactBoundaryButNotLaterExams() {
        var value = snapshot()
        value.upsertExam(.init(title:"边界考试",start:date(18),end:date(18,12)))
        value.upsertExam(.init(title:"更晚考试",start:date(18).addingTimeInterval(1),end:date(18,12)))
        value.upsertExam(.init(title:"已结束考试",start:date(10),end:date(10,12)))
        XCTAssertEqual(state(value,now:date(11)).upcomingExams.map(\.title), ["边界考试"])
    }
    func testExamNextIsMarkedAndUsesCountdownTarget() {
        var value = snapshot()
        value.upsertExam(.init(title:"考试",start:date(11,15),end:date(11,17)))
        let result = state(value,now:date(11,14))
        XCTAssertEqual(result.phase,.upcoming)
        XCTAssertTrue(result.course?.isExam == true)
        XCTAssertEqual(result.nextToStart?.start,date(11,15))
    }
    func testOngoingExamHasCurrentStateAndIsNotRepeatedInAdvanceNotice() {
        var value = snapshot()
        value.upsertExam(.init(title:"考试",start:date(11),end:date(11,12)))
        let result = state(value,now:date(11,11))
        XCTAssertEqual(result.phase,.current)
        XCTAssertTrue(result.course?.isExam == true)
        XCTAssertTrue(result.upcomingExams.isEmpty)
    }
    func testExamTakesPriorityWhenItStartsTogetherWithNormalCourse() {
        var value = snapshot([course(11)])
        value.upsertExam(.init(title:"独立考试",start:date(11),end:date(11,12)))
        XCTAssertTrue(state(value,now:date(11)).course?.isExam == true)
    }
    func testWidgetTimelineIncludesSevenDayReminderThresholdAndExamStart() {
        var value = snapshot()
        let examStart = date(19)
        value.upsertExam(.init(title:"考试",start:examStart,end:date(19,12)))
        let threshold = calendar.date(byAdding:.day,value:-7,to:examStart)!
        XCTAssertTrue(ReminderEngine.timelineDates(snapshot:value,now:date(11),calendar:calendar).contains(threshold))
        XCTAssertTrue(ReminderEngine.timelineDates(snapshot:value,now:date(19,9),calendar:calendar).contains(examStart))
    }
    func testOldSnapshotsDecodeWithoutExamFields() throws {
        let value = snapshot([course(11)])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String:Any]
        json.removeValue(forKey:"exams")
        let decoded = try JSONDecoder().decode(ScheduleSnapshot.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertTrue(decoded.examRecords.isEmpty)
        XCTAssertEqual(decoded.schedule.count,1)
        XCTAssertFalse(decoded.schedule[0].isExam)
    }
}
