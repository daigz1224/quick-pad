import XCTest
@testable import QuickPad

/// Tests for `StreamWriter`. Split into two groups:
///
/// 1. `buildAppended` — the pure string-in / string-out core. Runs
///    without touching the filesystem, deterministic, asserts the
///    exact cosmetic shape of the written file.
/// 2. `append(...)` — the FS-side wrapper. Uses a temp directory so
///    tests run in parallel safely and clean up after themselves.
final class StreamWriterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickPadTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Reproduces the writer's timestamp formatter so we can compute
    /// the expected string without hardcoding a timezone (tests must
    /// pass in any locale/TZ configuration).
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "EEEE"
        return f
    }()

    private func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 0, _ s: Int = 0) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = h
        components.minute = min
        components.second = s
        components.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func expectedSeparator(for date: Date) -> String {
        "--- \(Self.dayFormatter.string(from: date)) \(Self.weekdayFormatter.string(from: date)) ---"
    }

    private func expectedTimestamp(for date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }

    // MARK: - buildAppended: empty-file case

    func testAppendToEmptyFileCreatesSeparatorAndEntry() {
        let now = makeDate(2026, 4, 9, 10, 0, 0)
        let out = StreamWriter.buildAppended(
            existing: "",
            bulletType: .note,
            content: "hello",
            now: now
        )

        let expected = """
        \(expectedSeparator(for: now))

        - \(expectedTimestamp(for: now)) [note] hello

        """
        XCTAssertEqual(out, expected)
    }

    // MARK: - buildAppended: same-day append

    func testSameDayAppendHasNoBlankLineBetweenEntries() {
        // The cosmetic contract: same-day entries are contiguous. A
        // blank line between entries is only used to separate days.
        let first = makeDate(2026, 4, 9, 10, 0, 0)
        let second = makeDate(2026, 4, 9, 11, 0, 0)

        let afterFirst = StreamWriter.buildAppended(
            existing: "",
            bulletType: .note,
            content: "first",
            now: first
        )
        let afterSecond = StreamWriter.buildAppended(
            existing: afterFirst,
            bulletType: .task,
            content: "second",
            now: second
        )

        let expected = """
        \(expectedSeparator(for: first))

        - \(expectedTimestamp(for: first)) [note] first
        - \(expectedTimestamp(for: second)) [task] second

        """
        XCTAssertEqual(afterSecond, expected)
    }

    func testSameDayAppendDoesNotDuplicateSeparator() {
        let first = makeDate(2026, 4, 9, 10, 0, 0)
        let second = makeDate(2026, 4, 9, 11, 0, 0)

        let afterFirst = StreamWriter.buildAppended(
            existing: "",
            bulletType: .note,
            content: "first",
            now: first
        )
        let afterSecond = StreamWriter.buildAppended(
            existing: afterFirst,
            bulletType: .note,
            content: "second",
            now: second
        )

        // Exactly one day separator in the final output.
        let separator = expectedSeparator(for: first)
        let occurrences = afterSecond.components(separatedBy: separator).count - 1
        XCTAssertEqual(occurrences, 1)
    }

    // MARK: - buildAppended: new-day append

    func testNewDayAppendInsertsSeparatorWithBlankLineBoundary() {
        // Yesterday's content already in the file, today's append
        // should insert a new day separator and leave a blank line
        // boundary between the old day and the new one.
        let yesterday = makeDate(2026, 4, 8, 15, 0, 0)
        let today = makeDate(2026, 4, 9, 10, 0, 0)

        let existing = StreamWriter.buildAppended(
            existing: "",
            bulletType: .note,
            content: "yesterday's entry",
            now: yesterday
        )
        let out = StreamWriter.buildAppended(
            existing: existing,
            bulletType: .idea,
            content: "today's entry",
            now: today
        )

        let expected = """
        \(expectedSeparator(for: yesterday))

        - \(expectedTimestamp(for: yesterday)) [note] yesterday's entry

        \(expectedSeparator(for: today))

        - \(expectedTimestamp(for: today)) [idea] today's entry

        """
        XCTAssertEqual(out, expected)
    }

    // MARK: - buildAppended: content transformations

    func testStarPrefixShortcutExpandsToPriority() {
        let now = makeDate(2026, 4, 9)
        let out = StreamWriter.buildAppended(
            existing: "",
            bulletType: .note,
            content: "* urgent fix",
            now: now
        )
        XCTAssertTrue(out.contains("[note] *priority urgent fix"))
        // The raw `* ` is gone — we expanded it, we don't double-write.
        XCTAssertFalse(out.contains("[note] * urgent fix"))
    }

    func testBareStarIsNotTreatedAsPriority() {
        // Only `* ` (star + space) is the shortcut. A literal `*` at
        // the start should pass through unchanged.
        let now = makeDate(2026, 4, 9)
        let out = StreamWriter.buildAppended(
            existing: "",
            bulletType: .note,
            content: "*stars",
            now: now
        )
        XCTAssertTrue(out.contains("[note] *stars"))
        XCTAssertFalse(out.contains("*priority"))
    }

    func testUnknownBulletTypeFallsBackToNote() {
        // `.unknown` is a parser-only sentinel, it should never end up
        // written back to disk. The writer maps it to `note`.
        let now = makeDate(2026, 4, 9)
        let out = StreamWriter.buildAppended(
            existing: "",
            bulletType: .unknown,
            content: "whatever",
            now: now
        )
        XCTAssertTrue(out.contains("[note] whatever"))
        XCTAssertFalse(out.contains("[unknown]"))
    }

    func testAllBulletTypesRenderTheirRawValue() {
        let now = makeDate(2026, 4, 9)
        for type in [BulletType.note, .task, .event, .idea] {
            let out = StreamWriter.buildAppended(
                existing: "",
                bulletType: type,
                content: "body",
                now: now
            )
            XCTAssertTrue(
                out.contains("[\(type.rawValue)] body"),
                "expected [\(type.rawValue)] in output, got: \(out)"
            )
        }
    }

    // MARK: - buildAppended: newline normalization

    func testTrailingWhitespaceAndNewlinesAreNormalized() {
        // Input with a messy trailing tail — extra blank lines, CR,
        // trailing spaces. Output should still end with exactly one
        // newline (no accumulation).
        let now = makeDate(2026, 4, 9, 11, 0, 0)
        let dirty = "--- 2026-04-09 Thursday ---\n\n- 2026-04-09T10:00:00+09:00 [note] first\n\n\n   \n"
        let out = StreamWriter.buildAppended(
            existing: dirty,
            bulletType: .note,
            content: "second",
            now: now
        )
        // Ends with exactly one trailing newline.
        XCTAssertTrue(out.hasSuffix("\n"))
        XCTAssertFalse(out.hasSuffix("\n\n\n"))
    }

    // MARK: - buildAppended + parser round-trip

    func testWrittenOutputIsParseableByStreamParser() {
        // The two sides of the Store must agree on the format. If the
        // writer produces something the parser can't read, everything
        // downstream silently breaks.
        let first = makeDate(2026, 4, 9, 10, 0, 0)
        let second = makeDate(2026, 4, 9, 11, 30, 0)
        let third = makeDate(2026, 4, 10, 9, 15, 0)

        var text = ""
        text = StreamWriter.buildAppended(
            existing: text, bulletType: .note, content: "first", now: first
        )
        text = StreamWriter.buildAppended(
            existing: text, bulletType: .task, content: "second", now: second
        )
        text = StreamWriter.buildAppended(
            existing: text, bulletType: .idea, content: "third", now: third
        )

        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].entries.count, 2)
        XCTAssertEqual(sections[0].entries[0].content, "first")
        XCTAssertEqual(sections[0].entries[0].bulletType, .note)
        XCTAssertEqual(sections[0].entries[1].content, "second")
        XCTAssertEqual(sections[0].entries[1].bulletType, .task)
        XCTAssertEqual(sections[1].entries.count, 1)
        XCTAssertEqual(sections[1].entries[0].content, "third")
        XCTAssertEqual(sections[1].entries[0].bulletType, .idea)
    }

    // MARK: - append(...): filesystem integration

    func testAppendCreatesFileAndDirectoryWhenMissing() throws {
        let nested = tempDir
            .appendingPathComponent(".quickpad")
            .appendingPathComponent("stream.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))

        let writer = StreamWriter()
        try writer.append(
            bulletType: .note,
            content: "first ever",
            at: Date(),
            fileURL: nested
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
        let text = try String(contentsOf: nested, encoding: .utf8)
        XCTAssertTrue(text.contains("[note] first ever"))
    }

    func testAppendThrowsOnEmptyContent() {
        let url = tempDir.appendingPathComponent("stream.md")
        let writer = StreamWriter()
        XCTAssertThrowsError(try writer.append(bulletType: .note, content: "", fileURL: url))
        XCTAssertThrowsError(try writer.append(bulletType: .note, content: "   \n\t", fileURL: url))
        // File should not have been created by a failed write.
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAppendIsAtomicAcrossMultipleCalls() throws {
        // Two back-to-back appends must both land in the file. This
        // also verifies replaceItemAt works correctly on an existing
        // file (the second append exercises that code path).
        let url = tempDir.appendingPathComponent("stream.md")
        let writer = StreamWriter()

        try writer.append(bulletType: .note, content: "one", fileURL: url)
        try writer.append(bulletType: .task, content: "two", fileURL: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("[note] one"))
        XCTAssertTrue(text.contains("[task] two"))
    }
}
