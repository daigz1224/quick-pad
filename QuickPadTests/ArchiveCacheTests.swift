import XCTest
@testable import QuickPad

/// Covers the archive-cache fast path on `MarkdownFileStore.loadArchives`.
/// Uses a per-test temp directory so we never read or write the real
/// `~/.quickpad/archive/`.
final class ArchiveCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("quickpad-archive-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        // Each test starts with a clean cache so we're not measuring an
        // earlier test's residue.
        MarkdownFileStore.invalidateArchiveCache()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        MarkdownFileStore.invalidateArchiveCache()
    }

    private func writeArchive(name: String, content: String) throws {
        try content.write(
            to: tempDir.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    func testEmptyDirectoryReturnsEmpty() {
        let result = MarkdownFileStore().loadArchives(directoryURL: tempDir)
        XCTAssertEqual(result.count, 0)
    }

    func testNonExistentDirectoryReturnsEmpty() {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let result = MarkdownFileStore().loadArchives(directoryURL: missing)
        XCTAssertEqual(result.count, 0)
    }

    func testCacheReturnsSameInstanceWhenDirectoryUnchanged() throws {
        try writeArchive(name: "2026-03.md", content: """
        --- 2026-03-15 Sunday ---

        - 2026-03-15T10:00:00+08:00 [note] cached entry
        """)

        let store = MarkdownFileStore()
        let first = store.loadArchives(directoryURL: tempDir)
        let second = store.loadArchives(directoryURL: tempDir)

        XCTAssertEqual(first.count, second.count)
        XCTAssertGreaterThan(first.count, 0)
        // Section IDs are stable when reading from cache (we don't
        // re-parse), proving we got the cached value back.
        XCTAssertEqual(first.first?.id, second.first?.id)
    }

    func testCacheInvalidatesWhenFileAdded() throws {
        try writeArchive(name: "2026-03.md", content: """
        --- 2026-03-15 Sunday ---

        - 2026-03-15T10:00:00+08:00 [note] first
        """)

        let store = MarkdownFileStore()
        let initial = store.loadArchives(directoryURL: tempDir)
        let initialFlatCount = initial.flatMap { $0.entries }.count

        // Sleep briefly so the new file's mtime is distinct from the
        // first one (HFS+/APFS mtime resolution is sub-second but the
        // directory listing scan can collapse same-second timestamps).
        Thread.sleep(forTimeInterval: 1.05)

        try writeArchive(name: "2026-04.md", content: """
        --- 2026-04-01 Wednesday ---

        - 2026-04-01T10:00:00+08:00 [note] second
        """)

        let after = store.loadArchives(directoryURL: tempDir)
        let afterFlatCount = after.flatMap { $0.entries }.count

        XCTAssertGreaterThan(afterFlatCount, initialFlatCount)
    }

    func testInvalidateForcesReparse() throws {
        try writeArchive(name: "a.md", content: """
        --- 2026-03-15 Sunday ---

        - 2026-03-15T10:00:00+08:00 [note] before
        """)

        let store = MarkdownFileStore()
        let first = store.loadArchives(directoryURL: tempDir)
        XCTAssertTrue(
            first.flatMap { $0.entries }.contains { $0.content == "before" }
        )

        // Modify the same file in place. Without invalidation, the
        // cached parse may still be returned (mtime resolution boundary).
        try writeArchive(name: "a.md", content: """
        --- 2026-03-15 Sunday ---

        - 2026-03-15T10:00:00+08:00 [note] after
        """)
        MarkdownFileStore.invalidateArchiveCache()

        let second = store.loadArchives(directoryURL: tempDir)
        XCTAssertTrue(
            second.flatMap { $0.entries }.contains { $0.content == "after" }
        )
    }
}
