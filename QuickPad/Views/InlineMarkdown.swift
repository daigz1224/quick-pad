import SwiftUI

/// Renders inline Markdown as styled SwiftUI `Text`. Built on
/// `AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace`
/// so block-level elements (headers, lists) are treated as plain text.
///
/// Supported inline syntax:
///   - `` `code` `` — accent-tinted, monospaced, soft background
///   - `**bold**` — native AttributedString rendering
///   - `*italic*` — themed run + italic font + textSecondary tint
///   - `~~strikethrough~~` — manual post-pass (not standard CommonMark)
///   - `[link](url)` — accent + underline
///   - `#hashtag` — manual post-pass, accent foreground
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
        applyStrikethrough(&attributed, theme: theme, scheme: scheme)
        applyHashtags(&attributed, theme: theme, scheme: scheme)

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
        let italicFont = theme.contentFont(size: contentSize).italic()
        let italicFg = theme.textSecondary(for: scheme)

        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    attributed[run.range].foregroundColor = codeFg
                    attributed[run.range].backgroundColor = codeBg
                    attributed[run.range].font = codeFont
                } else if intent.contains(.emphasized) {
                    // *italic* — italicize and fade to secondary so it
                    // reads as an aside rather than another emphatic peak.
                    attributed[run.range].font = italicFont
                    attributed[run.range].foregroundColor = italicFg
                }
            }
            if run.link != nil {
                attributed[run.range].foregroundColor = theme.accent
                attributed[run.range].underlineStyle = .single
            }
        }
    }

    // MARK: - Strikethrough (manual; GFM extension, not in CommonMark)

    private static let strikethroughRegex = #/~~([^~]+)~~/#

    @MainActor
    private static func applyStrikethrough(
        _ attributed: inout AttributedString,
        theme: ThemeManager,
        scheme: ColorScheme
    ) {
        // Cheap O(N) prefilter — skip the materialization + regex pass
        // entirely for entries without any `~` (the common case).
        guard attributed.characters.contains("~") else { return }
        let plain = String(attributed.characters)
        let fade = theme.textTertiary(for: scheme)
        // Apply in reverse so earlier indices stay valid as we mutate.
        for match in plain.matches(of: Self.strikethroughRegex).reversed() {
            let attrRange = attributedRange(of: match.range, in: plain, within: attributed)
            var replacement = AttributedString(String(match.output.1))
            replacement.strikethroughStyle = Text.LineStyle.single
            replacement.foregroundColor = fade
            attributed.replaceSubrange(attrRange, with: replacement)
        }
    }

    // MARK: - Hashtags

    /// Matches `#tag` — alphanumerics + CJK ideograph block. Not
    /// preceded by a word char (so `foo#bar` isn't a hashtag) or by
    /// another `#` (so `##` doesn't double-count). Compiled once.
    private static let hashtagRegex: Regex<Substring> = {
        // Pattern is compile-time constant; force-try is safe.
        try! Regex(#"(?<![\w#])#[\w\u{4E00}-\u{9FFF}]+"#)
    }()

    @MainActor
    private static func applyHashtags(
        _ attributed: inout AttributedString,
        theme: ThemeManager,
        scheme: ColorScheme
    ) {
        guard attributed.characters.contains("#") else { return }
        let plain = String(attributed.characters)
        let tagColor = theme.accent.opacity(0.85)
        for match in plain.matches(of: Self.hashtagRegex) {
            let attrRange = attributedRange(of: match.range, in: plain, within: attributed)
            attributed[attrRange].foregroundColor = tagColor
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
            let attrRange = attributedRange(of: range, in: plain, within: attributed)

            // Themed mode (color != .yellow) uses a soft background
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

    // MARK: - Helpers

    /// Translate a plain-string range to the matching range inside the
    /// attributed string. Assumes equal character counts up to the
    /// translated position — true after the markdown parser has
    /// stripped delimiters and true for every post-pass in this file.
    private static func attributedRange(
        of plainRange: Range<String.Index>,
        in plain: String,
        within attributed: AttributedString
    ) -> Range<AttributedString.Index> {
        let lowerOffset = plain.distance(from: plain.startIndex, to: plainRange.lowerBound)
        let upperOffset = plain.distance(from: plain.startIndex, to: plainRange.upperBound)
        let lower = attributed.index(attributed.startIndex, offsetByCharacters: lowerOffset)
        let upper = attributed.index(attributed.startIndex, offsetByCharacters: upperOffset)
        return lower..<upper
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
