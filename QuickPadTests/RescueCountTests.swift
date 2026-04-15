import XCTest
@testable import QuickPad

final class RescueCountTests: XCTestCase {

    private var tempDir: URL!
    private var tempFile: URL!
    private let mutator = StreamMutator()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickpad-rescue-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempFile = tempDir.appendingPathComponent("stream.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - extractRescueCount (pure)

    func testExtractMissingReturnsZero() {
        let result = StreamMutator.extractRescueCount(fromToken: "task")
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.cleaned, "task")
    }

    func testExtractSimpleCount() {
        let result = StreamMutator.extractRescueCount(fromToken: "task @r3")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.cleaned, "task")
    }

    func testExtractCountWithTaskState() {
        let result = StreamMutator.extractRescueCount(fromToken: "task>done @r5")
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.cleaned, "task>done")
    }

    func testExtractCountWithDeleted() {
        let result = StreamMutator.extractRescueCount(fromToken: "task>done>deleted @r2")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.cleaned, "task>done>deleted")
    }

    func testSetRescueCountAppendsWhenNonZero() {
        XCTAssertEqual(StreamMutator.setRescueCount(inToken: "note", count: 4), "note @r4")
    }

    func testSetRescueCountStripsWhenZero() {
        XCTAssertEqual(StreamMutator.setRescueCount(inToken: "task @r3", count: 0), "task")
    }

    func testSetRescueCountReplacesExisting() {
        XCTAssertEqual(StreamMutator.setRescueCount(inToken: "task @r3", count: 7), "task @r7")
    }

    // MARK: - bumpRescueCount

    func testBumpFromZeroAddsR1() {
        let result = StreamMutator.bumpRescueCount(inRawLine: "- 2026-04-09T10:00:00+08:00 [task] foo")
        XCTAssertEqual(result, "- 2026-04-09T10:00:00+08:00 [task @r1] foo")
    }

    func testBumpIncrementsExisting() {
        let result = StreamMutator.bumpRescueCount(inRawLine: "- 2026-04-09T10:00:00+08:00 [idea @r4] foo")
        XCTAssertEqual(result, "- 2026-04-09T10:00:00+08:00 [idea @r5] foo")
    }

    func testBumpPreservesTaskStateAndDeleted() {
        let result = StreamMutator.bumpRescueCount(inRawLine: "- ts [task>done>deleted @r2] foo")
        XCTAssertEqual(result, "- ts [task>done>deleted @r3] foo")
    }

    // MARK: - Parser integration

    func testParserExtractsCountWhenPresent() {
        let text = "- 2026-04-09T10:00:00+08:00 [task @r3] do the thing"
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.first?.entries.first?.rescueCount, 3)
        XCTAssertEqual(sections.first?.entries.first?.bulletType, .task)
        XCTAssertEqual(sections.first?.entries.first?.content, "do the thing")
    }

    func testParserDefaultsToZeroWhenMissing() {
        let text = "- 2026-04-09T10:00:00+08:00 [note] hi"
        let sections = StreamParser.parse(text)
        XCTAssertEqual(sections.first?.entries.first?.rescueCount, 0)
    }

    func testParserHandlesCountWithTaskStateAndDeleted() {
        let text = "- 2026-04-09T10:00:00+08:00 [task>done>deleted @r5] yo"
        let sections = StreamParser.parse(text)
        let entry = sections.first?.entries.first
        XCTAssertEqual(entry?.rescueCount, 5)
        XCTAssertEqual(entry?.taskState, .done)
        XCTAssertTrue(entry?.isDeleted ?? false)
    }

    // MARK: - Mutation interactions

    func testInsertDeletedSuffixPreservesCount() {
        let result = StreamMutator.insertDeletedSuffix("- ts [note @r2] foo")
        XCTAssertEqual(result, "- ts [note>deleted @r2] foo")
    }

    func testInsertDeletedSuffixIdempotentWithCount() {
        let already = "- ts [note>deleted @r2] foo"
        XCTAssertEqual(StreamMutator.insertDeletedSuffix(already), already)
    }

    func testReplaceTaskStatePreservesCount() {
        let result = StreamMutator.replaceTaskState(rawLine: "- ts [task @r3] foo", newState: .done)
        XCTAssertEqual(result, "- ts [task>done @r3] foo")
    }

    func testReplaceBulletTypePreservesCount() {
        let result = StreamMutator.replaceBulletType(rawLine: "- ts [task @r3] foo", newType: .idea)
        XCTAssertEqual(result, "- ts [idea @r3] foo")
    }

    // MARK: - End-to-end rescue increments count on disk

    func testRescueBumpsCountAndFlipsTimestamp() throws {
        let yesterday = Date().addingTimeInterval(-86400 * 3)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        let oldDay = f.string(from: yesterday)

        let content = """
        --- \(oldDay) Friday ---

        - \(isoTimestamp(yesterday)) [idea] something old
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        let target = "- \(isoTimestamp(yesterday)) [idea] something old"
        try mutator.rescue(rawLine: target, fileURL: tempFile)

        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(result.contains("[idea @r1] something old"),
                      "expected @r1 in rescued line; got:\n\(result)")
    }

    func testRescueIncrementsExistingCount() throws {
        let yesterday = Date().addingTimeInterval(-86400 * 3)
        let target = "- \(isoTimestamp(yesterday)) [idea @r4] been here before"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        let oldDay = f.string(from: yesterday)

        let content = """
        --- \(oldDay) Friday ---

        \(target)
        """
        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        try mutator.rescue(rawLine: target, fileURL: tempFile)
        let result = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertTrue(result.contains("[idea @r5] been here before"))
    }

    private func isoTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f.string(from: date)
    }
}
