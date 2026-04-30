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

    // MARK: - Date-range filtering (⌘⇧E)

    /// Helper: ISO timestamp at noon on the given date (inclusive day).
    private func makeEntry(at day: String, content: String) -> StreamEntry {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        let ts = f.date(from: "\(day)T12:00:00+00:00")
        return StreamEntry(
            timestamp: ts,
            bulletType: .note,
            content: content,
            rawLine: "- \(day)T12:00:00+00:00 [note] \(content)"
        )
    }

    func testDateIntervalKeepsEntriesInsideAndDropsOutside() {
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = 2026; components.month = 4; components.day = 10
        let start = cal.date(from: components)!
        components.day = 13
        let end = cal.date(from: components)!  // half-open: include 10, 11, 12; exclude 13
        let interval = DateInterval(start: start, end: end)

        let inside1 = makeEntry(at: "2026-04-10", content: "in1")
        let inside2 = makeEntry(at: "2026-04-12", content: "in2")
        let outsideOld = makeEntry(at: "2026-04-09", content: "old")
        let outsideNew = makeEntry(at: "2026-04-14", content: "new")

        let section = StreamSection(
            date: nil,
            rawHeader: "--- bucket ---",
            entries: [inside1, inside2, outsideOld, outsideNew]
        )

        let result = StreamExporter.markdown(from: [section], dateInterval: interval)

        XCTAssertTrue(result.contains("in1"))
        XCTAssertTrue(result.contains("in2"))
        XCTAssertFalse(result.contains("old"))
        XCTAssertFalse(result.contains("new"))
    }

    func testDateIntervalSkipsSectionsThatHaveNoSurvivingEntries() {
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = 2026; components.month = 4; components.day = 10
        let start = cal.date(from: components)!
        components.day = 11
        let end = cal.date(from: components)!
        let interval = DateInterval(start: start, end: end)

        // Section A has an in-range entry; section B's only entry is out of range.
        let secA = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-10 ---",
            entries: [makeEntry(at: "2026-04-10", content: "kept")]
        )
        let secB = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-09 ---",
            entries: [makeEntry(at: "2026-04-09", content: "dropped")]
        )

        let result = StreamExporter.markdown(from: [secA, secB], dateInterval: interval)
        XCTAssertTrue(result.contains("kept"))
        XCTAssertFalse(result.contains("dropped"))
        // Empty section's header should NOT be emitted.
        XCTAssertFalse(result.contains("2026-04-09"))
    }

    func testDateIntervalNilMatchesLegacyBehavior() {
        let entry = makeEntry(at: "2026-04-10", content: "x")
        let section = StreamSection(
            date: nil,
            rawHeader: "--- 2026-04-10 ---",
            entries: [entry]
        )
        let withNil = StreamExporter.markdown(from: [section], dateInterval: nil)
        let withoutArg = StreamExporter.markdown(from: [section])
        XCTAssertEqual(withNil, withoutArg)
    }

    func testDateIntervalDropsEntriesWithoutTimestamp() {
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            duration: 100_000_000
        )
        let noTimestamp = StreamEntry(
            timestamp: nil,
            bulletType: .note,
            content: "ts-less",
            rawLine: "- (no timestamp) [note] ts-less"
        )
        let section = StreamSection(
            date: nil,
            rawHeader: "--- bucket ---",
            entries: [noTimestamp]
        )
        let result = StreamExporter.markdown(from: [section], dateInterval: interval)
        XCTAssertFalse(result.contains("ts-less"))
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
