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

    /// Load every `archive/*.md` file and return the parsed entries
    /// flattened into a single section list. Used by ⌘F to extend
    /// search beyond the current stream so a "lost last year" idea
    /// remains findable.
    func loadArchives(directoryURL: URL = MarkdownFileStore.archiveDirectoryURL) -> [StreamSection] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path),
              let urls = try? fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        var sections: [StreamSection] = []
        for url in urls.filter({ $0.pathExtension.lowercased() == "md" }) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            sections.append(contentsOf: StreamParser.parse(text))
        }
        return sections
    }

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
