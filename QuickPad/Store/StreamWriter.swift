import Foundation

/// Append-only writer for `~/.quickpad/stream.md`. Kept deliberately
/// tiny: the only operation this milestone needs is "add one entry to
/// today's section". Everything is atomic (temp file + rename) so a
/// crash mid-write can never leave stream.md in a half-baked state.
///
/// The writer never touches lines it didn't add — the architecture doc
/// is explicit that vim edits and QuickPad edits must coexist, so we
/// preserve every existing byte and only append at the tail.
struct StreamWriter {

    enum WriteError: Error {
        case emptyContent
    }

    /// Append a new entry for `bulletType + content` to stream.md. If the
    /// file's last day separator isn't today's, a new separator is
    /// inserted first. Timestamp defaults to `Date()` but is injectable
    /// so tests / future features (e.g. backfill) can supply their own.
    @discardableResult
    func append(
        bulletType: BulletType,
        content: String,
        at now: Date = Date(),
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws -> URL {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WriteError.emptyContent }

        // Make sure ~/.quickpad exists before we try to write into it.
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Load current contents (empty string if the file doesn't exist
        // yet — first-run case).
        let existing: String
        if FileManager.default.fileExists(atPath: fileURL.path) {
            existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        } else {
            existing = ""
        }

        let rewritten = Self.buildAppended(
            existing: existing,
            bulletType: bulletType,
            content: trimmed,
            now: now
        )

        try Self.atomicWrite(rewritten, to: fileURL)
        return fileURL
    }

    // MARK: - Text assembly

    /// Pure function so it's trivially testable without touching the FS.
    ///
    /// Cosmetic contract:
    /// - Same-day entries are contiguous (single newline between them).
    /// - A blank line sits between the last entry of a day and the
    ///   next day's separator.
    /// - A blank line sits between a day separator and its first entry
    ///   (matches the shape of `sample-stream.md` and reads well in vim).
    /// - The file always ends with exactly one trailing newline; no
    ///   accumulation across repeated appends.
    static func buildAppended(
        existing: String,
        bulletType: BulletType,
        content: String,
        now: Date
    ) -> String {
        // Normalize: strip any existing trailing whitespace / newlines
        // so we control the file's tail shape ourselves.
        var base = existing
        while let last = base.last, last == "\n" || last == "\r" || last == " " || last == "\t" {
            base.removeLast()
        }

        let todayHeader = separatorLine(for: now)
        let needsSeparator = !hasSeparatorForToday(in: base, now: now)

        var out = base
        if needsSeparator {
            // Crossing a day boundary (or starting from an empty file).
            // A blank line separates yesterday's last entry from the
            // new day's header; a blank line after the header sets up
            // the day's first entry.
            if !out.isEmpty {
                out.append("\n\n")
            }
            out.append(todayHeader)
            out.append("\n\n")
        } else if !out.isEmpty {
            // Same-day append: entries are contiguous, single newline.
            out.append("\n")
        }
        out.append(entryLine(
            bulletType: bulletType,
            content: content,
            now: now
        ))
        out.append("\n")
        return out
    }

    /// Check whether the existing text already has a day separator for
    /// `now`'s calendar date. We only look at the *last* separator:
    /// QuickPad is append-only, so if the tail belongs to today we're
    /// fine; if it belongs to yesterday we need to insert a new one.
    private static func hasSeparatorForToday(in text: String, now: Date) -> Bool {
        let target = isoDayFormatter.string(from: now)
        // Scan lines from the bottom up looking for the most recent
        // separator. The parser's format is `--- YYYY-MM-DD Weekday ---`.
        let lines = text.components(separatedBy: "\n")
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("---"), trimmed.hasSuffix("---") else {
                continue
            }
            let stripped = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                .trimmingCharacters(in: .whitespaces)
            let token = stripped.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            return token == target
        }
        return false
    }

    /// `--- 2026-04-09 Thursday ---`
    private static func separatorLine(for date: Date) -> String {
        let day = isoDayFormatter.string(from: date)
        let weekday = weekdayFormatter.string(from: date)
        return "--- \(day) \(weekday) ---"
    }

    /// `- 2026-04-09T22:31:17+09:00 [task] fix the build`
    ///
    /// Task entries emit `[task]` (pending) — migrated/done/cancelled
    /// transitions happen in a later milestone and touch existing lines
    /// instead of creating new ones.
    ///
    /// Content shortcut: a leading `* ` expands to `*priority `, matching
    /// the architecture doc's priority marker. Anything else goes in
    /// verbatim so `read:`, `watch:`, `listen:`, `?` etc. round-trip
    /// unchanged.
    private static func entryLine(
        bulletType: BulletType,
        content: String,
        now: Date
    ) -> String {
        let timestamp = isoTimestampFormatter.string(from: now)
        let type: String = (bulletType == .unknown ? "note" : bulletType.rawValue)
        let body = expandShortcuts(content)
        return "- \(timestamp) [\(type)] \(body)"
    }

    private static func expandShortcuts(_ content: String) -> String {
        if content.hasPrefix("* ") {
            return "*priority " + String(content.dropFirst(2))
        }
        // Bare `*` alone isn't meaningful — treat as literal content.
        return content
    }

    // MARK: - Atomic write

    private static func atomicWrite(_ text: String, to fileURL: URL) throws {
        let data = Data(text.utf8)
        let tmpURL = fileURL.appendingPathExtension("tmp")

        // Write the temp file first. Using atomic:true here means the
        // temp file itself is written via a nested rename, so we get a
        // two-level guarantee: temp file is complete before we touch the
        // real path, and the final replace is also atomic.
        try data.write(to: tmpURL, options: [.atomic])

        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            _ = try fm.replaceItemAt(fileURL, withItemAt: tmpURL)
        } else {
            try fm.moveItem(at: tmpURL, to: fileURL)
        }
    }

    // MARK: - Formatters

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "EEEE"
        return f
    }()

    /// `yyyy-MM-dd'T'HH:mm:ssXXXXX` — matches the parser's primary
    /// (second-precision) shape so round-trips stay clean.
    private static let isoTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()
}
