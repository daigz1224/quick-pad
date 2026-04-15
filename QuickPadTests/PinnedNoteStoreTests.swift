import XCTest
@testable import QuickPad

final class PinnedNoteStoreTests: XCTestCase {

    private var tempDir: URL!
    private let store = PinnedNoteStore()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickpad-pinned-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Slug

    func testSlugBasicAscii() {
        XCTAssertEqual(
            PinnedNoteStore.slug(for: "Build the new dashboard"),
            "build-the-new-dashboard"
        )
    }

    func testSlugStripsPriorityPrefix() {
        XCTAssertEqual(
            PinnedNoteStore.slug(for: "*priority ship the migration"),
            "ship-the-migration"
        )
    }

    func testSlugStripsReadPrefix() {
        XCTAssertEqual(
            PinnedNoteStore.slug(for: "read: SplatAD appendix B"),
            "splatad-appendix-b"
        )
    }

    func testSlugCollapsesDashes() {
        XCTAssertEqual(
            PinnedNoteStore.slug(for: "foo   bar  --  baz"),
            "foo-bar-baz"
        )
    }

    func testSlugDropsCJKAndFallsBackOnAllCJK() {
        // Pure CJK -> empty after filtering -> date-stamped fallback.
        let slug = PinnedNoteStore.slug(for: "全中文内容")
        XCTAssertTrue(slug.hasPrefix("note-"), "got: \(slug)")
        XCTAssertEqual(slug.count, "note-".count + 8)
    }

    func testSlugTruncatesAtBoundary() {
        let long = String(repeating: "word-", count: 30) // 150 chars
        let slug = PinnedNoteStore.slug(for: long)
        XCTAssertLessThanOrEqual(slug.count, 48)
        XCTAssertFalse(slug.hasSuffix("-"))
    }

    // MARK: - uniqueURL

    func testUniqueURLAppendsSuffixOnCollision() throws {
        let base = tempDir.appendingPathComponent("foo.md")
        try "x".write(to: base, atomically: true, encoding: .utf8)

        let next = PinnedNoteStore.uniqueURL(for: "foo", in: tempDir)
        XCTAssertEqual(next.lastPathComponent, "foo-2.md")

        try "x".write(to: next, atomically: true, encoding: .utf8)
        let third = PinnedNoteStore.uniqueURL(for: "foo", in: tempDir)
        XCTAssertEqual(third.lastPathComponent, "foo-3.md")
    }

    // MARK: - Markdown rendering

    func testRenderMarkdownIncludesOriginAndContent() {
        let entry = StreamEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            bulletType: .idea,
            content: "Distill review pipeline",
            rawLine: "- 2023-11-14T... [idea] Distill review pipeline"
        )
        let md = PinnedNoteStore.renderMarkdown(entry: entry, now: Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertTrue(md.contains("# Distill review pipeline"))
        XCTAssertTrue(md.contains("`[idea]`"))
        XCTAssertTrue(md.contains("graduated from stream on"))
        XCTAssertTrue(md.contains("origin:"))
        XCTAssertTrue(md.hasSuffix("Distill review pipeline\n"))
    }

    // MARK: - graduate (file write)

    func testGraduateWritesFileAndReturnsURL() throws {
        let entry = StreamEntry(
            timestamp: Date(),
            bulletType: .note,
            content: "Onboarding doc draft",
            rawLine: "- ts [note] Onboarding doc draft"
        )
        let url = try store.graduate(entry: entry, directoryURL: tempDir)
        XCTAssertEqual(url.lastPathComponent, "onboarding-doc-draft.md")
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(body.contains("# Onboarding doc draft"))
    }

    func testGraduateAvoidsOverwriteOnSecondCall() throws {
        let entry = StreamEntry(
            timestamp: Date(),
            bulletType: .note,
            content: "Same title",
            rawLine: "- ts [note] Same title"
        )
        let first = try store.graduate(entry: entry, directoryURL: tempDir)
        let second = try store.graduate(entry: entry, directoryURL: tempDir)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "same-title-2.md")
    }

    // MARK: - list

    func testListReturnsMarkdownFilesNewestFirst() throws {
        let a = tempDir.appendingPathComponent("alpha.md")
        let b = tempDir.appendingPathComponent("beta.md")
        let c = tempDir.appendingPathComponent("ignore.txt")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "c".write(to: c, atomically: true, encoding: .utf8)
        // Touch `b` last so it's most recently modified.
        Thread.sleep(forTimeInterval: 0.05)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        let urls = store.list(directoryURL: tempDir)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.first?.lastPathComponent, "beta.md")
        XCTAssertEqual(urls.last?.lastPathComponent, "alpha.md")
    }

    func testListReturnsEmptyWhenDirectoryMissing() {
        let missing = tempDir.appendingPathComponent("nope")
        XCTAssertEqual(store.list(directoryURL: missing), [])
    }
}
