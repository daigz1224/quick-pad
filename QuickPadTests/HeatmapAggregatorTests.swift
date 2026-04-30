import XCTest
@testable import QuickPad

/// Covers `HeatmapAggregator.build` — pure logic that turns a list of
/// `StreamSection`s into the 12×7 cell grid and month closure stats
/// shown in `StreamStatsBar`.
final class HeatmapAggregatorTests: XCTestCase {

    private let cal = Calendar.current

    // MARK: - Helpers

    /// Build a stream entry at `daysAgo` from the supplied `now`. Lets
    /// each test pin the "current moment" for deterministic results
    /// regardless of when CI runs.
    private func entry(
        daysAgo: Int,
        bulletType: BulletType = .note,
        taskState: TaskState? = nil,
        isDeleted: Bool = false,
        now: Date
    ) -> StreamEntry {
        let ts = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return StreamEntry(
            timestamp: ts,
            bulletType: bulletType,
            taskState: taskState,
            content: "x",
            isDeleted: isDeleted,
            rawLine: "- ts [\(bulletType.rawValue)] x"
        )
    }

    private func wrap(_ entries: [StreamEntry]) -> [StreamSection] {
        [StreamSection(date: nil, rawHeader: "--- d ---", entries: entries)]
    }

    // MARK: - Grid shape

    func testGridHasExactlyWeeksShownColumnsAnd7Rows() {
        let agg = HeatmapAggregator.build(sections: [], weeksShown: 12, now: Date())
        XCTAssertEqual(agg.grid.count, 12)
        for col in agg.grid {
            XCTAssertEqual(col.count, 7)
        }
    }

    func testEmptyInputProducesAllZeroCellsExceptFutureFlag() {
        let agg = HeatmapAggregator.build(sections: [], weeksShown: 8, now: Date())
        for col in agg.grid {
            for day in col {
                XCTAssertEqual(day.count, 0)
            }
        }
    }

    // MARK: - Counting

    func testTodayEntryShowsUpInLastColumn() {
        let now = Date()
        let entries = [entry(daysAgo: 0, now: now), entry(daysAgo: 0, now: now)]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)

