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
    /// Already-deleted lines are returned unchanged.
    static func insertDeletedSuffix(_ rawLine: String) -> String {
        guard !rawLine.contains(">deleted]") else { return rawLine }
        guard let closeBracket = rawLine.firstIndex(of: "]") else {
            return rawLine
        }
        var result = rawLine
        result.insert(contentsOf: ">deleted", at: closeBracket)
        return result
    }

    /// `[note>deleted] foo` → `[note] foo`
    /// `[task>done>deleted] bar` → `[task>done] bar`
    /// Lines without `>deleted` are returned unchanged.
    static func removeDeletedSuffix(_ rawLine: String) -> String {
        rawLine.replacingOccurrences(of: ">deleted", with: "")
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

    // MARK: - Helpers

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
