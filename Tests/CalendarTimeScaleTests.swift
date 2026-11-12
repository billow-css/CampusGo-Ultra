import XCTest
@testable import CampusScheduleCore

final class CalendarTimeScaleTests: XCTestCase {
    func testLunchBreakIsShortButClassRemainsReadable() {
        let scale = CalendarTimeScale(start: 480, end: 1260, periods: LessonPeriod.defaults)
        XCTAssertLessThanOrEqual(scale.position(for: 825) - scale.position(for: 710), 14.01)
        XCTAssertGreaterThanOrEqual(scale.position(for: 525) - scale.position(for: 480), 47)
        XCTAssertLessThan(scale.height, 570)
    }
    func testEveryMinuteRemainsStrictlyOrdered() {
        let scale = CalendarTimeScale(start: 480, end: 1260, periods: LessonPeriod.defaults)
        for minute in 480..<1260 { XCTAssertLessThan(scale.position(for: minute), scale.position(for: minute + 1)) }
        XCTAssertEqual(scale.position(for: 480), 0)
        XCTAssertEqual(scale.position(for: 1260), scale.height)
    }
    func testClassesOutsideConfiguredPeriodsAreNotCompressedAsBreaks() {
        let scale = CalendarTimeScale(start: 480, end: 1260, periods: LessonPeriod.defaults, occupied: [(735, 795)])
        XCTAssertEqual(scale.position(for: 795) - scale.position(for: 735), 63, accuracy: 0.001)
    }
    func testAdjacentClassesCannotOverlapAfterScaling() {
        let scale = CalendarTimeScale(start: 480, end: 1260, periods: LessonPeriod.defaults, occupied: [(955, 1000), (1010, 1055)])
        XCTAssertLessThan(scale.position(for: 1000), scale.position(for: 1010))
    }
    func testInvalidAndOutOfRangeMinutesAreSafe() {
        let invalid = CalendarTimeScale(start: 600, end: 500, periods: [])
        XCTAssertEqual(invalid.height, 0)
        XCTAssertEqual(invalid.position(for: 600), 0)
        let normal = CalendarTimeScale(start: 480, end: 1260, periods: LessonPeriod.defaults)
        XCTAssertEqual(normal.position(for: 0), 0)
        XCTAssertEqual(normal.position(for: 1440), normal.height)
    }
}
