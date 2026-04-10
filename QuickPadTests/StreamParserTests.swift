import XCTest
@testable import QuickPad

/// Unit tests for `StreamParser`. The parser is pure (text in,
/// `[StreamSection]` out) so every test is a single `parse()` call
/// with hand-crafted input — no filesystem, no fixtures.
final class StreamParserTests: XCTestCase {

    // MARK: - Day separators

    func testParsesSingleDayWithOneEntry() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:30+09:00 [note] hello world
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].rawHeader, "--- 2026-04-09 Thursday ---")
        XCTAssertNotNil(sections[0].date)
        XCTAssertEqual(sections[0].entries.count, 1)
        XCTAssertEqual(sections[0].entries[0].content, "hello world")
        XCTAssertEqual(sections[0].entries[0].bulletType, .note)
    }

    func testParsesMultipleDays() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:30+09:00 [note] day two entry

        --- 2026-04-08 Wednesday ---

        - 2026-04-08T15:00+09:00 [task] day one entry
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].entries.count, 1)
        XCTAssertEqual(sections[0].entries[0].content, "day two entry")
        XCTAssertEqual(sections[1].entries.count, 1)
        XCTAssertEqual(sections[1].entries[0].content, "day one entry")
    }

    func testEntriesBeforeFirstSeparatorGoIntoImplicitBucket() {
        // Malformed-but-recoverable input: an entry without a leading
        // day separator. Parser should keep it rather than drop it,
        // housed in a section with date == nil.
        let text = """
        - 2026-04-09T10:30+09:00 [note] orphan before any day header

        --- 2026-04-09 Thursday ---

        - 2026-04-09T11:00+09:00 [note] normal entry
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.count, 2)
        XCTAssertNil(sections[0].date)
        XCTAssertNil(sections[0].rawHeader)
        XCTAssertEqual(sections[0].entries.count, 1)
        XCTAssertEqual(sections[0].entries[0].content, "orphan before any day header")
        XCTAssertEqual(sections[1].entries.count, 1)
    }

    func testEmptyFileProducesEmptySections() {
        XCTAssertEqual(StreamParser.parse("").count, 0)
        XCTAssertEqual(StreamParser.parse("\n\n\n").count, 0)
    }

    func testOnlyBlankLinesAreIgnored() {
        let text = """


        --- 2026-04-09 Thursday ---



        - 2026-04-09T10:30+09:00 [note] only entry


        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].entries.count, 1)
    }

    // MARK: - Bullet types and task states

    func testParsesAllBulletTypes() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [note] a note
        - 2026-04-09T10:01+09:00 [task] a task
        - 2026-04-09T10:02+09:00 [event] an event
        - 2026-04-09T10:03+09:00 [idea] an idea
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections[0].entries.map(\.bulletType), [.note, .task, .event, .idea])
    }

    func testParsesAllTaskStates() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [task] pending implicit
        - 2026-04-09T10:01+09:00 [task>done] done state
        - 2026-04-09T10:02+09:00 [task>migrated] migrated state
        - 2026-04-09T10:03+09:00 [task>cancelled] cancelled state
        """
        let sections = StreamParser.parse(text)
        let states = sections[0].entries.map(\.taskState)
        XCTAssertEqual(states, [.pending, .done, .migrated, .cancelled])
    }

    func testUnknownBulletTypeBecomesUnknownEntry() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [gibberish] something
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections[0].entries.count, 1)
        XCTAssertEqual(sections[0].entries[0].bulletType, .unknown)
        // rawLine preserved verbatim so future writes don't mangle it.
        XCTAssertTrue(sections[0].entries[0].rawLine.contains("[gibberish]"))
    }

    // MARK: - Timestamps

    func testMinutePrecisionTimestamps() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T22:31+09:00 [note] minute precision
        """
        let sections = StreamParser.parse(text)
        XCTAssertNotNil(sections[0].entries[0].timestamp)
    }

    func testSecondPrecisionTimestamps() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T22:31:17+09:00 [note] second precision
        """
        let sections = StreamParser.parse(text)
        XCTAssertNotNil(sections[0].entries[0].timestamp)
    }

    func testBothPrecisionsCoexistInSameFile() {
        // The parser must accept both shapes in the same file because
        // vim-edited entries often use minute precision while QuickPad
        // writes at second precision.
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T22:31+09:00 [note] minute
        - 2026-04-09T22:31:17+09:00 [note] second
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections[0].entries.count, 2)
        XCTAssertNotNil(sections[0].entries[0].timestamp)
        XCTAssertNotNil(sections[0].entries[1].timestamp)
    }

    // MARK: - Inline content markers

    func testPriorityMarkerIsExtracted() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [note] *priority important thing
        """
        let sections = StreamParser.parse(text)
        XCTAssertTrue(sections[0].entries[0].isPriority)
        XCTAssertEqual(sections[0].entries[0].content, "important thing")
    }

    func testPriorityCanComboWithPrefixTags() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [note] *priority read: SplatAD appendix B
        """
        let sections = StreamParser.parse(text)
        XCTAssertTrue(sections[0].entries[0].isPriority)
        XCTAssertEqual(sections[0].entries[0].prefixTag, "read")
    }

    func testPrefixTagsReadWatchListen() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [note] read: a paper
        - 2026-04-09T10:01+09:00 [note] watch: a video
        - 2026-04-09T10:02+09:00 [note] listen: a podcast
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections[0].entries.map(\.prefixTag), ["read", "watch", "listen"])
    }

    func testQuestionMarkPrefixBecomesExploreTag() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [idea] ? can we train on uncertainty?
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections[0].entries[0].prefixTag, "explore")
    }

    // MARK: - Data preservation

    func testRawLineIsPreservedVerbatim() {
        let original = "- 2026-04-09T10:00+09:00 [note] *priority read: SplatAD appendix B"
        let text = """
        --- 2026-04-09 Thursday ---

        \(original)
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections[0].entries[0].rawLine, original)
    }

    func testChineseContentRoundTrips() {
        let text = """
        --- 2026-04-09 Thursday ---

        - 2026-04-09T10:00+09:00 [note] 和标注组对齐点云密度标准 — 300pts@50m
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(
            sections[0].entries[0].content,
            "和标注组对齐点云密度标准 — 300pts@50m"
        )
    }

    func testMalformedLineBecomesUnknownPreservingRawLine() {
        // No bracket, no timestamp — totally broken entry. Parser
        // should keep it as .unknown with rawLine intact rather than
        // silently drop it.
        let text = """
        --- 2026-04-09 Thursday ---

        - totally garbage line
        """
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections[0].entries.count, 1)
        XCTAssertEqual(sections[0].entries[0].bulletType, .unknown)
        XCTAssertTrue(sections[0].entries[0].rawLine.contains("garbage"))
    }
}
