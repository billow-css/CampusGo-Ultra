import XCTest
@testable import CampusScheduleCore

final class GoSciTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    func date(_ day: Int = 19, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    func add(_ document: inout SciDocument, day: Int = 19, period: SciPeriod = .morning, titles: String = "检查日志\n跑实验") throws -> String {
        let id = document.ensureSession(on: date(day), period: period, calendar: calendar)
        try document.setDraft(titles, session: id)
        try document.commitDraft(session: id)
        return id
    }
    func testNightAfterMidnightBelongsToPreviousDayAndEndsExclusively() {
        let block = SciPeriod.containing(date(20, 1, 59), calendar: calendar)
        XCTAssertEqual(block?.day, date(19)); XCTAssertEqual(block?.period, .night)
        XCTAssertNil(SciPeriod.containing(date(20, 2), calendar: calendar))
        XCTAssertEqual(SciPeriod.night.interval(on: date(), calendar: calendar).end, date(20, 2))
    }
    func testExactDayBoundariesAndUnscheduledGaps() {
        for hour in [2, 6, 12, 13] { XCTAssertNil(SciPeriod.containing(date(19, hour), calendar: calendar)) }
        XCTAssertEqual(SciPeriod.containing(date(19, 7), calendar: calendar)?.period, .morning)
        XCTAssertEqual(SciPeriod.containing(date(19, 14), calendar: calendar)?.period, .afternoon)
        XCTAssertEqual(SciPeriod.containing(date(19, 19), calendar: calendar)?.period, .night)
    }
    func testNextPeriodCrossesDayAndWeek() {
        let next = SciPeriod.night.next(on: date(22), calendar: calendar)
        XCTAssertEqual(next.day, date(23)); XCTAssertEqual(next.period, .morning)
    }
    func testUniqueEightCharacterIDsAndOneSessionPerDayPeriod() throws {
        var document = SciDocument()
        for offset in 0..<60 {
            let day = calendar.date(byAdding: .day, value: offset, to: date())!
            for period in SciPeriod.allCases {
                let id = document.ensureSession(on: day, period: period, calendar: calendar)
                XCTAssertNotNil(id.range(of: "^S[A-Z0-9]{7}$", options: .regularExpression))
                XCTAssertEqual(document.ensureSession(on: day.addingTimeInterval(3600), period: period, calendar: calendar), id)
            }
        }
        XCTAssertEqual(document.sessions.count, 180); XCTAssertEqual(document.usedIDs.count, 180)
        try document.validate(calendar: calendar)
    }
    func testMultilineCommitTrimsBlankLinesAndDoesNotDuplicateOnSecondCommit() throws {
        var document = SciDocument()
        let id = try add(&document, titles: " 检查日志 \n\n跑实验\r\n  ")
        try document.commitDraft(session: id)
        XCTAssertEqual(document.session(id)?.tasks.map(\.title), ["检查日志", "跑实验"])
        XCTAssertEqual(document.session(id)?.draftText, "")
    }
    func testDraftSurvivesSerializationWithoutShowingAsPlan() throws {
        var document = SciDocument()
        let id = document.ensureSession(on: date(), period: .night, calendar: calendar)
        try document.setDraft("未写完\n第二行", session: id)
        let restored = try JSONDecoder().decode(SciDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored, document)
        XCTAssertEqual(restored.plannedCount(on: date(), calendar: calendar), 0)
        XCTAssertNil(restored.featured(at: date(19, 20), calendar: calendar))
    }
    func testCheckboxProgressAndCompletedDayMarkerAreRetained() throws {
        var document = SciDocument(); let id = try add(&document)
        for task in document.session(id)!.tasks { try document.toggleTask(task.id, session: id) }
        XCTAssertEqual(document.session(id)?.progress, 1)
        XCTAssertEqual(document.plannedCount(on: date(), calendar: calendar), 1)
        XCTAssertFalse(document.session(id)!.isOverdue(at: date(20), calendar: calendar))
        XCTAssertNil(document.featured(at: date(20), calendar: calendar))
    }
    func testOverdueBeginsAtEndOfBlock() throws {
        var document = SciDocument(); let id = try add(&document)
        XCTAssertFalse(document.session(id)!.isOverdue(at: date(19, 11, 59), calendar: calendar))
        XCTAssertTrue(document.session(id)!.isOverdue(at: date(19, 12), calendar: calendar))
    }
    func testWholeSessionPostponePreservesIDAndTaskIDs() throws {
        var document = SciDocument(); let id = try add(&document)
        let tasks = document.session(id)!.tasks
        let moved = try document.postpone(session: id, at: date(19, 12), calendar: calendar)
        XCTAssertEqual(moved, id); XCTAssertEqual(document.session(moved)?.period, .afternoon)
        XCTAssertEqual(document.session(moved)?.tasks, tasks)
        XCTAssertEqual(document.sessions.count, 1)
    }
    func testPartialPostponeLeavesCompletedHistoryAndMovesOnlyPendingItems() throws {
        var document = SciDocument(); let id = try add(&document)
        let tasks = document.session(id)!.tasks
        try document.toggleTask(tasks[0].id, session: id)
        let moved = try document.postpone(session: id, at: date(19, 12), calendar: calendar)
        XCTAssertNotEqual(moved, id)
        XCTAssertEqual(document.session(id)?.tasks.map(\.id), [tasks[0].id])
        XCTAssertTrue(document.session(id)!.tasks[0].isCompleted)
        XCTAssertEqual(document.session(moved)?.tasks.map(\.id), [tasks[1].id])
        try document.validate(calendar: calendar)
    }
    func testPostponeMergesIntoExistingTargetAndReservesOldID() throws {
        var document = SciDocument(); let id = try add(&document)
        let target = try add(&document, period: .afternoon, titles: "组会")
        XCTAssertEqual(try document.postpone(session: id, at: date(19, 12), calendar: calendar), target)
        XCTAssertNil(document.session(id)); XCTAssertTrue(document.usedIDs.contains(id))
        XCTAssertEqual(document.session(target)?.tasks.map(\.title), ["组会", "检查日志", "跑实验"])
        try document.validate(calendar: calendar)
    }
    func testOldOverduePostponeSkipsExpiredBlocks() throws {
        var document = SciDocument(); let id = try add(&document, day: 1)
        let target = try document.postpone(session: id, at: date(19, 20), calendar: calendar)
        XCTAssertEqual(document.session(target)?.day, date(19))
        XCTAssertEqual(document.session(target)?.period, .night)
        XCTAssertTrue(document.overdue(at: date(19, 20), calendar: calendar).isEmpty)
    }
    func testPostponeInLunchGapUsesAfternoonAndAfterNightUsesMorning() throws {
        for (now, day, period) in [(date(19, 13), date(19), SciPeriod.afternoon), (date(20, 3), date(20), .morning)] {
            var document = SciDocument(); let id = try add(&document, day: 1)
            let target = try document.postpone(session: id, at: now, calendar: calendar)
            XCTAssertEqual(document.session(target)?.day, day)
            XCTAssertEqual(document.session(target)?.period, period)
        }
    }
    func testPoolRoundTripMovesNotCopiesAndRetainsOriginAndCompletionHistory() throws {
        var document = SciDocument(); let id = try add(&document)
        let tasks = document.session(id)!.tasks
        try document.toggleTask(tasks[0].id, session: id)
        try document.moveToPool(session: id)
        XCTAssertEqual(document.session(id)?.tasks.count, 1)
        XCTAssertEqual(document.pool.map(\.id), [tasks[1].id])
        XCTAssertEqual(document.pool.first?.originSessionID, id)
        let target = document.ensureSession(on: date(20), period: .night, calendar: calendar)
        try document.takeFromPool(tasks[1].id, into: target)
        XCTAssertTrue(document.pool.isEmpty)
        XCTAssertEqual(document.session(target)?.tasks.first?.id, tasks[1].id)
        XCTAssertThrowsError(try document.takeFromPool(tasks[1].id, into: target))
        try document.validate(calendar: calendar)
    }
    func testFeaturedPrioritizesCurrentThenFutureThenLatestOverdue() throws {
        var document = SciDocument(); let old = try add(&document, day: 18)
        let current = try add(&document)
        let next = try add(&document, day: 20)
        XCTAssertEqual(document.featured(at: date(19, 10), calendar: calendar)?.id, current)
        XCTAssertEqual(document.featured(at: date(19, 13), calendar: calendar)?.id, next)
        XCTAssertEqual(document.featured(at: date(21), calendar: calendar)?.id, next)
        XCTAssertEqual(document.overdue(at: date(19, 10), calendar: calendar).map(\.id), [old])
    }
    func testEmptySessionRemovalNeverRecyclesIDOrDropsDraft() throws {
        var document = SciDocument()
        let id = document.ensureSession(on: date(), period: .morning, calendar: calendar)
        try document.setDraft("草稿", session: id); document.removeEmptySession(id)
        XCTAssertNotNil(document.session(id))
        try document.setDraft("", session: id); document.removeEmptySession(id)
        XCTAssertNil(document.session(id)); XCTAssertTrue(document.usedIDs.contains(id))
        XCTAssertNotEqual(document.ensureSession(on: date(), period: .morning, calendar: calendar), id)
    }
    func testDeselectPrunesEmptyAndWhitespaceSlotsButPreservesPlansAndDrafts() throws {
        var document = SciDocument()
        let empty = document.ensureSession(on: date(), period: .morning, calendar: calendar)
        let whitespace = document.ensureSession(on: date(), period: .afternoon, calendar: calendar)
        try document.setDraft(" \n\t ", session: whitespace)
        let draft = document.ensureSession(on: date(), period: .night, calendar: calendar)
        try document.setDraft("待输入的想法", session: draft)
        let planned = try add(&document, day: 20)
        document.removeEmptySessions()
        XCTAssertNil(document.session(empty)); XCTAssertNil(document.session(whitespace))
        XCTAssertEqual(document.session(draft)?.draftText, "待输入的想法")
        XCTAssertEqual(document.session(planned)?.tasks.count, 2)
        XCTAssertTrue(document.usedIDs.contains(empty)); XCTAssertTrue(document.usedIDs.contains(whitespace))
        try document.validate(calendar: calendar)
    }
    func testSwitchingToBlankKeepsDestinationButClearsPreviousEmptySlot() throws {
        var document = SciDocument()
        let first = document.ensureSession(on: date(), period: .morning, calendar: calendar)
        let second = document.ensureSession(on: date(), period: .afternoon, calendar: calendar)
        document.removeEmptySessions(except: second)
        XCTAssertNil(document.session(first)); XCTAssertNotNil(document.session(second))
        document.removeEmptySessions(except: second)
        XCTAssertEqual(document.ensureSession(on: date(), period: .afternoon, calendar: calendar), second)
        document.removeEmptySessions()
        XCTAssertTrue(document.sessions.isEmpty)
    }
    func testInvalidVersionDuplicateTaskAndDuplicateSlotRejected() throws {
        var document = SciDocument(); let id = try add(&document)
        var bad = document; bad.schemaVersion = 99; XCTAssertThrowsError(try bad.validate(calendar: calendar))
        bad = document; bad.pool.append(bad.sessions[0].tasks[0]); XCTAssertThrowsError(try bad.validate(calendar: calendar))
        bad = document
        var duplicate = document.session(id)!; duplicate.id = "S1234567"
        bad.sessions.append(duplicate); bad.usedIDs.insert(duplicate.id)
        XCTAssertThrowsError(try bad.validate(calendar: calendar))
    }
    func testDayCountsHaveThreeLevelsAndExcludeEmptyDrafts() throws {
        var document = SciDocument()
        for (index, period) in SciPeriod.allCases.enumerated() {
            _ = try add(&document, period: period)
            XCTAssertEqual(document.plannedCount(on: date(), calendar: calendar), index + 1)
        }
        _ = document.ensureSession(on: date(20), period: .morning, calendar: calendar)
        XCTAssertEqual(document.plannedCount(on: date(20), calendar: calendar), 0)
    }
    func testDeleteSessionRemovesPlanAndMarkerWithoutChangingPoolOrRecyclingID() throws {
        var document = SciDocument(); let id = try add(&document)
        document.addToPool("其他待安排任务")
        let pool = document.pool
        let deleted = try document.deleteSession(id)
        XCTAssertEqual(deleted.id, id); XCTAssertEqual(deleted.tasks.count, 2)
        XCTAssertNil(document.session(id)); XCTAssertEqual(document.plannedCount(on: date(), calendar: calendar), 0)
        XCTAssertNil(document.featured(at: date(19, 10), calendar: calendar))
        XCTAssertEqual(document.pool, pool); XCTAssertTrue(document.usedIDs.contains(id))
        XCTAssertThrowsError(try document.deleteSession(id))
    }
    func testUndoDeletionRestoresOriginalIDCompletionAndDraft() throws {
        var document = SciDocument(); let id = try add(&document)
        try document.toggleTask(document.session(id)!.tasks[0].id, session: id)
        try document.setDraft("还没写完", session: id)
        let before = document
        let deleted = try document.deleteSession(id)
        XCTAssertEqual(document.restoreSession(deleted, calendar: calendar), id)
        XCTAssertEqual(document, before)
        try document.validate(calendar: calendar)
    }
    func testUndoDeletionMergesWhenOriginalSlotHasBeenReused() throws {
        var document = SciDocument(); let id = try add(&document)
        try document.setDraft("原草稿", session: id)
        let deleted = try document.deleteSession(id)
        let replacement = try add(&document, titles: "新安排")
        try document.setDraft("新草稿", session: replacement)
        XCTAssertEqual(document.restoreSession(deleted, calendar: calendar), replacement)
        XCTAssertEqual(document.sessions.count, 1)
        XCTAssertEqual(document.session(replacement)?.tasks.map(\.title), ["新安排", "检查日志", "跑实验"])
        XCTAssertEqual(document.session(replacement)?.draftText, "新草稿\n原草稿")
        try document.validate(calendar: calendar)
    }
    func testNightFollowsLocalClockAcrossDST() {
        var la = Calendar(identifier: .gregorian); la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = la.date(from: DateComponents(year: 2026, month: 3, day: 7))!
        let interval = SciPeriod.night.interval(on: day, calendar: la)
        XCTAssertEqual(la.component(.day, from: interval.end), 8)
        XCTAssertGreaterThan(interval.duration, 0)
    }
}
