import XCTest
@testable import QuickPad

final class StreamArchiverTests: XCTestCase {

    private var tempDir: URL!
    private var streamURL: URL!
    private var archiveDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickPadArchiverTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        streamURL = tempDir.appendingPathComponent("stream.md")
        archiveDir = tempDir.appendingPathComponent("archive")
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    private func makeArchiver(days: Int = 30) -> StreamArchiver {
        StreamArchiver(
            archiveAfterDays: days,
            archiveDirectory: archiveDir,
            streamFileURL: streamURL
        )
    }

    private func writeStream(_ content: String) throws {
        try content.write(to: streamURL, atomically: true, encoding: .utf8)
    }

    private func readStream() throws -> String {
        try String(contentsOf: streamURL, encoding: .utf8)
    }

    private func readArchive(_ month: String) throws -> String {
        let url = archiveDir.appendingPathComponent("\(month).md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - No-op cases

    func testNoFileIsNoOp() throws {
        let archiver = makeArchiver()
        let result = try archiver.run()
        XCTAssertEqual(result.archivedCount, 0)
        XCTAssertEqual(result.cleanedDeletedCount, 0)
    }

    func testEmptyFileIsNoOp() throws {
        try writeStream("")
        let archiver = makeArchiver()
        let result = try archiver.run()
        XCTAssertEqual(result.archivedCount, 0)
    }

    func testNoEligibleEntriesIsNoOp() throws {
        // Pending task and a note — neither should be archived.
        try writeStream("""
        --- 2026-04-08 Tuesday ---

        - 2026-04-08T10:00:00+08:00 [task] pending task
        - 2026-04-08T10:00:00+08:00 [note] a note
        """)
        let archiver = makeArchiver(days: 0)
        let result = try archiver.run()
        XCTAssertEqual(result.archivedCount, 0)

        let remaining = try readStream()
        XCTAssertTrue(remaining.contains("[task] pending task"))
        XCTAssertTrue(remaining.contains("[note] a note"))
    }

    // MARK: - Done/cancelled archival

    func testDoneTaskOlderThanThresholdIsArchived() throws {
        try writeStream("""
        --- 2026-03-01 Sunday ---

        - 2026-03-01T10:00:00+08:00 [task>done] finished task
        - 2026-03-01T10:00:00+08:00 [note] a note
        """)

        // "now" is 41 days after the entry → older than 30-day threshold.
        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 1)

        // stream.md should still have the note, not the done task.
        let remaining = try readStream()
        XCTAssertTrue(remaining.contains("[note] a note"))
        XCTAssertFalse(remaining.contains("[task>done] finished task"))

        // Archive file should have the done task.
        let archive = try readArchive("2026-03")
        XCTAssertTrue(archive.contains("[task>done] finished task"))
        XCTAssertTrue(archive.contains("--- 2026-03-01"))
    }

    func testCancelledTaskIsArchived() throws {
        try writeStream("""
        --- 2026-03-01 Sunday ---

        - 2026-03-01T10:00:00+08:00 [task>cancelled] cancelled task
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 1)
        let archive = try readArchive("2026-03")
        XCTAssertTrue(archive.contains("[task>cancelled] cancelled task"))
    }

    func testRecentDoneTaskIsNotArchived() throws {
        // Entry is only 5 days old, threshold is 30 days.
        try writeStream("""
        --- 2026-04-06 Monday ---

        - 2026-04-06T08:00:00+08:00 [task>done] just finished
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 0)
        let remaining = try readStream()
        XCTAssertTrue(remaining.contains("[task>done] just finished"))
    }

    // MARK: - Soft-deleted cleanup

    func testOldDeletedEntriesAreCleaned() throws {
        try writeStream("""
        --- 2026-03-01 Sunday ---

        - 2026-03-01T10:00:00+08:00 [note>deleted] trashed note
        - 2026-03-01T10:00:00+08:00 [note] keep this
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.cleanedDeletedCount, 1)
        let remaining = try readStream()
        XCTAssertFalse(remaining.contains(">deleted"))
        XCTAssertTrue(remaining.contains("[note] keep this"))
    }

    func testRecentDeletedEntryIsNotCleaned() throws {
        try writeStream("""
        --- 2026-04-06 Monday ---

        - 2026-04-06T08:00:00+08:00 [note>deleted] recent delete
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.cleanedDeletedCount, 0)
        let remaining = try readStream()
        XCTAssertTrue(remaining.contains("[note>deleted] recent delete"))
    }

    // MARK: - Empty separator cleanup

    func testEmptySeparatorIsRemovedAfterArchival() throws {
        // All entries under this day are archivable → separator removed.
        try writeStream("""
        --- 2026-04-10 Friday ---

        - 2026-04-10T10:00:00+08:00 [note] keep

        --- 2026-03-01 Sunday ---

        - 2026-03-01T10:00:00+08:00 [task>done] old done
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 1)
        let remaining = try readStream()
        XCTAssertFalse(remaining.contains("2026-03-01"))
        XCTAssertTrue(remaining.contains("2026-04-10"))
    }

    // MARK: - Multi-month archival

    func testEntriesGroupedByMonth() throws {
        try writeStream("""
        --- 2026-03-05 Thursday ---

        - 2026-03-05T10:00:00+08:00 [task>done] march done

        --- 2026-02-10 Tuesday ---

        - 2026-02-10T10:00:00+08:00 [task>done] february done
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 2)

        let marchArchive = try readArchive("2026-03")
        XCTAssertTrue(marchArchive.contains("march done"))
        XCTAssertFalse(marchArchive.contains("february done"))

        let febArchive = try readArchive("2026-02")
        XCTAssertTrue(febArchive.contains("february done"))
        XCTAssertFalse(febArchive.contains("march done"))
    }

    // MARK: - Archive append (idempotence)

    func testAppendToExistingArchiveFile() throws {
        // Pre-populate an archive file.
        try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let archiveURL = archiveDir.appendingPathComponent("2026-03.md")
        try "--- 2026-03-01 Sunday ---\n\n- 2026-03-01T10:00:00+08:00 [task>done] older\n".write(
            to: archiveURL, atomically: true, encoding: .utf8
        )

        try writeStream("""
        --- 2026-03-05 Thursday ---

        - 2026-03-05T10:00:00+08:00 [task>done] newer done
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 1)
        let archive = try readArchive("2026-03")
        XCTAssertTrue(archive.contains("older"))
        XCTAssertTrue(archive.contains("newer done"))
    }

    // MARK: - Mixed scenario

    func testMixedScenario() throws {
        try writeStream("""
        --- 2026-04-10 Friday ---

        - 2026-04-10T10:00:00+08:00 [note] today note
        - 2026-04-10T09:00:00+08:00 [task] pending today

        --- 2026-03-01 Sunday ---

        - 2026-03-01T10:00:00+08:00 [task>done] old done
        - 2026-03-01T09:00:00+08:00 [task>cancelled] old cancelled
        - 2026-03-01T08:00:00+08:00 [note>deleted] old deleted
        - 2026-03-01T07:00:00+08:00 [note] old note to keep
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 2)        // done + cancelled
        XCTAssertEqual(result.cleanedDeletedCount, 1)   // deleted note

        let remaining = try readStream()
        XCTAssertTrue(remaining.contains("[note] today note"))
        XCTAssertTrue(remaining.contains("[task] pending today"))
        XCTAssertTrue(remaining.contains("[note] old note to keep"))
        XCTAssertFalse(remaining.contains("[task>done]"))
        XCTAssertFalse(remaining.contains("[task>cancelled]"))
        XCTAssertFalse(remaining.contains(">deleted"))

        let archive = try readArchive("2026-03")
        XCTAssertTrue(archive.contains("[task>done] old done"))
        XCTAssertTrue(archive.contains("[task>cancelled] old cancelled"))
    }

    // MARK: - Deleted-done should NOT be archived

    func testDeletedDoneTaskIsCleanedNotArchived() throws {
        // A done task that was also soft-deleted: should be cleaned, not archived.
        try writeStream("""
        --- 2026-03-01 Sunday ---

        - 2026-03-01T10:00:00+08:00 [task>done>deleted] done and deleted
        """)

        let now = ISO8601DateFormatter().date(from: "2026-04-11T10:00:00+08:00")!
        let archiver = makeArchiver(days: 30)
        let result = try archiver.run(now: now)

        XCTAssertEqual(result.archivedCount, 0)
        XCTAssertEqual(result.cleanedDeletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: archiveDir.appendingPathComponent("2026-03.md").path
        ))
    }
}
