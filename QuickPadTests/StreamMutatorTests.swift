import XCTest
@testable import QuickPad

final class StreamMutatorTests: XCTestCase {

    private var tempDir: URL!
    private var tempFile: URL!
    private let mutator = StreamMutator()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickpad-mutator-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempFile = tempDir.appendingPathComponent("stream.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - rebuildLine (pure)

    func testRebuildLinePreservesPrefix() {
        let old = "- 2026-04-09T22:31:17+09:00 [note] old content"
        let result = StreamMutator.rebuildLine(oldRawLine: old, newContent: "new content")
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [note] new content")
    }

    func testRebuildLinePreservesTaskState() {
        let old = "- 2026-04-09T22:31:17+09:00 [task>done] shipped it"
        let result = StreamMutator.rebuildLine(oldRawLine: old, newContent: "shipped v2")
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [task>done] shipped v2")
    }

    func testRebuildLineExpandsShortcuts() {
        let old = "- 2026-04-09T22:31:17+09:00 [note] something"
        let result = StreamMutator.rebuildLine(oldRawLine: old, newContent: "* urgent thing")
        XCTAssertEqual(result, "- 2026-04-09T22:31:17+09:00 [note] *priority urgent thing")
    }

    func testRebuildLineNoBracketReturnsOriginal() {
        let old = "no brackets here"
        let result = StreamMutator.rebuildLine(oldRawLine: old, newContent: "whatever")
        XCTAssertEqual(result, old)
    }

    // MARK: - insertDeletedSuffix (pure)

    func testInsertDeletedSuffixNote() {
        let line = "- 2026-04-09T22:31+09:00 [note] some insight"
        let result = StreamMutator.insertDeletedSuffix(line)
        XCTAssertEqual(result, "- 2026-04-09T22:31+09:00 [note>deleted] some insight")
    }

    func testInsertDeletedSuffixTaskDone() {
        let line = "- 2026-04-09T22:31+09:00 [task>done] finished"
        let result = StreamMutator.insertDeletedSuffix(line)
        XCTAssertEqual(result, "- 2026-04-09T22:31+09:00 [task>done>deleted] finished")
    }

    func testInsertDeletedSuffixIdempotent() {
        let line = "- 2026-04-09T22:31+09:00 [note>deleted] already deleted"
        let result = StreamMutator.insertDeletedSuffix(line)
        XCTAssertEqual(result, line, "Should not double-delete")
    }

    func testInsertDeletedSuffixNoBracket() {
        let line = "no brackets"
        let result = StreamMutator.insertDeletedSuffix(line)
        XCTAssertEqual(result, line, "Should return unchanged if no bracket found")
    }

    // MARK: - removeDeletedSuffix (pure)

    func testRemoveDeletedSuffix() {
        let line = "- 2026-04-09T22:31+09:00 [note>deleted] some insight"
        let result = StreamMutator.removeDeletedSuffix(line)
        XCTAssertEqual(result, "- 2026-04-09T22:31+09:00 [note] some insight")
    }

    func testRemoveDeletedSuffixFromTaskDone() {
        let line = "- 2026-04-09T22:31+09:00 [task>done>deleted] finished"
        let result = StreamMutator.removeDeletedSuffix(line)
        XCTAssertEqual(result, "- 2026-04-09T22:31+09:00 [task>done] finished")
    }

    func testRemoveDeletedSuffixNoop() {
        let line = "- 2026-04-09T22:31+09:00 [note] not deleted"
        let result = StreamMutator.removeDeletedSuffix(line)
        XCTAssertEqual(result, line)
    }

    // MARK: - Round-trip: insert + remove

    func testDeletedSuffixRoundTrip() {
        let original = "- 2026-04-09T22:31+09:00 [question] still a question?"
        let deleted = StreamMutator.insertDeletedSuffix(original)
        let restored = StreamMutator.removeDeletedSuffix(deleted)
        XCTAssertEqual(restored, original)
    }

    // MARK: - FS integration: editEntry

    func testEditEntryOnDisk() throws {
        let content = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T22:31:17+09:00 [note] old typo
        - 2026-04-09T20:15:00+09:00 [task] something else
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.editEntry(
            oldRawLine: "- 2026-04-09T22:31:17+09:00 [note] old typo",
            newContent: "fixed content",
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(result.contains("[note] fixed content"))
        XCTAssertFalse(result.contains("old typo"))
        // Other lines untouched:
        XCTAssertTrue(result.contains("[task] something else"))
        XCTAssertTrue(result.contains("--- 2026-04-09 Thursday ---"))
    }

    func testEditEntryThrowsOnMissingLine() throws {
        let content = "- 2026-04-09T22:31:17+09:00 [note] present\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try mutator.editEntry(
                oldRawLine: "- 2026-04-09T22:31:17+09:00 [note] absent",
                newContent: "fix",
                fileURL: tempFile
            )
        ) { error in
            XCTAssertTrue(error is StreamMutator.MutationError)
        }
    }

