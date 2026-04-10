import XCTest
@testable import QuickPad

final class TaskStateTests: XCTestCase {

    func testBareTaskTokenParsesAsPending() {
        // `[task]` with no suffix is the implicit pending state.
        XCTAssertEqual(TaskState.parse(token: "task"), .pending)
    }

    func testParseKnownSuffixes() {
        XCTAssertEqual(TaskState.parse(token: "task>done"), .done)
        XCTAssertEqual(TaskState.parse(token: "task>migrated"), .migrated)
        XCTAssertEqual(TaskState.parse(token: "task>cancelled"), .cancelled)
    }

    func testParseUnknownSuffixReturnsNil() {
        XCTAssertNil(TaskState.parse(token: "task>garbage"))
        XCTAssertNil(TaskState.parse(token: "task>"))
    }

    func testGlyphMapping() {
        // Snapshot: these glyphs leak into the UI column directly,
        // silent changes would shift the visual identity of tasks.
        XCTAssertEqual(TaskState.pending.glyph, "☐")
        XCTAssertEqual(TaskState.done.glyph, "✓")
        XCTAssertEqual(TaskState.migrated.glyph, "▶")
        XCTAssertEqual(TaskState.cancelled.glyph, "✕")
    }
}
