import Foundation

/// Targeted line-level mutations on `stream.md`. Unlike `StreamWriter`
/// (which is strictly append-only and never touches existing bytes),
/// `StreamMutator` deliberately modifies existing lines — it is the
/// opt-in escape hatch for typo corrections and soft-delete.
///
/// Every operation follows the same discipline:
/// 1. Read the current file from disk (not from memory).
/// 2. Locate the target line by exact `rawLine` match.
/// 3. Perform the substitution in memory.
/// 4. Atomic-write the result back (temp file + rename).
///
/// If the target line has been modified externally (e.g. by vim) between
/// the time the user saw it and the time they click Edit, the operation
/// fails with `.lineNotFound` rather than silently clobbering the wrong
/// line.
struct StreamMutator {

    enum MutationError: Error, LocalizedError {
        case lineNotFound
        case emptyContent
        case fileNotReadable

        var errorDescription: String? {
            switch self {
            case .lineNotFound: return "Entry was modified externally — please refresh and try again."
            case .emptyContent: return "Content cannot be empty."
            case .fileNotReadable: return "Could not read stream.md."
            }
        }
    }

    // MARK: - Edit

    /// Replace a single entry's content while preserving its timestamp,
    /// bullet type, and task state. Only the text after `[type] ` changes.
    ///
    /// - Parameters:
    ///   - oldRawLine: The entry's `rawLine` as captured by the parser.
    ///   - newContent: The replacement content (will be trimmed).
    ///   - fileURL: Defaults to the standard stream.md location.
    func editEntry(
        oldRawLine: String,
        newContent: String,
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MutationError.emptyContent }

