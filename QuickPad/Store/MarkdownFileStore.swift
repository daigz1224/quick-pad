import Foundation

/// Reads `~/.quickpad/stream.md` from disk, falling back to the bundled
/// sample fixture so the popover is never empty on first launch.
/// Writing is intentionally absent for this milestone.
struct MarkdownFileStore {

    /// `~/.quickpad/stream.md`. Computed each call so a future test can
    /// override `FileManager.default.homeDirectoryForCurrentUser`.
    static var streamFileURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quickpad", isDirectory: true)
            .appendingPathComponent("stream.md", isDirectory: false)
    }

    /// `~/.quickpad/archive/` — monthly archive files written by
    /// `StreamArchiver` for done/cancelled tasks older than 30 days.
    static var archiveDirectoryURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quickpad", isDirectory: true)
            .appendingPathComponent("archive", isDirectory: true)
    }

    /// Used by ⌘F to extend search into archived months. Cached and
    /// invalidated when any archive file's mtime advances; archives
    /// grow monotonically via StreamArchiver so this stays correct in
    /// practice. Call `invalidateArchiveCache()` after a manual vim edit.
    func loadArchives(directoryURL: URL = MarkdownFileStore.archiveDirectoryURL) -> [StreamSection] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path),
              let urls = try? fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            // Directory missing: treat as empty and clear any stale cache.
            Self.cacheLock.lock()
            Self.archiveCache = nil
            Self.cacheLock.unlock()
            return []
        }
        let mdURLs = urls.filter { $0.pathExtension.lowercased() == "md" }

        // Cache key = (file count, max mtime). If neither changed since
        // the last call, the parsed result is still valid.
        let mtimes = mdURLs.compactMap {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
        let signature = ArchiveSignature(count: mdURLs.count, latestMtime: mtimes.max())

        Self.cacheLock.lock()
        if let cache = Self.archiveCache, cache.signature == signature {
            let cached = cache.sections
            Self.cacheLock.unlock()
            return cached
        }
        Self.cacheLock.unlock()

        var sections: [StreamSection] = []
        for url in mdURLs {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            sections.append(contentsOf: StreamParser.parse(text))
        }

        Self.cacheLock.lock()
        Self.archiveCache = (signature: signature, sections: sections)
        Self.cacheLock.unlock()
        return sections
    }

    /// Force the next `loadArchives` to re-parse from disk.
    static func invalidateArchiveCache() {
        cacheLock.lock()
        archiveCache = nil
        cacheLock.unlock()
    }

    private struct ArchiveSignature: Equatable {
        let count: Int
        let latestMtime: Date?
    }

    private static let cacheLock = NSLock()
    private static var archiveCache: (signature: ArchiveSignature, sections: [StreamSection])?

    /// Loads the stream. Returns the parsed sections plus a flag
    /// indicating whether the data came from disk or the bundled sample.
    func load() -> (sections: [StreamSection], usedFallback: Bool) {
        let url = Self.streamFileURL
        if FileManager.default.fileExists(atPath: url.path),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return (StreamParser.parse(text), false)
        }
        return (loadBundledSample(), true)
    }

    private func loadBundledSample() -> [StreamSection] {
        guard let url = Bundle.main.url(forResource: "sample-stream", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return StreamParser.parse(text)
    }
}
