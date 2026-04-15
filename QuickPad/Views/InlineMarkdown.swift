import SwiftUI

/// Renders inline Markdown (`` `code` ``, `**bold**`, `[link](url)`) as
/// styled SwiftUI `Text`. Uses `AttributedString(markdown:)` with
/// `.inlineOnlyPreservingWhitespace` so block-level elements (headers,
/// lists) are treated as plain text.
///
/// Two overloads:
/// - `render(_:query:)` — plain rendering, search highlight uses yellow.
///   Kept for tests and any caller without theme access.
/// - `render(_:theme:scheme:query:)` — theme-aware rendering: code spans
///   take the theme accent + tinted surface, links take the theme accent
///   with underline, search highlight tints with theme accent.
enum InlineMarkdown {

    // MARK: - Plain (no theme)

    static func render(_ text: String, query: String = "") -> Text {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return highlightPlain(text, query: query, accent: .yellow)
        }
        if !query.isEmpty {
            applySearchHighlight(&attributed, query: query, color: .yellow)
        }
        return Text(attributed)
    }

    // MARK: - Themed

    @MainActor
    static func render(
        _ text: String,
        theme: ThemeManager,
        scheme: ColorScheme,
        contentSize: CGFloat = 11,
        query: String = ""
    ) -> Text {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return highlightPlain(text, query: query, accent: theme.accent)
        }

        applyThemeStyling(&attributed, theme: theme, scheme: scheme, contentSize: contentSize)

        if !query.isEmpty {
            applySearchHighlight(&attributed, query: query, color: theme.accent)
        }
        return Text(attributed)
    }

    // MARK: - Run styling

    @MainActor
    private static func applyThemeStyling(
        _ attributed: inout AttributedString,
        theme: ThemeManager,
        scheme: ColorScheme,
        contentSize: CGFloat
    ) {
        let codeFont = theme.monoFont(size: contentSize)
        let codeBg = theme.accent.opacity(scheme == .dark ? 0.18 : 0.12)
        let codeFg = theme.accent

        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                attributed[run.range].foregroundColor = codeFg
                attributed[run.range].backgroundColor = codeBg
                attributed[run.range].font = codeFont
            }
            if run.link != nil {
                attributed[run.range].foregroundColor = theme.accent
                attributed[run.range].underlineStyle = .single
            }
        }
    }

    // MARK: - Search highlighting

    private static func applySearchHighlight(
        _ attributed: inout AttributedString,
        query: String,
        color: Color
    ) {
        let plain = String(attributed.characters)
        var searchStart = plain.startIndex
        while searchStart < plain.endIndex,
              let range = plain.range(
                of: query,
                options: .caseInsensitive,
                range: searchStart..<plain.endIndex
              ) {
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

            // For themed mode (color != .yellow) use a soft background
            // tint so we don't fight code-span foreground colors.
            if color == .yellow {
                attributed[attrRange].foregroundColor = .yellow
                attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized
            } else {
                attributed[attrRange].backgroundColor = color.opacity(0.30)
                attributed[attrRange].inlinePresentationIntent = .stronglyEmphasized
            }

            searchStart = range.upperBound
        }
    }

    // MARK: - Plain-text fallback

    private static func highlightPlain(_ text: String, query: String, accent: Color) -> Text {
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
                .foregroundStyle(accent)
                .bold()
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result = result + Text(String(text[cursor..<text.endIndex]))
        }
        return result
    }
}
