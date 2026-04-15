import XCTest
@testable import QuickPad

final class BulletTypeTests: XCTestCase {

    func testNextCyclesThroughUserFacingTypes() {
        XCTAssertEqual(BulletType.note.next, .task)
        XCTAssertEqual(BulletType.task.next, .question)
        XCTAssertEqual(BulletType.question.next, .idea)
        XCTAssertEqual(BulletType.idea.next, .note)
    }

    func testNextOnUnknownBouncesBackToNote() {
        // `.unknown` should never appear in the input-bar cycle, but
        // if it ever leaks in (e.g. state restoration bug), it should
        // rejoin the cycle at the sensible starting point.
        XCTAssertEqual(BulletType.unknown.next, .note)
    }

    func testParseBareToken() {
        XCTAssertEqual(BulletType.parse(token: "note"), .note)
        XCTAssertEqual(BulletType.parse(token: "task"), .task)
        XCTAssertEqual(BulletType.parse(token: "question"), .question)
        XCTAssertEqual(BulletType.parse(token: "idea"), .idea)
    }

    func testParseLegacyEventTokenMapsToQuestion() {
        // Streams written before the event→question rename must
        // continue to load. `[event]` is a legacy alias for `[question]`.
        XCTAssertEqual(BulletType.parse(token: "event"), .question)
    }

    func testParseTokenWithTaskStateSuffix() {
        // The parser must strip task-state suffixes from the bullet
        // type lookup; otherwise `task>done` would never match.
        XCTAssertEqual(BulletType.parse(token: "task>done"), .task)
        XCTAssertEqual(BulletType.parse(token: "task>migrated"), .task)
        XCTAssertEqual(BulletType.parse(token: "task>cancelled"), .task)
    }

    func testParseUnknownTokenReturnsNil() {
        // Nil (not `.unknown`) so the caller can decide whether to
        // fall back or drop.
        XCTAssertNil(BulletType.parse(token: "gibberish"))
        XCTAssertNil(BulletType.parse(token: ""))
        XCTAssertNil(BulletType.parse(token: "TASK"))  // case sensitive
    }

    func testGlyphIsStableAcrossCases() {
        // Snapshot test: if someone silently changes a glyph, the
        // stream.md format drifts and existing files look different.
        XCTAssertEqual(BulletType.note.glyph, "—")
        XCTAssertEqual(BulletType.task.glyph, "☐")
        XCTAssertEqual(BulletType.question.glyph, "?")
        XCTAssertEqual(BulletType.idea.glyph, "!")
        XCTAssertEqual(BulletType.unknown.glyph, "⋯")
    }
}
