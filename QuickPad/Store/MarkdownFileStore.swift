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
