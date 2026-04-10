import SwiftUI

/// Renders inline Markdown (`` `code` ``, `**bold**`, `[link](url)`) as
/// styled SwiftUI `Text`. Uses `AttributedString(markdown:)` with
/// `.inlineOnlyPreservingWhitespace` so block-level elements (headers,
/// lists) are treated as plain text.
///
/// Search highlighting is applied on top of Markdown styling: matching
/// substrings get a yellow foreground + bold, preserving any underlying
/// code/link styling.
enum InlineMarkdown {

    /// Render `text` as inline Markdown, optionally highlighting
    /// `query` matches with yellow + bold.
    static func render(_ text: String, query: String = "") -> Text {
        // Try Markdown parsing; fall back to plain text on failure.
        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return highlightPlain(text, query: query)
        }

        // Apply search highlighting if active.
        if !query.isEmpty {
            applySearchHighlight(&attributed, query: query)
        }

        return Text(attributed)
    }

    // MARK: - Search highlighting on AttributedString

    /// Walk the attributed string's plain-text representation and mark
    /// every case-insensitive match of `query` with yellow + bold.
    private static func applySearchHighlight(
        _ attributed: inout AttributedString,
        query: String
    ) {
        let plain = String(attributed.characters)
        var searchStart = plain.startIndex
        while searchStart < plain.endIndex,
              let range = plain.range(
                of: query,
                options: .caseInsensitive,
                range: searchStart..<plain.endIndex
              ) {
            // Convert String.Index range to AttributedString.Index range.
            let offset = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let length = plain.distance(from: range.lowerBound, to: range.upperBound)
            let attrStart = attributed.index(
                attributed.startIndex,
                offsetByCharacters: offset
            )
            let attrEnd = attributed.index(
                attrStart,
                offsetByCharacters: length
            )
            let attrRange = attrStart..<attrEnd

            attributed[attrRange].foregroundColor = .yellow
            attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized

            searchStart = range.upperBound
        }
    }

    // MARK: - Fallback plain-text highlighting

    /// Used when Markdown parsing fails — mirrors the old `highlighted`
    /// method from `StreamEntryRow`.
    private static func highlightPlain(_ text: String, query: String) -> Text {
        guard !query.isEmpty else { return Text(text) }

        var result = Text("")
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let range = text.range(
                of: query,
                options: .caseInsensitive,
                range: cursor..<text.endIndex
              ) {
            if range.lowerBound > cursor {
                result = result + Text(String(text[cursor..<range.lowerBound]))
            }
            result = result + Text(String(text[range]))
                .foregroundStyle(Color.yellow)
                .bold()
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result = result + Text(String(text[cursor..<text.endIndex]))
        }
        return result
    }
}
