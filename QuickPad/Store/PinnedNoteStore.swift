import Foundation

/// Graduation: promote a Stream entry into a standalone Markdown file
/// under `~/.quickpad/pinned/`. This is the "graduate from the stream"
/// step from ARCHITECTURE.md — a repeatedly-rescued entry that's
/// matured into something worth keeping separately.
///
/// The file on disk is plain Markdown with a YAML-style header. We
/// keep it readable/editable by vim and searchable by grep, matching
/// the rest of QuickPad's KISS storage philosophy.
struct PinnedNoteStore {

    enum PinnedError: Error, LocalizedError {
        case directoryCreationFailed
        case writeFailed
        case fileExists

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed: return "Could not create ~/.quickpad/pinned/"
            case .writeFailed: return "Could not write pinned note."
            case .fileExists: return "A pinned note with that slug already exists."
            }
        }
    }

    /// `~/.quickpad/pinned/`
    static var pinnedDirectoryURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quickpad", isDirectory: true)
            .appendingPathComponent("pinned", isDirectory: true)
    }

    // MARK: - Listing

    /// Returns `*.md` files in `~/.quickpad/pinned/`, sorted by
    /// modification time (most recently touched first).
    func list(directoryURL: URL = PinnedNoteStore.pinnedDirectoryURL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return da > db
            }
    }

    // MARK: - Graduate

    /// Write a pinned note file for `entry`. Returns the URL of the
    /// created file. Does NOT touch `stream.md` — the caller is
    /// responsible for removing the entry from the stream (typically
    /// via `StreamMutator.removeLine`).
    ///
    /// If a file with the derived slug already exists, appends `-2`,
    /// `-3`, ... so we never silently overwrite prior graduations.
    @discardableResult
    func graduate(
        entry: StreamEntry,
        directoryURL: URL = PinnedNoteStore.pinnedDirectoryURL
    ) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            do {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                throw PinnedError.directoryCreationFailed
            }
        }

        let slug = Self.slug(for: entry.content)
        let finalURL = Self.uniqueURL(for: slug, in: directoryURL)
        let body = Self.renderMarkdown(entry: entry)

        do {
            try body.write(to: finalURL, atomically: true, encoding: .utf8)
        } catch {
            throw PinnedError.writeFailed
        }
        return finalURL
    }

    // MARK: - Slug generation

    /// Produce a URL-safe, filesystem-friendly slug from entry content.
    /// Rules:
    /// - Lowercase
    /// - Drop BuJo prefix markers we render but don't want in filenames
    ///   (`*priority ` / `read: ` etc. get stripped)
    /// - Replace whitespace with `-`
    /// - Drop characters outside `[a-z0-9\-_\.]` — including CJK. If
    ///   the result is empty after filtering (pure-CJK content), fall
    ///   back to `note-YYYYMMDD`.
    /// - Truncate to 48 chars at a word boundary when possible.
    static func slug(for content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip known content prefixes so the slug focuses on meaning.
        for prefix in ["*priority ", "read:", "watch:", "listen:"] {
            if text.lowercased().hasPrefix(prefix) {
                text.removeFirst(prefix.count)
                text = text.trimmingCharacters(in: .whitespaces)
                break
            }
        }

        text = text.lowercased()
        text = text.replacingOccurrences(of: " ", with: "-")
        text = text.replacingOccurrences(of: "\t", with: "-")

        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_.")
        text = String(text.filter { allowed.contains($0) })

        // Collapse runs of dashes.
        while text.contains("--") {
            text = text.replacingOccurrences(of: "--", with: "-")
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))

        if text.isEmpty {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyyMMdd"
            return "note-\(df.string(from: Date()))"
        }

        // Truncate, preferring a dash boundary near the end.
        let maxLen = 48
        if text.count > maxLen {
            let cutoff = text.index(text.startIndex, offsetBy: maxLen)
            var truncated = String(text[..<cutoff])
            if let lastDash = truncated.lastIndex(of: "-"),
               truncated.distance(from: truncated.startIndex, to: lastDash) > 20 {
                truncated = String(truncated[..<lastDash])
            }
            text = truncated
        }
        return text
    }

    /// Resolves `<slug>.md`, then `<slug>-2.md`, `<slug>-3.md`, ... until
    /// a name that doesn't exist on disk is found.
    static func uniqueURL(for slug: String, in directoryURL: URL) -> URL {
        let fm = FileManager.default
        let base = directoryURL.appendingPathComponent("\(slug).md")
        if !fm.fileExists(atPath: base.path) { return base }
        var n = 2
        while true {
            let candidate = directoryURL.appendingPathComponent("\(slug)-\(n).md")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    // MARK: - Markdown rendering

    /// Render a pinned note file. Preserves the original entry's
    /// timestamp + bullet type in a lightweight header so the "where
    /// did this come from" history isn't lost.
    static func renderMarkdown(entry: StreamEntry, now: Date = Date()) -> String {
        let title = entry.content.isEmpty ? "Untitled" : entry.content
        let ts = entry.timestamp.map { Self.iso.string(from: $0) } ?? "-"
        let graduated = Self.iso.string(from: now)
        let type = entry.bulletType.rawValue

        var out = ""
        out += "# \(title)\n"
        out += "\n"
        out += "> graduated from stream on \(graduated)\n"
        out += "> origin: `[\(type)]` · \(ts)\n"
        out += "\n"
        out += "---\n"
        out += "\n"
        out += "\(entry.content)\n"
        return out
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return f
    }()
}
