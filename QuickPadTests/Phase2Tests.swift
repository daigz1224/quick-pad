import XCTest
@testable import QuickPad

/// Tests for Phase 2 features: gravity opacity, rescue, task state toggle,
/// and type filter support.
final class Phase2Tests: XCTestCase {

    private var tempDir: URL!
    private var tempFile: URL!
    private let mutator = StreamMutator()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickpad-phase2-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempFile = tempDir.appendingPathComponent("stream.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Gravity opacity

    func testGravityOpacityToday() {
        let entry = StreamEntry(
            timestamp: Date(),
            bulletType: .note,
            content: "fresh",
            rawLine: ""
        )
        XCTAssertEqual(entry.gravityOpacity, 1.0)
        XCTAssertEqual(entry.ageInDays, 0)
    }

    func testGravityOpacityYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let entry = StreamEntry(
            timestamp: yesterday,
            bulletType: .note,
            content: "old",
            rawLine: ""
        )
        XCTAssertEqual(entry.gravityOpacity, 0.85)
    }

    func testGravityOpacity3Days() {
        let threeDays = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let entry = StreamEntry(
            timestamp: threeDays,
            bulletType: .note,
            content: "older",
            rawLine: ""
        )
        XCTAssertEqual(entry.gravityOpacity, 0.68)
    }

    func testGravityOpacity7Days() {
        let sevenDays = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let entry = StreamEntry(
            timestamp: sevenDays,
            bulletType: .note,
            content: "week old",
            rawLine: ""
        )
        XCTAssertEqual(entry.gravityOpacity, 0.50)
    }

    func testGravityOpacity14Days() {
        let twoWeeks = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let entry = StreamEntry(
            timestamp: twoWeeks,
            bulletType: .note,
            content: "ancient",
            rawLine: ""
        )
        XCTAssertEqual(entry.gravityOpacity, 0.35)
    }

    func testGravityOpacityVeryOld() {
        let monthOld = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        let entry = StreamEntry(
            timestamp: monthOld,
            bulletType: .note,
            content: "fossil",
            rawLine: ""
        )
        XCTAssertEqual(entry.gravityOpacity, 0.22)
    }

    func testGravityOpacityNilTimestampTreatedAsToday() {
        let entry = StreamEntry(
            timestamp: nil,
            bulletType: .unknown,
            content: "no timestamp",
            rawLine: "whatever"
        )
        XCTAssertEqual(entry.ageInDays, 0)
        XCTAssertEqual(entry.gravityOpacity, 1.0)
    }

    /// Bug fix: a future timestamp (timezone edge case) should clamp to
    /// age 0 and render at full opacity, not fall to the default 0.22.
    func testGravityOpacityFutureTimestampClampsToZero() {
        let future = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
        let entry = StreamEntry(
            timestamp: future,
            bulletType: .note,
            content: "slightly future",
            rawLine: ""
        )
        XCTAssertEqual(entry.ageInDays, 0, "Future timestamps should clamp to 0 days")
        XCTAssertEqual(entry.gravityOpacity, 1.0)
    }

    // MARK: - Task state toggle (pure)

