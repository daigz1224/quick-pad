import XCTest
@testable import QuickPad

/// Covers `StreamViewModel.normalize` — the input-cleanup step at the
/// top of `append` and `editEntry` that prevents voice dictation or
/// pasted multi-line content from fragmenting into orphan stream-line
/// pseudo-entries.
final class NormalizeTests: XCTestCase {

    func testPlainContentPassesThrough() {
        XCTAssertEqual(
            StreamViewModel.normalize("hello world"),
            "hello world"
        )
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(
            StreamViewModel.normalize("   hello world   "),
            "hello world"
        )
    }

    func testCollapsesEmbeddedNewlinesToSingleSpace() {
        XCTAssertEqual(
            StreamViewModel.normalize("first line\nsecond line"),
            "first line second line"
        )
    }

    func testCollapsesRunsOfWhitespace() {
        XCTAssertEqual(
            StreamViewModel.normalize("a  \t  b   c"),
            "a b c"
        )
    }

    func testCollapsesCRLFAndOtherLineBreaks() {
        XCTAssertEqual(
            StreamViewModel.normalize("a\r\nb\rc\nd"),
            "a b c d"
        )
    }

    func testVoiceDictationWithNumberedListFlattens() {
        let voice = """
        在企业工作的时候，对于不同的需求要有自己的侧重：

        1. 如果价值很高，认真去做。
        2. 如果不是，靠轻维护的方式。
        """
        let expected = "在企业工作的时候，对于不同的需求要有自己的侧重： 1. 如果价值很高，认真去做。 2. 如果不是，靠轻维护的方式。"
        XCTAssertEqual(StreamViewModel.normalize(voice), expected)
    }

    func testEmptyInputBecomesEmpty() {
        XCTAssertEqual(StreamViewModel.normalize(""), "")
        XCTAssertEqual(StreamViewModel.normalize("   \n  \t  "), "")
    }
}
