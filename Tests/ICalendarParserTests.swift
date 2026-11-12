import XCTest
@testable import CampusScheduleCore

final class ICalendarParserTests: XCTestCase {
    private func document(_ body: String) -> Data {
        Data(("BEGIN:VCALENDAR\nVERSION:2.0\nX-WR-CALNAME:学校课表\n" + body + "\nEND:VCALENDAR\n").utf8)
    }
    private let event = """
    BEGIN:VEVENT
    UID:lesson-1
    DTSTART:20261111T101000
    DTEND:20261111T115000
    SUMMARY:软件工程
    LOCATION:教学楼C404
    DESCRIPTION:第3节-第4节
    TZID:Asia/Shanghai
    END:VEVENT
    """

    func testSchoolFormatUsesStandaloneTimezone() throws {
        let result = try ICalendarParser.parse(document(event), sourceID: "school", defaultTimeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(result.name, "学校课表")
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].title, "软件工程")
        XCTAssertEqual(result.events[0].location, "教学楼C404")
        XCTAssertEqual(result.events[0].end.timeIntervalSince(result.events[0].start), 6000)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(utc.component(.hour, from: result.events[0].start), 2)
    }
    func testParameterTimezoneAndUTCProduceSameInstants() throws {
        let local = event.replacingOccurrences(of: "DTSTART:", with: "DTSTART;TZID=Asia/Shanghai:")
            .replacingOccurrences(of: "DTEND:", with: "DTEND;TZID=Asia/Shanghai:")
        let utc = event.replacingOccurrences(of: "20261111T101000", with: "20261111T021000Z")
            .replacingOccurrences(of: "20261111T115000", with: "20261111T035000Z")
        XCTAssertEqual(try ICalendarParser.parse(document(local), sourceID: "a").events[0].start,
                       try ICalendarParser.parse(document(utc), sourceID: "a").events[0].start)
    }
    func testFoldingEscapesAndNestedAlarm() throws {
        let raw = event.replacingOccurrences(of: "SUMMARY:软件工程", with: "SUMMARY:软件\n 工程")
            .replacingOccurrences(of: "DESCRIPTION:第3节-第4节", with: "DESCRIPTION:第一行\\n第二行\\,A\\;B\\\\C\nBEGIN:VALARM\nSUMMARY:不应替换课程名\nEND:VALARM")
        let result = try ICalendarParser.parse(document(raw), sourceID: "a")
        XCTAssertEqual(result.events[0].title, "软件工程")
        XCTAssertEqual(result.events[0].notes, "第一行\n第二行,A;B\\C")
    }
    func testDuplicatesAreRemovedButDistinctOccurrencesRemain() throws {
        let later = event.replacingOccurrences(of: "20261111", with: "20261118")
        let result = try ICalendarParser.parse(document([event, event, later].joined(separator: "\n")), sourceID: "school")
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.events[0].courseKey, result.events[1].courseKey)
        XCTAssertNotEqual(result.events[0].id, result.events[1].id)
    }
    func testAllDayAndCancelledEventsAreExcluded() throws {
        let cancelled = event.replacingOccurrences(of: "UID:lesson-1", with: "UID:cancelled\nSTATUS:CANCELLED")
        let allDay = "BEGIN:VEVENT\nDTSTART;VALUE=DATE:20261111\nDTEND;VALUE=DATE:20261112\nSUMMARY:假期\nEND:VEVENT"
        let result = try ICalendarParser.parse(document([event, cancelled, allDay].joined(separator: "\n")), sourceID: "a")
        XCTAssertEqual(result.events.count, 1)
    }
    func testRepeatedRulesAreRejectedInsteadOfSilentlyTruncating() {
        let repeating = event.replacingOccurrences(of: "UID:lesson-1", with: "UID:lesson-1\nRRULE:FREQ=WEEKLY;COUNT=16")
        XCTAssertThrowsError(try ICalendarParser.parse(document(repeating), sourceID: "a")) {
            XCTAssertTrue($0 is ICalendarError)
        }
    }
    func testLoginHTMLAndInvalidDatesAreRejected() {
        XCTAssertThrowsError(try ICalendarParser.parse(Data("<html>登录</html>".utf8), sourceID: "a"))
        XCTAssertThrowsError(try ICalendarParser.parse(document(event.replacingOccurrences(of: "20261111T101000", with: "20261399T101000")), sourceID: "a"))
    }
    func testStableSourceAndMetadataAcrossReimport() throws {
        let source = ICalendarParser.sourceID(for: URL(string: "https://school.example/calendar/123")!)
        let first = try ICalendarParser.parse(document(event), sourceID: source)
        var snapshot = ScheduleSnapshot()
        snapshot.registerCourses(first.events)
        let id = snapshot.profiles[0].shortID
        snapshot.profiles[0].teacher = "王老师"
        snapshot.registerCourses(try ICalendarParser.parse(document(event), sourceID: source).events)
        XCTAssertEqual(snapshot.profiles[0].shortID, id)
        XCTAssertEqual(snapshot.profiles[0].teacher, "王老师")
        XCTAssertEqual(snapshot.profiles.count, 1)
    }
    func testOldSnapshotDecodesWithoutImportedCalendarField() throws {
        let old = ScheduleSnapshot()
        let data = try JSONEncoder().encode(old)
        XCTAssertNil(try JSONDecoder().decode(ScheduleSnapshot.self, from: data).importedCalendar)
    }
    func testDirectoryProbeIsCleanedUpAndDoesNotOverwriteSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SharedRepository(fileURL: directory.appendingPathComponent("schedule.json"))
        let original = ScheduleSnapshot()
        try repository.save(original)
        try repository.verifyWritableDirectory()
        XCTAssertEqual(try repository.load(), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["schedule.json"])
    }
}