    func testReplaceTaskStatePendingToDone() {
        let line = "- 2026-04-09T22:31:17+09:00 [task] do the thing"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .done)
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [task>done] do the thing")
    }

    func testReplaceTaskStateDoneToPending() {
        let line = "- 2026-04-09T22:31:17+09:00 [task>done] did it"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .pending)
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [task] did it")
    }

    func testReplaceTaskStateDoneToMigrated() {
        let line = "- 2026-04-09T22:31:17+09:00 [task>done] revisit"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .migrated)
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [task>migrated] revisit")
    }

    func testReplaceTaskStatePendingToCancelled() {
        let line = "- 2026-04-09T22:31:17+09:00 [task] wontfix"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .cancelled)
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [task>cancelled] wontfix")
    }

    func testReplaceTaskStatePreservesDeletedSuffix() {
        let line = "- 2026-04-09T22:31:17+09:00 [task>deleted] deleted pending task"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .done)
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [task>done>deleted] deleted pending task")
    }

    func testReplaceTaskStateDoneDeletedToMigrated() {
        let line = "- 2026-04-09T22:31:17+09:00 [task>done>deleted] archived task"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .migrated)
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [task>migrated>deleted] archived task")
    }

    func testReplaceTaskStateIgnoresNonTask() {
        let line = "- 2026-04-09T22:31:17+09:00 [note] not a task"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .done)
        XCTAssertEqual(result, line, "Non-task lines should be unchanged")
    }

    func testReplaceTaskStateIgnoresQuestion() {
        // Non-task bullets should never get a task-state suffix attached.
        let line = "- 2026-04-09T22:31:17+09:00 [question] still wondering"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .done)
        XCTAssertEqual(result, line)
    }

    func testReplaceTaskStateNoBracketReturnsOriginal() {
        let line = "no brackets here"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .done)
        XCTAssertEqual(result, line)
    }

    func testReplaceTaskStateSameStateIsNoop() {
        let line = "- 2026-04-09T22:31:17+09:00 [task>done] already done"
        let result = StreamMutator.replaceTaskState(rawLine: line, newState: .done)
        // Should produce the same line (already has >done).
        XCTAssertEqual(result, line)
    }

    // MARK: - Task state toggle (FS)

    func testSetTaskStateOnDisk() throws {
        let content = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T22:31:17+09:00 [task] pending task
        - 2026-04-09T20:00:00+09:00 [note] a note
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.setTaskState(
            rawLine: "- 2026-04-09T22:31:17+09:00 [task] pending task",
            newState: .done,
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(result.contains("[task>done] pending task"))
        XCTAssertFalse(result.contains("[task] pending task"))
        XCTAssertTrue(result.contains("[note] a note"))
    }

    func testSetTaskStateRoundTripDoneToPending() throws {
        let content = "- 2026-04-09T22:31:17+09:00 [task>done] was done\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.setTaskState(
            rawLine: "- 2026-04-09T22:31:17+09:00 [task>done] was done",
            newState: .pending,
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(result.contains("[task] was done"))
        XCTAssertFalse(result.contains(">done"))
    }

    // MARK: - Rescue (pure helpers)

    func testRebuildLineWithTimestamp() {
        let old = "- 2026-04-01T10:00:00+09:00 [note] old entry"
        let now = Date()
        let result = StreamMutator.rebuildLineWithTimestamp(oldRawLine: old, now: now)

        XCTAssertTrue(result.hasPrefix("- 2026"))
        XCTAssertTrue(result.contains("[note] old entry"))
        XCTAssertFalse(result.contains("2026-04-01T10:00:00"))
    }

    func testRebuildLineWithTimestampPreservesTaskState() {
        let old = "- 2026-04-01T10:00:00+09:00 [task>migrated] moved"
        let now = Date()
        let result = StreamMutator.rebuildLineWithTimestamp(oldRawLine: old, now: now)
        XCTAssertTrue(result.contains("[task>migrated] moved"))
    }

    func testRebuildLineWithTimestampNoBracketReturnsOriginal() {
        let old = "no brackets here"
        let result = StreamMutator.rebuildLineWithTimestamp(oldRawLine: old, now: Date())
        XCTAssertEqual(result, old)
    }

    func testSeparatorLineFormat() {
        // Use a known date to verify the separator format.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let dayStr = formatter.string(from: now)
        let sep = StreamMutator.separatorLine(for: now)
        XCTAssertTrue(sep.hasPrefix("--- \(dayStr)"))
        XCTAssertTrue(sep.hasSuffix("---"))
    }

    // MARK: - Rescue (FS)

    func testRescueMovesEntryToToday() throws {
        let now = Date()
        let todaySep = StreamMutator.separatorLine(for: now)

        let content = """
        \(todaySep)

        - 2026-04-10T12:00:00+09:00 [note] today entry

        --- 2026-04-01 Tuesday ---

        - 2026-04-01T10:00:00+09:00 [idea] old idea to rescue
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.rescue(
            rawLine: "- 2026-04-01T10:00:00+09:00 [idea] old idea to rescue",
            at: now,
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertFalse(result.contains("2026-04-01T10:00:00"))
        XCTAssertTrue(result.contains("[idea] old idea to rescue"))

        let lines = result.components(separatedBy: "\n")
        let sepIdx = lines.firstIndex(where: { $0.contains(todaySep) })
        XCTAssertNotNil(sepIdx)
        let rescuedIdx = lines.firstIndex(where: { $0.contains("old idea to rescue") })
        XCTAssertNotNil(rescuedIdx)
        if let s = sepIdx, let r = rescuedIdx {
            XCTAssertTrue(r > s && r <= s + 3, "Rescued entry should be near today's separator")
        }
    }

    func testRescueCreatesTodaySeparatorIfMissing() throws {
        let now = Date()
        let content = """
        --- 2026-03-01 Saturday ---

        - 2026-03-01T10:00:00+09:00 [note] ancient entry
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.rescue(
            rawLine: "- 2026-03-01T10:00:00+09:00 [note] ancient entry",
            at: now,
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        let todaySep = StreamMutator.separatorLine(for: now)
        XCTAssertTrue(result.contains(todaySep), "Should create today's separator")
        XCTAssertTrue(result.contains("[note] ancient entry"))
    }

    func testRescueThrowsOnMissingLine() throws {
        let content = "- 2026-04-09T22:31:17+09:00 [note] present\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try mutator.rescue(
                rawLine: "- 2026-04-09T22:31:17+09:00 [note] absent",
                fileURL: tempFile
            )
        ) { error in
            XCTAssertTrue(error is StreamMutator.MutationError)
        }
    }

    func testRescueThrowsOnMissingFile() {
        let nonexistent = tempDir.appendingPathComponent("nope.md")
        XCTAssertThrowsError(
            try mutator.rescue(rawLine: "whatever", fileURL: nonexistent)
        )
    }

    // MARK: - Parser: deleted entries with task state

    func testParserDeletedTaskDoneHasBothFlags() {
        let text = "- 2026-04-09T22:31:17+09:00 [task>done>deleted] old task\n"
        let sections = StreamParser.parse(text)
        let entry = sections[0].entries[0]
        XCTAssertTrue(entry.isDeleted)
        XCTAssertEqual(entry.bulletType, .task)
        XCTAssertEqual(entry.taskState, .done)
    }

    func testParserDeletedNoteIsDeleted() {
        let text = "- 2026-04-09T22:31:17+09:00 [note>deleted] hidden\n"
        let sections = StreamParser.parse(text)
        let entry = sections[0].entries[0]
        XCTAssertTrue(entry.isDeleted)
        XCTAssertEqual(entry.bulletType, .note)
        XCTAssertFalse(entry.content.isEmpty)
    }

    func testParserNonDeletedEntryIsNotDeleted() {
        let text = "- 2026-04-09T22:31:17+09:00 [note] visible\n"
        let sections = StreamParser.parse(text)
        let entry = sections[0].entries[0]
        XCTAssertFalse(entry.isDeleted)
    }

    // MARK: - End-to-end: rescue → parse round-trip

    func testRescuedEntryParsesCorrectly() throws {
        let now = Date()
        let todaySep = StreamMutator.separatorLine(for: now)
        let content = """
        \(todaySep)

        --- 2026-03-01 Saturday ---

        - 2026-03-01T10:00:00+09:00 [task>done] old completed task
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.rescue(
            rawLine: "- 2026-03-01T10:00:00+09:00 [task>done] old completed task",
            at: now,
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        let sections = StreamParser.parse(result)

        // Should have a today section with the rescued entry.
        let todaySection = sections.first(where: {
            guard let date = $0.date else { return false }
            return Calendar.current.isDateInToday(date)
        })
        XCTAssertNotNil(todaySection)
        let rescued = todaySection?.entries.first(where: {
            $0.content.contains("old completed task")
        })
        XCTAssertNotNil(rescued)
        XCTAssertEqual(rescued?.bulletType, .task)
        XCTAssertEqual(rescued?.taskState, .done)
    }

    // MARK: - Task state toggle → parse round-trip

    func testTaskStateToggleRoundTrip() throws {
        let content = "- 2026-04-09T22:31:17+09:00 [task] need to do\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        // pending → done
        try mutator.setTaskState(
            rawLine: "- 2026-04-09T22:31:17+09:00 [task] need to do",
            newState: .done,
            fileURL: tempFile
        )
        var result = try String(contentsOf: tempFile, encoding: .utf8)
        var entry = StreamParser.parse(result)[0].entries[0]
        XCTAssertEqual(entry.taskState, .done)

        // done → migrated
        try mutator.setTaskState(
            rawLine: "- 2026-04-09T22:31:17+09:00 [task>done] need to do",
            newState: .migrated,
            fileURL: tempFile
        )
        result = try String(contentsOf: tempFile, encoding: .utf8)
        entry = StreamParser.parse(result)[0].entries[0]
        XCTAssertEqual(entry.taskState, .migrated)

        // migrated → pending
        try mutator.setTaskState(
            rawLine: "- 2026-04-09T22:31:17+09:00 [task>migrated] need to do",
            newState: .pending,
            fileURL: tempFile
        )
        result = try String(contentsOf: tempFile, encoding: .utf8)
        entry = StreamParser.parse(result)[0].entries[0]
        XCTAssertEqual(entry.taskState, .pending)
    }
}