        let newLine = Self.rebuildLine(oldRawLine: oldRawLine, newContent: trimmed)
        try replaceLine(oldLine: oldRawLine, newLine: newLine, in: fileURL)
    }

    // MARK: - Soft delete

    /// Mark an entry as deleted by inserting `>deleted` into its bracket
    /// token. `[note] foo` → `[note>deleted] foo`.
    func softDelete(
        rawLine: String,
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws {
        let newLine = Self.insertDeletedSuffix(rawLine)
        try replaceLine(oldLine: rawLine, newLine: newLine, in: fileURL)
    }

    /// Undo a soft-delete by removing the `>deleted` suffix from the
    /// bracket token. `[note>deleted] foo` → `[note] foo`.
    func undelete(
        rawLine: String,
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws {
        let newLine = Self.removeDeletedSuffix(rawLine)
        try replaceLine(oldLine: rawLine, newLine: newLine, in: fileURL)
    }

    // MARK: - Rescue (float to today)

    /// Move an entry to today's section: remove the old line, update its
    /// timestamp to `now`, and insert it right after today's separator
    /// (creating the separator if needed).
    func rescue(
        rawLine: String,
        at now: Date = Date(),
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw MutationError.fileNotReadable
        }

        var lines = text.components(separatedBy: "\n")

        // 1. Find and remove the old line.
        guard let removeIdx = lines.firstIndex(of: rawLine) else {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard let trimmedIdx = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == trimmed
            }) else {
                throw MutationError.lineNotFound
            }
            lines.remove(at: trimmedIdx)
            try insertRescuedLine(rawLine: rawLine, into: &lines, now: now, fileURL: fileURL)
            return
        }
        lines.remove(at: removeIdx)

        try insertRescuedLine(rawLine: rawLine, into: &lines, now: now, fileURL: fileURL)
    }

    private func insertRescuedLine(
        rawLine: String,
        into lines: inout [String],
        now: Date,
        fileURL: URL
    ) throws {
        // 2. Build the new line with updated timestamp + bumped @rN.
        //    Bumping happens BEFORE the timestamp swap so the bracket
        //    surgery operates on the original line (cheaper than
        //    re-parsing the rebuilt line, and the order doesn't matter
        //    semantically).
        let withBumpedCount = Self.bumpRescueCount(inRawLine: rawLine)
        let newLine = Self.rebuildLineWithTimestamp(oldRawLine: withBumpedCount, now: now)

        // 3. Find today's separator; create one if absent.
        let todaySep = Self.separatorLine(for: now)
        var insertIdx: Int

        if let sepIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == todaySep
        }) {
            // Insert after the separator (skip any blank lines right after it).
            insertIdx = sepIdx + 1
            while insertIdx < lines.count && lines[insertIdx].trimmingCharacters(in: .whitespaces).isEmpty {
                insertIdx += 1
            }
        } else {
            // No today separator yet — prepend at the top of the file.
            // Layout: separator, blank, entry, blank, ...old content...
            lines.insert("", at: 0)   // blank line between new entry and old content
            lines.insert("", at: 0)   // blank line after separator (entry goes here)
            lines.insert(todaySep, at: 0)
            insertIdx = 2             // right after separator + blank line
        }

        lines.insert(newLine, at: insertIdx)

        // 4. Write back.
        let result = lines.joined(separator: "\n")
        try Self.atomicWrite(result, to: fileURL)
    }

    // MARK: - Remove line (used by graduate)

    /// Delete a single line from `stream.md` outright (no soft-delete
    /// suffix, no history preserved). The caller is responsible for
    /// persisting the content elsewhere first — currently only
    /// `PinnedNoteStore.graduate` uses this, after having written the
    /// entry to `~/.quickpad/pinned/<slug>.md`.
    func removeLine(
        rawLine: String,
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw MutationError.fileNotReadable
        }

        var lines = text.components(separatedBy: "\n")
        let idx: Int
        if let i = lines.firstIndex(of: rawLine) {
            idx = i
        } else {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard let i = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == trimmed
            }) else {
                throw MutationError.lineNotFound
            }
            idx = i
        }
        lines.remove(at: idx)
        let result = lines.joined(separator: "\n")
        try Self.atomicWrite(result, to: fileURL)
    }

    // MARK: - Task state toggle

    /// Change a task entry's state. `[task] foo` → `[task>done] foo`.
    /// Non-task entries are ignored (no-op).
    func setTaskState(
        rawLine: String,
        newState: TaskState,
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws {
        let newLine = Self.replaceTaskState(rawLine: rawLine, newState: newState)
        guard newLine != rawLine else { return }
        try replaceLine(oldLine: rawLine, newLine: newLine, in: fileURL)
    }

    // MARK: - Change bullet type

    /// Change an entry's bullet type. `[note] foo` → `[task] foo`.
    /// Task-state suffixes are dropped when converting away from task,
    /// and added as `>pending` when converting to task.
    func changeBulletType(
        rawLine: String,
        newType: BulletType,
        fileURL: URL = MarkdownFileStore.streamFileURL
    ) throws {
        let newLine = Self.replaceBulletType(rawLine: rawLine, newType: newType)
        guard newLine != rawLine else { return }
        try replaceLine(oldLine: rawLine, newLine: newLine, in: fileURL)
    }

    /// Pure helper: replace the bracket token's bullet type.
    /// `[task>done] foo` → `[note] foo`  (strips task state)
    /// `[note] foo` → `[task] foo`       (no state suffix added for task)
    /// Preserves `@rN` rescue count.
    static func replaceBulletType(rawLine: String, newType: BulletType) -> String {
        mutatingBracketToken(in: rawLine) { cleaned, count in
            let isDeleted = cleaned.contains(">deleted")
            var newToken = newType.rawValue
            if isDeleted { newToken += ">deleted" }
            return (newToken, count)
        }
    }

    // MARK: - Line manipulation (pure, testable)

    /// Rebuild an entry line with new content, preserving the prefix
    /// (`- TIMESTAMP [type]`). If the line doesn't match the expected
    /// format, returns the old line unchanged (defensive — caller should
    /// have guarded with `lineNotFound` upstream).
    static func rebuildLine(oldRawLine: String, newContent: String) -> String {
        // Find the closing `]` of the bracket token. Everything up to
        // and including `] ` is the prefix we preserve.
        guard let closeBracket = oldRawLine.firstIndex(of: "]") else {
            return oldRawLine
        }
        let prefixEnd = oldRawLine.index(after: closeBracket)
        let prefix = String(oldRawLine[oldRawLine.startIndex..<prefixEnd])

        // Expand content shortcuts (same as StreamWriter).
        let body = expandShortcuts(newContent)
        return "\(prefix) \(body)"
    }

    /// `[note] foo` → `[note>deleted] foo`
    /// `[task>done] bar` → `[task>done>deleted] bar`
    /// `[task @r3] bar` → `[task>deleted @r3] bar` (`@rN` preserved)
    /// Already-deleted lines are returned unchanged.
    static func insertDeletedSuffix(_ rawLine: String) -> String {
        mutatingBracketToken(in: rawLine) { cleaned, count in
            if cleaned.contains(">deleted") {
                return (cleaned, count)
            }
            return (cleaned + ">deleted", count)
        }
    }

    /// `[note>deleted] foo` → `[note] foo`
    /// `[task>done>deleted] bar` → `[task>done] bar`
    /// Lines without `>deleted` are returned unchanged. `@rN` is preserved.
    static func removeDeletedSuffix(_ rawLine: String) -> String {
        mutatingBracketToken(in: rawLine) { cleaned, count in
            (cleaned.replacingOccurrences(of: ">deleted", with: ""), count)
        }
    }

    // MARK: - File I/O

    /// Find `oldLine` in the file, replace with `newLine`, and write back
    /// atomically. Matches on the first exact occurrence.
    private func replaceLine(
        oldLine: String,
        newLine: String,
        in fileURL: URL
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw MutationError.fileNotReadable
        }

        let lines = text.components(separatedBy: "\n")
        guard let index = lines.firstIndex(of: oldLine) else {
            // Also try trimmed match for resilience against trailing
            // whitespace differences.
            let trimmedOld = oldLine.trimmingCharacters(in: .whitespaces)
            guard let trimmedIndex = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == trimmedOld
            }) else {
                throw MutationError.lineNotFound
            }
            var mutable = lines
            mutable[trimmedIndex] = newLine
            let result = mutable.joined(separator: "\n")
            try Self.atomicWrite(result, to: fileURL)
            return
        }

        var mutable = lines
        mutable[index] = newLine
        let result = mutable.joined(separator: "\n")
        try Self.atomicWrite(result, to: fileURL)
    }

    /// Rebuild a line with a new timestamp, preserving content and bracket.
    /// `- OLD_TS [note] foo` → `- NEW_TS [note] foo`
    static func rebuildLineWithTimestamp(oldRawLine: String, now: Date) -> String {
        // Expected format: `- TIMESTAMP [type] content`
        // We replace everything up to the first `[` with the new timestamp.
        guard let bracketIdx = oldRawLine.firstIndex(of: "[") else {
            return oldRawLine
        }
        let rest = String(oldRawLine[bracketIdx...])
        let ts = isoTimestampFormatter.string(from: now)
        return "- \(ts) \(rest)"
    }

    /// Replace the task state suffix in a bracket token.
    /// `[task] foo` → `[task>done] foo`
    /// `[task>pending] foo` → `[task>done] foo`
    /// Non-task lines are returned unchanged. `@rN` is preserved.
    static func replaceTaskState(rawLine: String, newState: TaskState) -> String {
        mutatingBracketToken(in: rawLine) { cleaned, count in
            let isDeleted = cleaned.contains(">deleted")
            let withoutDel = cleaned.replacingOccurrences(of: ">deleted", with: "")
            let head = withoutDel.split(separator: ">", maxSplits: 1).first.map(String.init) ?? withoutDel
            guard head == "task" else { return (cleaned, count) }

            var newToken: String = (newState == .pending) ? "task" : "task>\(newState.rawValue)"
            if isDeleted { newToken += ">deleted" }
            return (newToken, count)
        }
    }

    // MARK: - Rescue count (`@rN` inside the bracket token)

    /// Extract the rescue count from a bracket token. Returns 0 + the
    /// original token if no `@rN` segment is present. Removes the
    /// `@rN` part (and any leading whitespace) from the cleaned token
    /// so downstream `>deleted` / task-state parsing isn't affected.
    static func extractRescueCount(fromToken token: String) -> (count: Int, cleaned: String) {
        guard let range = token.range(of: #"\s*@r(\d+)"#, options: .regularExpression) else {
            return (0, token)
        }
        let match = String(token[range])
        let digits = match.drop { !$0.isNumber }
        let count = Int(digits) ?? 0
        var cleaned = token
        cleaned.removeSubrange(range)
        return (count, cleaned.trimmingCharacters(in: .whitespaces))
    }

    /// Replace any existing `@rN` with one reflecting `count`. A count
    /// of 0 emits the bare token (no suffix), keeping never-rescued
    /// entries pristine.
    static func setRescueCount(inToken token: String, count: Int) -> String {
        let stripped = extractRescueCount(fromToken: token).cleaned
        return count == 0 ? stripped : "\(stripped) @r\(count)"
    }

    /// Increment the rescue count inside the bracket token of a raw
    /// stream line. Idempotent w.r.t. format: missing `@rN` is treated
    /// as 0 and becomes `@r1`.
    static func bumpRescueCount(inRawLine rawLine: String) -> String {
        mutatingBracketToken(in: rawLine) { cleaned, count in
            (cleaned, count + 1)
        }
    }

    /// Generic surgery on the bracket token of a raw stream line.
    /// Splits the token into `cleaned` (everything except `@rN`) and
    /// `count`, lets the caller transform either, and re-renders the
    /// line. All helpers that touch the bracket should go through this
    /// so `@rN` survives unrelated mutations.
    private static func mutatingBracketToken(
        in rawLine: String,
        transform: (_ cleaned: String, _ count: Int) -> (cleaned: String, count: Int)
    ) -> String {
        guard let openBracket = rawLine.firstIndex(of: "["),
              let closeBracket = rawLine.firstIndex(of: "]") else {
            return rawLine
        }
        let token = String(rawLine[rawLine.index(after: openBracket)..<closeBracket])
        let (count, cleaned) = extractRescueCount(fromToken: token)
        let (newCleaned, newCount) = transform(cleaned, count)
        let newToken = setRescueCount(inToken: newCleaned, count: newCount)

        let prefix = String(rawLine[rawLine.startIndex...openBracket])
        let suffix = String(rawLine[closeBracket...])
        return prefix + newToken + suffix
    }

    /// `--- 2026-04-09 Thursday ---`
    static func separatorLine(for date: Date) -> String {
        let day = isoDayFormatter.string(from: date)
        let weekday = weekdayFormatter.string(from: date)
        return "--- \(day) \(weekday) ---"
    }

    // MARK: - Helpers

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

    private static let isoTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()

    private static func expandShortcuts(_ content: String) -> String {
        if content.hasPrefix("* ") {
            return "*priority " + String(content.dropFirst(2))
        }
        return content
    }

    private static func atomicWrite(_ text: String, to fileURL: URL) throws {
        let data = Data(text.utf8)
        let tmpURL = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: [.atomic])

        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            _ = try fm.replaceItemAt(fileURL, withItemAt: tmpURL)
        } else {
            try fm.moveItem(at: tmpURL, to: fileURL)
        }
    }
}
