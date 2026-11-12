import XCTest
@testable import CampusScheduleCore

final class SigningMigrationTests: XCTestCase {
    func testBackupPreservesTeachersExamLinksAndCourseIDs() throws {
        let start = Date(timeIntervalSince1970: 1_794_384_600)
        let course = CourseOccurrence(id:"original",calendarID:"school",title:"软件工程",start:start,
            end:start.addingTimeInterval(6000),location:"C404",notes:"备注")
        var value = ScheduleSnapshot(now:start)
        value.occurrences = [course]
        value.registerCourses([course])
        value.profiles[0].teacher = "王老师"
        value.upsertExam(.marking(course))
        value.todos = [.init(title:"复习",icon:"book",deadline:start)]
        let restored = try SharedRepository.decodeBackup(JSONEncoder().encode(value))
        XCTAssertEqual(restored,value)
        XCTAssertEqual(restored.profile(for:restored.schedule[0])?.teacher,"王老师")
        XCTAssertEqual(restored.profile(for:restored.schedule[0])?.shortID,value.profiles[0].shortID)
        XCTAssertTrue(restored.schedule[0].isExam)
    }
    func testUnknownBackupVersionIsRejected() throws {
        var value = ScheduleSnapshot()
        value.schemaVersion = 99
        XCTAssertThrowsError(try SharedRepository.decodeBackup(JSONEncoder().encode(value)))
    }
    func testDataProtectionIncludesTeacherOnlyAndCalendarOnlyStores() {
        var value = ScheduleSnapshot()
        XCTAssertFalse(value.hasUserData)
        value.profiles = [.init(id:"school::数学",title:"数学",shortID:"AB234",teacher:"王老师")]
        XCTAssertTrue(value.hasUserData)
        value = ScheduleSnapshot()
        value.settings.calendarIDs = ["school"]
        XCTAssertTrue(value.hasUserData)
    }
}
