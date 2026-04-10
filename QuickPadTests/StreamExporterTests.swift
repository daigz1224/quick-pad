import XCTest
@testable import QuickPad

final class StreamExporterTests: XCTestCase {

    // MARK: - markdown(from:)

    func testEmptySectionsProducesEmptyOutput() {
        let result = StreamExporter.markdown(from: [])
        XCTAssertEqual(result.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testSingleSectionWithEntries() {
        let entry1 = StreamEntry(
            timestamp: nil, bulletType: .note,
            content: "hello", rawLine: "- 2026-04-10T10:00:00+08:00 [note] hello"
        )
        let entry2 = StreamEntry(
            timestamp: nil, bulletType: .task,
            content: "world", rawLine: "- 2026-04-10T11:00:00+08:00 [task] world"
        )
        let section = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-10 Friday ---",
            entries: [entry1, entry2]
        )

        let result = StreamExporter.markdown(from: [section])
        XCTAssertTrue(result.contains("--- 2026-04-10 Friday ---"))
        XCTAssertTrue(result.contains("[note] hello"))
        XCTAssertTrue(result.contains("[task] world"))
    }

    func testMultipleSectionsHaveBlankLineBetween() {
        let s1 = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-10 Friday ---",
            entries: [StreamEntry(
                timestamp: nil, bulletType: .note,
                content: "a", rawLine: "- 2026-04-10T10:00:00+08:00 [note] a"
            )]
        )
        let s2 = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-09 Thursday ---",
            entries: [StreamEntry(
                timestamp: nil, bulletType: .note,
                content: "b", rawLine: "- 2026-04-09T10:00:00+08:00 [note] b"
            )]
        )

        let result = StreamExporter.markdown(from: [s1, s2])
        // Should have a blank line between sections.
        XCTAssertTrue(result.contains("[note] a\n\n--- 2026-04-09"))
    }

    func testDeletedEntriesAreExcluded() {
        var deleted = StreamEntry(
            timestamp: nil, bulletType: .note,
            content: "gone", rawLine: "- 2026-04-10T10:00:00+08:00 [note>deleted] gone"
        )
        deleted.isDeleted = true

        let kept = StreamEntry(
            timestamp: nil, bulletType: .note,
            content: "kept", rawLine: "- 2026-04-10T11:00:00+08:00 [note] kept"
        )

        let section = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-10 Friday ---",
            entries: [deleted, kept]
        )

        let result = StreamExporter.markdown(from: [section])
        XCTAssertFalse(result.contains("gone"))
        XCTAssertTrue(result.contains("kept"))
    }

    func testOutputEndsWithTrailingNewline() {
        let section = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-10 Friday ---",
            entries: [StreamEntry(
                timestamp: nil, bulletType: .note,
                content: "x", rawLine: "- 2026-04-10T10:00:00+08:00 [note] x"
            )]
        )
        let result = StreamExporter.markdown(from: [section])
        XCTAssertTrue(result.hasSuffix("\n"))
    }

    func testRoundTripWithParser() {
        // Export then re-parse should preserve structure.
        let original = """
        --- 2026-04-10 Friday ---

        - 2026-04-10T10:00:00+08:00 [note] hello
        - 2026-04-10T09:00:00+08:00 [task] world

        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00:00+08:00 [idea] cool
        """
        let parsed = StreamParser.parse(original)
        let exported = StreamExporter.markdown(from: parsed)
        let reparsed = StreamParser.parse(exported)

        XCTAssertEqual(reparsed.count, parsed.count)
        XCTAssertEqual(reparsed[0].entries.count, parsed[0].entries.count)
        XCTAssertEqual(reparsed[1].entries.count, parsed[1].entries.count)
        XCTAssertEqual(reparsed[0].entries[0].content, "hello")
        XCTAssertEqual(reparsed[1].entries[0].content, "cool")
    }
}
