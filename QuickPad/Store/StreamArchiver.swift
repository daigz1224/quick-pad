import Foundation

/// Moves completed / cancelled tasks (and stale soft-deleted entries)
/// out of `stream.md` into monthly archive files under
/// `~/.quickpad/archive/YYYY-MM.md`.
///
/// Design:
/// - Only entries older than `archiveAfterHours` (default 24h) are
///   eligible, so recent completions stay visible for review.
/// - Archive files mirror the stream format (day separators + entries)
///   so they're still readable in any text editor.
/// - Empty day separators left behind in stream.md are cleaned up.
/// - Runs on app launch and periodically via a timer.
struct StreamArchiver {

    /// Minimum age (in days) before a done/cancelled task is archived.
    let archiveAfterDays: Int

    /// Root directory for archive files.
    let archiveDirectory: URL

    /// The stream file to scan.
    let streamFileURL: URL

    init(
        archiveAfterDays: Int = 30,
        archiveDirectory: URL = MarkdownFileStore.streamFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("archive"),
        streamFileURL: URL = MarkdownFileStore.streamFileURL
    ) {
        self.archiveAfterDays = archiveAfterDays
        self.archiveDirectory = archiveDirectory
        self.streamFileURL = streamFileURL
    }

    /// Result of an archive run.
    struct ArchiveResult {
        let archivedCount: Int
        let cleanedDeletedCount: Int
    }

    // MARK: - Public

    /// Scan stream.md, move eligible entries to archive files, clean up
    /// soft-deleted entries, and remove empty separators.
    @discardableResult
    func run(now: Date = Date()) throws -> ArchiveResult {
        guard FileManager.default.fileExists(atPath: streamFileURL.path),
              let text = try? String(contentsOf: streamFileURL, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ArchiveResult(archivedCount: 0, cleanedDeletedCount: 0)
        }

        let lines = text.components(separatedBy: "\n")
        let cutoff = Calendar.current.date(byAdding: .day, value: -archiveAfterDays, to: now)!

        var linesToKeep: [String] = []
        // Entries grouped by archive month key (e.g. "2026-04").
        var archiveGroups: [String: [ArchiveEntry]] = [:]
        var currentSeparator: String? = nil
        var currentDate: Date? = nil
        var archivedCount = 0
        var cleanedDeletedCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Day separator — remember it, defer adding to linesToKeep.
            if let (date, _) = parseSeparator(trimmed) {
                currentSeparator = line
                currentDate = date
                continue
            }

            // Blank line — keep only if we have a pending separator.
            if trimmed.isEmpty {
                // Will be re-inserted as needed during cleanup.
                continue
            }

            // Parse entry to check archivability.
            let entry = StreamParser.parse("--- 2000-01-01 X ---\n\(line)")
                .first?.entries.first

            let shouldArchive: Bool
            let shouldClean: Bool

            if let entry = entry, let ts = entry.timestamp {
                let isOldEnough = ts < cutoff
                let isDoneOrCancelled = entry.bulletType == .task
                    && (entry.taskState == .done || entry.taskState == .cancelled)
                shouldArchive = isOldEnough && isDoneOrCancelled && !entry.isDeleted
                shouldClean = isOldEnough && entry.isDeleted
            } else {
                shouldArchive = false
                shouldClean = false
            }

            if shouldArchive {
                let monthKey = monthKey(for: entry!.timestamp!)
                archiveGroups[monthKey, default: []].append(
                    ArchiveEntry(line: line, date: currentDate, separator: currentSeparator)
                )
                archivedCount += 1
                // Don't add to linesToKeep.
            } else if shouldClean {
                cleanedDeletedCount += 1
                // Don't add to linesToKeep.
            } else {
                // Emit the separator if this is the first kept entry under it.
                if let sep = currentSeparator {
                    if !linesToKeep.isEmpty {
                        linesToKeep.append("")  // blank line before separator
                    }
                    linesToKeep.append(sep)
                    linesToKeep.append("")  // blank line after separator
                    currentSeparator = nil
                }
                linesToKeep.append(line)
            }
        }

        // Nothing to do.
        guard archivedCount > 0 || cleanedDeletedCount > 0 else {
            return ArchiveResult(archivedCount: 0, cleanedDeletedCount: 0)
        }

        // Write archive files.
        if !archiveGroups.isEmpty {
            try FileManager.default.createDirectory(
                at: archiveDirectory,
                withIntermediateDirectories: true
            )
            for (month, entries) in archiveGroups {
                try appendToArchive(month: month, entries: entries)
            }
        }

        // Write back cleaned stream.md.
        let cleaned = normalizeTrailingNewline(linesToKeep.joined(separator: "\n"))
        try atomicWrite(cleaned, to: streamFileURL)

        return ArchiveResult(
            archivedCount: archivedCount,
            cleanedDeletedCount: cleanedDeletedCount
        )
    }

    // MARK: - Archive file I/O

    /// Append entries to `~/.quickpad/archive/YYYY-MM.md`, grouping
    /// by day separator.
    private func appendToArchive(month: String, entries: [ArchiveEntry]) throws {
        let fileURL = archiveDirectory.appendingPathComponent("\(month).md")

        var existing = ""
        if FileManager.default.fileExists(atPath: fileURL.path) {
            existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }

        // Group entries by their day separator.
        var byDay: [(separator: String, lines: [String])] = []
        var currentSep: String? = nil
        var currentLines: [String] = []

        for entry in entries {
            let sep = entry.separator ?? "--- unknown ---"
            if sep != currentSep {
                if let cs = currentSep {
                    byDay.append((separator: cs, lines: currentLines))
                }
                currentSep = sep
                currentLines = [entry.line]
            } else {
                currentLines.append(entry.line)
            }
        }
        if let cs = currentSep {
            byDay.append((separator: cs, lines: currentLines))
        }

        // Build the text to append.
        var addition = ""
        for group in byDay {
            // Check if this separator already exists in the archive file.
            if existing.contains(group.separator) {
                // Append entries after the existing separator's entries.
                // Simple approach: just append at the end with the same separator.
                // This may create duplicate separators, but it's cosmetically
                // fine for an archive file.
            }
            if !existing.isEmpty || !addition.isEmpty {
                addition += "\n"
            }
            addition += group.separator + "\n\n"
            addition += group.lines.joined(separator: "\n") + "\n"
        }

        let final = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            + (existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n")
            + addition

        try atomicWrite(normalizeTrailingNewline(final), to: fileURL)
    }

    // MARK: - Helpers

    private struct ArchiveEntry {
        let line: String
        let date: Date?
        let separator: String?
    }

    private func monthKey(for date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    private func parseSeparator(_ line: String) -> (Date, String)? {
        guard line.hasPrefix("---"), line.hasSuffix("---") else { return nil }
        let stripped = line
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            .trimmingCharacters(in: .whitespaces)
        let parts = stripped.split(separator: " ", maxSplits: 1)
        guard let dateToken = parts.first else { return nil }
        guard let date = Self.dayFormatter.date(from: String(dateToken)) else {
            return nil
        }
        return (date, line)
    }

    private func normalizeTrailingNewline(_ text: String) -> String {
        var s = text
        while s.hasSuffix("\n") { s.removeLast() }
        return s + "\n"
    }

    private func atomicWrite(_ text: String, to fileURL: URL) throws {
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

    // MARK: - Formatters

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
