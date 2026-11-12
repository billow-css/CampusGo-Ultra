import XCTest
@testable import CampusScheduleCore
final class LegacyReviewCompatibilityTests: XCTestCase {
    func testExistingReviewBytesRemainInBackupsWithoutAnActiveFeature() throws {
        var value = ScheduleSnapshot()
        value.reviews = [.init(title: "旧记录", courseScore: 86, teacherScore: 94, comment: "原有文字\n继续保留")]
        let restored = try SharedRepository.decodeBackup(JSONEncoder().encode(value))
        XCTAssertEqual(restored.reviews, value.reviews)
        XCTAssertTrue(restored.hasUserData)
    }
    func testSnapshotsWithoutLegacyReviewsStillDecode() throws {
        let value = try SharedRepository.decodeBackup(JSONEncoder().encode(ScheduleSnapshot()))
        XCTAssertNil(value.reviews)
    }
}
