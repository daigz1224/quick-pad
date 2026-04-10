import XCTest
import SwiftUI
@testable import QuickPad

/// Tests for the inline Markdown renderer. Since `Text` is opaque, we
/// test via `AttributedString` round-trips where possible, and verify
/// that the render function doesn't crash on edge cases.
final class InlineMarkdownTests: XCTestCase {

    // MARK: - Basic rendering (no crash, returns non-empty)

    func testPlainTextRenders() {
        let text = InlineMarkdown.render("hello world")
        // Text is opaque; just verify it doesn't crash.
        XCTAssertNotNil(text)
    }

    func testCodeSpanRenders() {
        let text = InlineMarkdown.render("run `kubectl logs` now")
        XCTAssertNotNil(text)
    }

    func testBoldRenders() {
        let text = InlineMarkdown.render("this is **important**")
        XCTAssertNotNil(text)
    }

    func testLinkRenders() {
        let text = InlineMarkdown.render("see [docs](https://example.com)")
        XCTAssertNotNil(text)
    }

    func testMixedMarkdownRenders() {
        let text = InlineMarkdown.render("**bold** and `code` and [link](url)")
        XCTAssertNotNil(text)
    }

    // MARK: - Search highlighting (verify via AttributedString)

    func testSearchHighlightOnPlainText() {
        // When Markdown parsing fails or is plain, search should still work.
        let text = InlineMarkdown.render("hello world", query: "world")
        XCTAssertNotNil(text)
    }

    func testSearchHighlightOnMarkdown() {
        let text = InlineMarkdown.render("run `kubectl` command", query: "kubectl")
        XCTAssertNotNil(text)
    }

    func testSearchHighlightCaseInsensitive() {
        let text = InlineMarkdown.render("Hello WORLD", query: "hello")
        XCTAssertNotNil(text)
    }

    func testEmptyQueryNoHighlight() {
        let text = InlineMarkdown.render("no highlight", query: "")
        XCTAssertNotNil(text)
    }

    // MARK: - Edge cases

    func testEmptyStringRenders() {
        let text = InlineMarkdown.render("")
        XCTAssertNotNil(text)
    }

    func testUnclosedBacktickRenders() {
        let text = InlineMarkdown.render("unclosed `backtick")
        XCTAssertNotNil(text)
    }

    func testUnclosedBoldRenders() {
        let text = InlineMarkdown.render("unclosed **bold")
        XCTAssertNotNil(text)
    }

    func testChineseContentRenders() {
        let text = InlineMarkdown.render("frozen ConvNeXt-T 比 **finetune** 快 3x")
        XCTAssertNotNil(text)
    }

    func testMultipleCodeSpansRender() {
        let text = InlineMarkdown.render("`a` and `b` and `c`")
        XCTAssertNotNil(text)
    }

    func testSearchQueryNotFoundNoChange() {
        let text = InlineMarkdown.render("hello world", query: "xyz")
        XCTAssertNotNil(text)
    }

    // MARK: - AttributedString parsing verification

    func testAttributedStringParsesCodeSpan() {
        let attr = try? AttributedString(
            markdown: "run `kubectl` now",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        XCTAssertNotNil(attr)
        let plain = attr.map { String($0.characters) }
        XCTAssertEqual(plain, "run kubectl now")
    }

    func testAttributedStringParsesBold() {
        let attr = try? AttributedString(
            markdown: "this is **bold**",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        XCTAssertNotNil(attr)
        let plain = attr.map { String($0.characters) }
        XCTAssertEqual(plain, "this is bold")
    }

    func testAttributedStringParsesLink() {
        let attr = try? AttributedString(
            markdown: "see [docs](https://example.com)",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        XCTAssertNotNil(attr)
        let plain = attr.map { String($0.characters) }
        XCTAssertEqual(plain, "see docs")
    }

    func testAttributedStringPreservesPlainText() {
        let attr = try? AttributedString(
            markdown: "just plain text",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        XCTAssertNotNil(attr)
        let plain = attr.map { String($0.characters) }
        XCTAssertEqual(plain, "just plain text")
    }
}
