import XCTest
@testable import QuickPad

/// Covers `StreamEntry.shouldShowGraduateHint`. The hint surfaces a
/// graduate suggestion in the everyday stream once an entry has been
/// rescued enough times to look like it deserves its own pinned note.
final class GraduateHintTests: XCTestCase {

    private func makeEntry(
        bulletType: BulletType = .note,
        taskState: TaskState? = nil,
        rescueCount: Int = 0,
        isDeleted: Bool = false
    ) -> StreamEntry {
        StreamEntry(
            timestamp: nil,
            bulletType: bulletType,
            taskState: taskState,
            content: "x",
            isDeleted: isDeleted,
            rescueCount: rescueCount,
            rawLine: "- 2026-04-30T10:00:00+08:00 [\(bulletType.rawValue) @r\(rescueCount)] x"
        )
    }

    func testBelowThresholdDoesNotShow() {
        let e = makeEntry(rescueCount: StreamEntry.graduateHintThreshold - 1)
        XCTAssertFalse(e.shouldShowGraduateHint)
    }

    func testAtThresholdShows() {
        let e = makeEntry(rescueCount: StreamEntry.graduateHintThreshold)
        XCTAssertTrue(e.shouldShowGraduateHint)
    }

    func testAboveThresholdShows() {
        let e = makeEntry(rescueCount: StreamEntry.graduateHintThreshold + 5)
        XCTAssertTrue(e.shouldShowGraduateHint)
    }

    func testDoneTaskDoesNotShow() {
        let e = makeEntry(
            bulletType: .task,
            taskState: .done,
            rescueCount: StreamEntry.graduateHintThreshold + 1
        )
        XCTAssertFalse(e.shouldShowGraduateHint)
    }

    func testCancelledTaskDoesNotShow() {
        let e = makeEntry(
            bulletType: .task,
            taskState: .cancelled,
            rescueCount: StreamEntry.graduateHintThreshold + 1
        )
        XCTAssertFalse(e.shouldShowGraduateHint)
    }

    func testPendingTaskShows() {
        let e = makeEntry(
            bulletType: .task,
            taskState: .pending,
            rescueCount: StreamEntry.graduateHintThreshold
        )
        XCTAssertTrue(e.shouldShowGraduateHint)
    }

    func testDeletedDoesNotShow() {
        let e = makeEntry(
            rescueCount: StreamEntry.graduateHintThreshold + 2,
            isDeleted: true
        )
        XCTAssertFalse(e.shouldShowGraduateHint)
    }

    func testUnknownBulletDoesNotShow() {
        let e = makeEntry(
            bulletType: .unknown,
            rescueCount: StreamEntry.graduateHintThreshold + 2
        )
        XCTAssertFalse(e.shouldShowGraduateHint)
    }
}
