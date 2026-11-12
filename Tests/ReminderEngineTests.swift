import XCTest
@testable import CampusScheduleCore

final class ReminderEngineTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    func date(_ day: Int = 11, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    func event(_ name: String, day: Int = 11, start: Int, end: Int, id: String = UUID().uuidString) -> CourseOccurrence {
        .init(id: id, calendarID: "school", title: name, start: date(day,start), end: date(day,end), location: "A302", notes: "")
    }
    func snapshot(_ events: [CourseOccurrence]) -> ScheduleSnapshot {
        var value = ScheduleSnapshot(now: date(11,9))
        value.occurrences = events
        value.registerCourses(events)
        return value
    }
    func state(_ value: ScheduleSnapshot, _ day: Int, _ hour: Int) -> ReminderState {
        ReminderEngine.state(snapshot: value, at: date(day,hour), calendar: calendar)
    }
    func state(_ value: ScheduleSnapshot, _ hour: Int) -> ReminderState { state(value, 11, hour) }

    func testCurrentCourseAndChronologicalNext() {
        let value = snapshot([event("英语",start:10,end:12), event("数学",start:8,end:10), event("程序设计",start:14,end:16)])
        let result = state(value,9)
        XCTAssertEqual(result.phase,.current)
        XCTAssertEqual(result.course?.title,"数学")
        XCTAssertEqual(result.next?.title,"英语")
    }
    func testBetweenCoursesShowsNextAndFollowing() {
        let value = snapshot([event("数学",start:8,end:9), event("英语",start:10,end:12),event("程序设计",start:14,end:16)])
        let result = state(value,9)
        XCTAssertEqual(result.phase,.upcoming)
        XCTAssertEqual(result.course?.title,"英语")
        XCTAssertEqual(result.next?.title,"程序设计")
    }
    func testCourseEndIsExclusive() {
        let value = snapshot([event("数学",start:8,end:10),event("英语",start:10,end:12)])
        XCTAssertEqual(state(value,10).course?.title,"英语")
    }
    func testCountdownTargetIsTheDisplayedUpcomingCourse() {
        let value = snapshot([event("数学",start:10,end:12),event("英语",start:14,end:16)])
        XCTAssertEqual(state(value,9).nextToStart?.title,"数学")
        XCTAssertEqual(state(value,13).nextToStart?.title,"英语")
    }
    func testCountdownAtStartSwitchesToFollowingCourseInsteadOfCountingUp() {
        let first = event("数学",start:10,end:12)
        let second = event("英语",start:14,end:16)
        let value = snapshot([first,second])
        let before = ReminderEngine.state(snapshot:value,at:first.start.addingTimeInterval(-1),calendar:calendar)
        let atStart = ReminderEngine.state(snapshot:value,at:first.start,calendar:calendar)
        XCTAssertEqual(before.phase,.upcoming)
        XCTAssertEqual(before.nextToStart?.id,first.id)
        XCTAssertEqual(atStart.phase,.current)
        XCTAssertEqual(atStart.nextToStart?.id,second.id)
    }
    func testCountdownTargetsFirstTomorrowCourseAfterTodayEnds() {
        let value = snapshot([event("数学",start:8,end:10),event("英语",day:12,start:10,end:12),event("物理",day:12,start:8,end:10)])
        XCTAssertEqual(state(value,18).nextToStart?.title,"物理")
    }
    func testNoCountdownDuringLastClassOrWhenThereAreNoCourses() {
        let value = snapshot([event("数学",start:8,end:10),event("英语",day:12,start:8,end:10)])
        XCTAssertNil(state(value,9).nextToStart)
        XCTAssertNil(state(snapshot([]),9).nextToStart)
    }
    func testLastCourseLeavesNextBlankEvenIfTomorrowHasClass() {
        let value = snapshot([event("数学",start:8,end:10),event("英语",day:12,start:8,end:10)])
        let result = state(value,9)
        XCTAssertEqual(result.phase,.current)
        XCTAssertNil(result.next)
        XCTAssertTrue(result.tomorrow.isEmpty)
    }
    func testAfterLastCourseShowsAllTomorrowCoursesInOrder() {
        let value = snapshot([event("数学",start:8,end:10),event("英语",day:12,start:10,end:12),event("物理",day:12,start:8,end:10)])
        let result = state(value,18)
        XCTAssertEqual(result.phase,.tomorrow)
        XCTAssertEqual(result.tomorrow.map(\.title),["物理","英语"])
        XCTAssertNil(result.course)
    }
    func testDayWithoutClassesCanShowTomorrow() {
        XCTAssertEqual(state(snapshot([event("数学",day:12,start:8,end:10)]),9).phase,.tomorrow)
    }
    func testEmptyAndFinishedStates() {
        XCTAssertEqual(state(snapshot([]),9).phase,.free)
        XCTAssertEqual(state(snapshot([event("数学",start:8,end:10)]),18).phase,.finished)
    }
    func testDeadlineWindowIncludesBoundaryAndOverdueButExcludesCompleted() {
        var value = snapshot([])
        value.todos = [
            .init(title:"逾期",deadline:date(10,9)),
            .init(title:"正好24小时",deadline:date(12,9)),
            .init(title:"更晚",deadline:date(12,10)),
            .init(title:"已完成",deadline:date(11,10),isCompleted:true),
            .init(title:"无截止时间")
        ]
        XCTAssertEqual(state(value,9).deadlines.map(\.title),["逾期","正好24小时"])
        value.settings.reminderHours = 1
        XCTAssertEqual(state(value,9).deadlines.map(\.title),["逾期"])
    }
    func testTimelineIncludesCourseBoundariesMidnightAndDeadlineThreshold() {
        var value = snapshot([event("数学",start:10,end:12)])
        value.todos = [.init(title:"报告",deadline:date(12,11))]
        let dates = ReminderEngine.timelineDates(snapshot:value,now:date(11,9),calendar:calendar)
        for expected in [date(11,10),date(11,11),date(11,12),date(12,0),date(12,11)] {
            XCTAssertTrue(dates.contains(expected))
        }
        XCTAssertEqual(dates,Array(Set(dates)).sorted())
    }
    func testCourseIDAndTeacherSurviveResyncAndDifferentDates() {
        let first = event("数学",start:8,end:10)
        var value = snapshot([first])
        let original = value.profiles[0].shortID
        value.profiles[0].teacher = "王老师"
        value.registerCourses([event("数学",day:18,start:10,end:12)])
        XCTAssertEqual(value.profiles.count,1)
        XCTAssertEqual(value.profiles[0].shortID,original)
        XCTAssertEqual(value.profiles[0].teacher,"王老师")
    }
    func testIDsHaveFiveUniqueCharactersAndDoNotMergeCourseVariants() {
        let events = (0..<500).map { event("课程\($0)",start:8,end:10) }
        let value = snapshot(events)
        XCTAssertEqual(Set(value.profiles.map(\.shortID)).count,500)
        XCTAssertTrue(value.profiles.allSatisfy { $0.shortID.count == 5 })
        XCTAssertNotEqual(CourseProfile.key(calendarID:"a",title:"体育（1）"),CourseProfile.key(calendarID:"a",title:"体育（2）"))
        XCTAssertNotEqual(CourseProfile.key(calendarID:"a",title:"数学"),CourseProfile.key(calendarID:"b",title:"数学"))
    }
    func testMondayStartsWeekAndSundayBelongsToSameWeek() {
        XCTAssertEqual(ScheduleFormat.monday(containing:date(15,18),calendar:calendar),date(9,0))
    }
    func testOverlapsGetSeparateLanesAndAdjacentCoursesReuseOneLane() {
        let layout = CalendarPlacement.layout([event("A",start:8,end:10),event("B",start:9,end:11),event("C",start:11,end:12)])
        XCTAssertEqual(layout.map(\.lanes),[2,2,1])
        XCTAssertNotEqual(layout[0].lane,layout[1].lane)
    }
    func testPeriodLabelsUseBothTimeBoundaries() {
        let e = CourseOccurrence(id:"a",calendarID:"a",title:"数学",start:date(11,10,10),end:date(11,11,50),location:"",notes:"")
        XCTAssertEqual(ScheduleFormat.periodLabel(e,periods:LessonPeriod.defaults,calendar:calendar),"第 3–4 节")
    }
    func testPersistenceRoundTripAndBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let repository = SharedRepository(fileURL:folder.appendingPathComponent("snapshot.json"))
        var value = snapshot([event("数学",start:8,end:10)])
        value.todos = [.init(title:"报告",deadline:date(18,20),isPinned:true)]
        try repository.save(value)
        XCTAssertEqual(try repository.load(),value)
        value.profiles[0].teacher = "王老师"
        try repository.save(value)
        XCTAssertTrue(FileManager.default.fileExists(atPath:repository.fileURL.appendingPathExtension("backup").path))
        XCTAssertEqual(try repository.load()?.profiles[0].teacher,"王老师")
    }
    func testJanuaryDefaultsToPreviousAutumn() {
        let january = calendar.date(from:DateComponents(year:2027,month:1,day:10))!
        let settings = ScheduleSettings(now:january,calendar:calendar)
        XCTAssertEqual(calendar.component(.year,from:settings.semesterStart),2026)
        XCTAssertEqual(calendar.component(.month,from:settings.semesterStart),8)
    }
    func testDisplayedTimesAlwaysPadMinutesToTwoDigits() {
        XCTAssertEqual(String(ScheduleFormat.time(date(11,8)).suffix(3)),":00")
        XCTAssertEqual(String(ScheduleFormat.time(date(11,8,5)).suffix(3)),":05")
    }
    func testTomorrowUsesCalendarDaysAcrossDST() {
        var cal = Calendar(identifier:.gregorian)
        cal.timeZone = TimeZone(identifier:"America/New_York")!
        let now = cal.date(from:DateComponents(year:2026,month:3,day:7,hour:23))!
        let start = cal.date(from:DateComponents(year:2026,month:3,day:8,hour:9))!
        let e = CourseOccurrence(id:"dst",calendarID:"a",title:"数学",start:start,end:start.addingTimeInterval(3600),location:"",notes:"")
        XCTAssertEqual(ReminderEngine.state(snapshot:snapshot([e]),at:now,calendar:cal).tomorrow.count,1)
    }
}