        // Find the cell whose date matches `today` — should have count 2.
        let today = cal.startOfDay(for: now)
        let todayCell = agg.grid.flatMap { $0 }.first { $0.date == today }
        XCTAssertNotNil(todayCell)
        XCTAssertEqual(todayCell?.count, 2)
    }

    func testEntryFromYesterdayLandsOneDayBack() {
        let now = Date()
        let entries = [entry(daysAgo: 1, now: now)]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)

        let yesterday = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: now)!)
        let cell = agg.grid.flatMap { $0 }.first { $0.date == yesterday }
        XCTAssertEqual(cell?.count, 1)
    }

    func testSoftDeletedEntriesAreNotCounted() {
        let now = Date()
        let entries = [
            entry(daysAgo: 0, now: now),
            entry(daysAgo: 0, isDeleted: true, now: now),
        ]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)

        let today = cal.startOfDay(for: now)
        let cell = agg.grid.flatMap { $0 }.first { $0.date == today }
        XCTAssertEqual(cell?.count, 1)
    }

    func testEntryOlderThanWindowIsIgnoredFromGrid() {
        // 200 days ago is well outside a 12-week (84-day) window.
        let now = Date()
        let entries = [entry(daysAgo: 200, now: now)]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)

        // No cell should claim a count for that entry.
        let total = agg.grid.flatMap { $0 }.map { $0.count }.reduce(0, +)
        XCTAssertEqual(total, 0)
    }

    // MARK: - Future flag

    func testCellsAfterTodayAreFlaggedFuture() {
        let now = Date()
        let agg = HeatmapAggregator.build(sections: [], weeksShown: 12, now: now)
        let today = cal.startOfDay(for: now)

        // The grid is laid out so the rightmost column is the current
        // week; some cells in that column might be after today.
        let futureCells = agg.grid.flatMap { $0 }.filter { $0.isFuture }
        for cell in futureCells {
            XCTAssertGreaterThan(cell.date, today)
        }
        let pastOrTodayCells = agg.grid.flatMap { $0 }.filter { !$0.isFuture }
        for cell in pastOrTodayCells {
            XCTAssertLessThanOrEqual(cell.date, today)
        }
    }

    func testTodayIsNotFlaggedFuture() {
        let now = Date()
        let agg = HeatmapAggregator.build(sections: [], weeksShown: 12, now: now)
        let today = cal.startOfDay(for: now)
        let todayCell = agg.grid.flatMap { $0 }.first { $0.date == today }
        XCTAssertEqual(todayCell?.isFuture, false)
    }

    // MARK: - Month closure stats

    func testMonthClosureCountsThisMonthsTasks() {
        // Pick a `now` mid-month so we have room before/after.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 20
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        let now = cal.date(from: components)!

        let entries = [
            // This month, closed.
            entry(daysAgo: 5, bulletType: .task, taskState: .done, now: now),
            entry(daysAgo: 3, bulletType: .task, taskState: .cancelled, now: now),
            // This month, open (counts in total only).
            entry(daysAgo: 1, bulletType: .task, taskState: .pending, now: now),
            // This month, not a task — ignored.
            entry(daysAgo: 2, bulletType: .note, now: now),
            // Last month — out of window.
            entry(daysAgo: 25, bulletType: .task, taskState: .done, now: now),
        ]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)
        XCTAssertEqual(agg.monthTotal, 3)
        XCTAssertEqual(agg.monthClosed, 2)
    }

    func testMonthClosureIgnoresSoftDeleted() {
        let now = Date()
        let entries = [
            entry(daysAgo: 0, bulletType: .task, taskState: .done, isDeleted: true, now: now),
            entry(daysAgo: 0, bulletType: .task, taskState: .done, now: now),
        ]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)
        XCTAssertEqual(agg.monthTotal, 1)
        XCTAssertEqual(agg.monthClosed, 1)
    }

    // MARK: - "today" anchor

    func testTodayPropertyEqualsStartOfNow() {
        let now = Date()
        let agg = HeatmapAggregator.build(sections: [], weeksShown: 12, now: now)
        XCTAssertEqual(agg.today, cal.startOfDay(for: now))
    }

    // MARK: - Folded right-rail counters

    func testTodayAppendedCountsTodayEntriesOnly() {
        let now = Date()
        let entries = [
            entry(daysAgo: 0, now: now),
            entry(daysAgo: 0, now: now),
            entry(daysAgo: 1, now: now),
            entry(daysAgo: 5, now: now),
        ]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)
        XCTAssertEqual(agg.todayAppended, 2)
    }

    func testTodayAppendedExcludesDeleted() {
        let now = Date()
        let entries = [
            entry(daysAgo: 0, now: now),
            entry(daysAgo: 0, isDeleted: true, now: now),
        ]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)
        XCTAssertEqual(agg.todayAppended, 1)
    }

    func testStaleTaskCountTracksAgedPendingTasks() {
        let now = Date()
        let entries = [
            // Pending task ≥7 days old → stale.
            entry(daysAgo: 10, bulletType: .task, taskState: .pending, now: now),
            entry(daysAgo: 20, bulletType: .task, taskState: nil, now: now),
            // Pending but recent → not stale.
            entry(daysAgo: 3, bulletType: .task, taskState: .pending, now: now),
            // Closed task → not stale regardless of age.
            entry(daysAgo: 30, bulletType: .task, taskState: .done, now: now),
            // Note ≥7 days old → not stale (stale only applies to tasks).
            entry(daysAgo: 10, bulletType: .note, now: now),
        ]
        let agg = HeatmapAggregator.build(sections: wrap(entries), weeksShown: 12, now: now)
        XCTAssertEqual(agg.staleTaskCount, 2)
    }
}
