import Foundation

/// Pure parser: text in, structured `[StreamSection]` out. No I/O, no
/// side effects, safe to call from anywhere. Format spec lives in
/// `docs/ARCHITECTURE.md` under "stream.md format".
enum StreamParser {

    static func parse(_ text: String) -> [StreamSection] {
        var sections: [StreamSection] = []
        // Implicit bucket for any entries that show up before the first
        // day separator. Kept so we never silently drop content.
        var current = StreamSection(date: nil, rawHeader: nil)

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                continue
            }

            if let (date, header) = parseSeparator(line) {
                if !current.entries.isEmpty || current.rawHeader != nil {
                    sections.append(current)
                }
                current = StreamSection(date: date, rawHeader: header)
                continue
            }

            let entry = parseEntry(rawLine)
            current.entries.append(entry)
        }

        if !current.entries.isEmpty || current.rawHeader != nil {
            sections.append(current)
        }

        return sections
    }

    // MARK: - Separators

    /// Matches `--- YYYY-MM-DD Weekday ---`. Returns the parsed date
    /// (calendar day, no time) and the raw header verbatim.
    private static func parseSeparator(_ line: String) -> (Date, String)? {
        guard line.hasPrefix("---"), line.hasSuffix("---") else { return nil }

        let stripped = line
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            .trimmingCharacters(in: .whitespaces)

        // Take the first whitespace-separated token, expect YYYY-MM-DD.
        let parts = stripped.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let dateToken = parts.first else { return nil }

        guard let date = separatorDateFormatter.date(from: String(dateToken)) else {
            return nil
        }
        return (date, line)
    }

    private static let separatorDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Entries

    /// Parses `- ISO-TIMESTAMP [bullet-type] content`. Anything that
    /// doesn't match becomes an `.unknown` entry holding the raw line so
    /// nothing is lost on a future round-trip.
    private static func parseEntry(_ rawLine: String) -> StreamEntry {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        // Strip the leading "- " if present.
        var body = line
        if body.hasPrefix("- ") {
            body = String(body.dropFirst(2))
        } else if body.hasPrefix("-") {
            body = String(body.dropFirst(1))
            if body.first == " " { body = String(body.dropFirst()) }
        }

        // Split off the timestamp at the first whitespace.
        let firstSplit = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard firstSplit.count == 2 else {
            return unknown(rawLine: rawLine)
        }
        let tsToken = String(firstSplit[0])
        let rest = String(firstSplit[1])

        let timestamp = parseTimestamp(tsToken)

        // Expect a `[bullet-type]` token next.
        guard rest.hasPrefix("["), let closeIdx = rest.firstIndex(of: "]") else {
            return unknown(rawLine: rawLine)
        }
        let typeToken = String(rest[rest.index(after: rest.startIndex)..<closeIdx])
        guard let bulletType = BulletType.parse(token: typeToken) else {
            return unknown(rawLine: rawLine)
        }
        let taskState: TaskState? = (bulletType == .task) ? TaskState.parse(token: typeToken) : nil

        var content = String(rest[rest.index(after: closeIdx)...])
            .trimmingCharacters(in: .whitespaces)

        // Inline content markers — detect, strip, but keep the rest of
        // the content readable.
        var isPriority = false
        if content.hasPrefix("*priority") {
            isPriority = true
            content = String(content.dropFirst("*priority".count))
                .trimmingCharacters(in: .whitespaces)
        }

        var prefixTag: String? = nil
        for (prefix, tag) in Self.prefixTags {
            if content.hasPrefix(prefix) {
                prefixTag = tag
                break
            }
        }
        if content.hasPrefix("?") {
            prefixTag = "explore"
        }

        return StreamEntry(
            timestamp: timestamp,
            bulletType: bulletType,
            taskState: taskState,
            content: content,
            isPriority: isPriority,
            prefixTag: prefixTag,
            rawLine: rawLine
        )
    }

    private static func unknown(rawLine: String) -> StreamEntry {
        StreamEntry(
            timestamp: nil,
            bulletType: .unknown,
            content: rawLine.trimmingCharacters(in: .whitespaces),
            rawLine: rawLine
        )
    }

    /// Karpathy-style content prefixes that get hoisted into a tag.
    /// Order matters only if any prefix becomes a substring of another.
    private static let prefixTags: [(String, String)] = [
        ("read:", "read"),
        ("watch:", "watch"),
        ("listen:", "listen"),
    ]

    /// Lenient timestamp parser. The architecture doc shows entries
    /// using both `HH:mm` and `HH:mm:ss` (e.g. `2025-04-09T22:31+09:00`),
    /// neither of which the strict `ISO8601DateFormatter` accepts on its
    /// own. Try a chain of plausible shapes.
    private static func parseTimestamp(_ token: String) -> Date? {
        if let date = isoSecondsFormatter.date(from: token) { return date }
        if let date = isoMinutesFormatter.date(from: token) { return date }
        if let date = strictISOFormatter.date(from: token) { return date }
        return nil
    }

    private static let isoSecondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    private static let isoMinutesFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return f
    }()

    private static let strictISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