    func testEditEntryEmptyContentThrows() throws {
        let content = "- 2026-04-09T22:31:17+09:00 [note] something\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try mutator.editEntry(
                oldRawLine: "- 2026-04-09T22:31:17+09:00 [note] something",
                newContent: "   ",
                fileURL: tempFile
            )
        ) { error in
            XCTAssertTrue(error is StreamMutator.MutationError)
        }
    }

    // MARK: - FS integration: softDelete + undelete

    func testSoftDeleteOnDisk() throws {
        let content = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T22:31:17+09:00 [note] to be deleted
        - 2026-04-09T20:15:00+09:00 [task] keep this
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.softDelete(
            rawLine: "- 2026-04-09T22:31:17+09:00 [note] to be deleted",
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(result.contains("[note>deleted] to be deleted"))
        XCTAssertFalse(result.contains("[note] to be deleted"))
        XCTAssertTrue(result.contains("[task] keep this"))
    }

    func testUndeleteOnDisk() throws {
        let content = "- 2026-04-09T22:31:17+09:00 [note>deleted] was deleted\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.undelete(
            rawLine: "- 2026-04-09T22:31:17+09:00 [note>deleted] was deleted",
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(result.contains("[note] was deleted"))
        XCTAssertFalse(result.contains(">deleted"))
    }

    func testSoftDeleteThenUndeleteRoundTrip() throws {
        let original = "- 2026-04-09T22:31:17+09:00 [idea] ephemeral thought\n"
        try original.write(to: tempFile, atomically: true, encoding: .utf8)

        let rawLine = "- 2026-04-09T22:31:17+09:00 [idea] ephemeral thought"

        try mutator.softDelete(rawLine: rawLine, fileURL: tempFile)
        let afterDelete = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(afterDelete.contains("[idea>deleted]"))

        let deletedRawLine = StreamMutator.insertDeletedSuffix(rawLine)
        try mutator.undelete(rawLine: deletedRawLine, fileURL: tempFile)
        let afterUndo = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(afterUndo.contains("[idea] ephemeral thought"))
        XCTAssertFalse(afterUndo.contains(">deleted"))
    }

    // MARK: - Parser recognizes >deleted

    func testParserRecognizesDeletedEntry() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T22:31:17+09:00 [note>deleted] hidden entry
        - 2026-04-09T20:15:00+09:00 [note] visible entry
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].entries.count, 2)

        let deleted = sections[0].entries[0]
        XCTAssertTrue(deleted.isDeleted)
        XCTAssertEqual(deleted.bulletType, .note)
        XCTAssertEqual(deleted.content, "hidden entry")

        let visible = sections[0].entries[1]
        XCTAssertFalse(visible.isDeleted)
    }

    func testParserRecognizesDeletedTaskWithState() {
        let text = "- 2026-04-09T22:31:17+09:00 [task>done>deleted] old task\n"
        let sections = StreamParser.parse(text)
        let entry = sections[0].entries[0]
        XCTAssertTrue(entry.isDeleted)
        XCTAssertEqual(entry.bulletType, .task)
        XCTAssertEqual(entry.taskState, .done)
        XCTAssertEqual(entry.content, "old task")
    }

    // MARK: - removeLine (graduate)

    func testRemoveLineDeletesExactMatch() throws {
        let content = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00:00+08:00 [note] keep this
        - 2026-04-09T11:00:00+08:00 [idea] graduate me
        - 2026-04-09T12:00:00+08:00 [task] keep this too
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.removeLine(
            rawLine: "- 2026-04-09T11:00:00+08:00 [idea] graduate me",
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertFalse(result.contains("graduate me"))
        XCTAssertTrue(result.contains("keep this"))
        XCTAssertTrue(result.contains("keep this too"))
    }

    func testRemoveLineThrowsWhenNotFound() throws {
        let content = "- 2026-04-09T10:00:00+08:00 [note] only line"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try mutator.removeLine(
            rawLine: "- 2026-04-09T10:00:00+08:00 [note] missing",
            fileURL: tempFile
        ))
    }

    // MARK: - Edge cases

    func testEditFirstOccurrenceWhenDuplicateLines() throws {
        let content = """
        - 2026-04-09T22:31:17+09:00 [note] same content
        - 2026-04-09T22:31:17+09:00 [note] same content
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.editEntry(
            oldRawLine: "- 2026-04-09T22:31:17+09:00 [note] same content",
            newContent: "edited first",
            fileURL: tempFile
        )

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        let lines = result.components(separatedBy: "\n")
        // First occurrence edited, second unchanged.
        XCTAssertEqual(lines[0], "- 2026-04-09T22:31:17+09:00 [note] edited first")
        XCTAssertEqual(lines[1], "- 2026-04-09T22:31:17+09:00 [note] same content")
    }
}
