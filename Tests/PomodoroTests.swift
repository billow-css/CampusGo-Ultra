import XCTest
@testable import CampusScheduleCore

final class PomodoroTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func testDefaultAndCycleLimits() {
        var timer = PomodoroSession()
        XCTAssertTrue(timer.isValid)
        XCTAssertEqual(timer.remaining(at: start), 1500)
        timer.configure(cycles: 0); XCTAssertEqual(timer.cycles, 1)
        timer.configure(cycles: 99); XCTAssertEqual(timer.cycles, 12)
    }
    func testStartCreatesFocusDeadline() {
        var timer = PomodoroSession(); timer.start(at: start)
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(1500))
        XCTAssertEqual(timer.currentCycle, 1)
        XCTAssertTrue(timer.isValid)
    }
    func testExactFocusBoundaryStartsBlueRest() {
        var timer = PomodoroSession(); timer.start(at: start)
        timer.advance(to: start.addingTimeInterval(1499))
        XCTAssertEqual(timer.phase, .focus)
        timer.advance(to: start.addingTimeInterval(1500))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.completedCycles, 1)
        XCTAssertEqual(timer.currentCycle, 1)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(1800))
    }
    func testRestBoundaryStartsNextFocus() {
        var timer = PomodoroSession(); timer.start(at: start)
        timer.advance(to: start.addingTimeInterval(1800))
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.currentCycle, 2)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(3300))
    }
    func testFinalFocusFinishesWithoutExtraRest() {
        var timer = PomodoroSession(); timer.configure(cycles: 1); timer.start(at: start)
        timer.advance(to: start.addingTimeInterval(1500))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.completedCycles, 1)
        XCTAssertNil(timer.deadline)
        XCTAssertEqual(timer.remaining(at: start), 0)
        XCTAssertTrue(timer.isValid)
    }
    func testTwoCyclesFinishAfterFiftyFiveMinutes() {
        var timer = PomodoroSession(); timer.configure(cycles: 2); timer.start(at: start)
        timer.advance(to: start.addingTimeInterval(3300))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.completedCycles, 2)
    }
    func testPauseFreezesAndResumePreservesRemainingTime() {
        var timer = PomodoroSession(); timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(400))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(10_000)), 1100)
        XCTAssertFalse(timer.advance(to: start.addingTimeInterval(10_000)))
        timer.resume(at: start.addingTimeInterval(10_000))
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(11_100))
        XCTAssertTrue(timer.isValid)
    }
    func testPauseAtBoundaryPausesNewPhase() {
        var timer = PomodoroSession(); timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(1500))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.pausedRemaining, 300)
    }
    func testDelayedTickDoesNotShiftPhaseDeadline() {
        var timer = PomodoroSession(); timer.start(at: start)
        timer.advance(to: start.addingTimeInterval(1510))
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(1800))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(1510)), 290)
    }
    func testLongSleepCatchesUpAllTwelveCyclesWithBoundedWork() {
        var timer = PomodoroSession(); timer.configure(cycles: 12); timer.start(at: start)
        timer.advance(to: start.addingTimeInterval(86400))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.completedCycles, 12)
        XCTAssertTrue(timer.isValid)
        XCTAssertFalse(timer.advance(to: start.addingTimeInterval(172800)))
    }
    func testConfigurationCannotChangeActiveSession() {
        var timer = PomodoroSession(); timer.start(at: start)
        let before = timer
        timer.configure(cycles: 9)
        XCTAssertEqual(timer, before)
    }
    func testResetPreservesCycleGoal() {
        var timer = PomodoroSession(); timer.configure(cycles: 3); timer.start(at: start)
        timer.reset()
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.cycles, 3)
        XCTAssertEqual(timer.completedCycles, 0)
        XCTAssertTrue(timer.isValid)
    }
    func testRunningAndPausedStateRoundTrips() throws {
        var timer = PomodoroSession(); timer.start(at: start)
        var restored = try JSONDecoder().decode(PomodoroSession.self, from: JSONEncoder().encode(timer))
        restored.advance(to: start.addingTimeInterval(1800))
        XCTAssertEqual(restored.currentCycle, 2)
        timer.pause(at: start.addingTimeInterval(250))
        restored = try JSONDecoder().decode(PomodoroSession.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(restored, timer)
        XCTAssertTrue(restored.isValid)
    }
    func testCorruptedStateRejected() {
        var timer = PomodoroSession(); timer.cycles = 0
        XCTAssertFalse(timer.isValid)
        timer = PomodoroSession(); timer.phase = .focus
        XCTAssertFalse(timer.isValid)
        timer = PomodoroSession(); timer.phase = .rest; timer.pausedRemaining = 300
        XCTAssertFalse(timer.isValid)
        timer = PomodoroSession(); timer.phase = .finished
        XCTAssertFalse(timer.isValid)
    }
}
