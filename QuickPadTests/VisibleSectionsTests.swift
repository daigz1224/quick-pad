import XCTest
@testable import QuickPad

/// Covers `StreamViewModel.applyVisibilityFilter` — the static helper
/// that drops soft-deleted entries and (when given) restricts to a
/// single bullet type. Cheap to test as pure logic without standing up
/// the full `@Observable` view model and its disk-backed loader.
final class VisibleSectionsTests: XCTestCase {

    private func entry(
        bulletType: BulletType = .note,
        isDeleted: Bool = false,
        content: String = "x"
    ) -> StreamEntry {
        StreamEntry(
            timestamp: nil,
            bulletType: bulletType,
            content: content,
            isDeleted: isDeleted,
            rawLine: "- ts [\(bulletType.rawValue)] \(content)"
        )
    }

    func testDropsSoftDeletedEntries() {
        let section = StreamSection(
            date: nil,
            rawHeader: "--- d ---",
            entries: [
                entry(content: "kept"),
                entry(isDeleted: true, content: "gone"),
            ]
        )
        let result = StreamViewModel.applyVisibilityFilter([section], typeFilter: nil)
        XCTAssertEqual(result.first?.entries.count, 1)
        XCTAssertEqual(result.first?.entries.first?.content, "kept")
    }

    func testTypeFilterKeepsMatchingTypeOnly() {
        let section = StreamSection(
            date: nil,
            rawHeader: "--- d ---",
            entries: [
                entry(bulletType: .note, content: "n"),
                entry(bulletType: .task, content: "t"),
                entry(bulletType: .idea, content: "i"),
            ]
        )
        let result = StreamViewModel.applyVisibilityFilter([section], typeFilter: .task)
        XCTAssertEqual(result.first?.entries.count, 1)
        XCTAssertEqual(result.first?.entries.first?.bulletType, .task)
    }

    func testSectionWithNothingLeftIsDropped() {
        let section = StreamSection(
            date: nil,
            rawHeader: "--- d ---",
            entries: [
                entry(bulletType: .note, content: "n"),
                entry(bulletType: .idea, content: "i"),
            ]
        )
        let result = StreamViewModel.applyVisibilityFilter([section], typeFilter: .task)
        XCTAssertTrue(result.isEmpty)
    }

    func testReturnsOriginalSectionWhenNothingFiltered() {
        let original = StreamSection(
            date: nil,
            rawHeader: "--- d ---",
            entries: [entry(content: "a"), entry(content: "b")]
        )
        let result = StreamViewModel.applyVisibilityFilter([original], typeFilter: nil)
        // Same id means no copy/recreate happened — the fast path is hit.
        XCTAssertEqual(result.first?.id, original.id)
    }

    func testEmptyHeaderOnlySectionSurvives() {
        // Sections with a header but no entries (e.g. an empty day
        // separator left behind after archiving) are kept so the day
        // separator continues to render — matches Phase 1 behavior.
        let section = StreamSection(
            date: nil,
            rawHeader: "--- d ---",
            entries: []
        )
        let result = StreamViewModel.applyVisibilityFilter([section], typeFilter: nil)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, section.id)
    }
}
