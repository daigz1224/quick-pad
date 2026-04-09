import Foundation
import Observation

/// Holds the parsed stream and exposes a `load()` entry point. Uses the
/// macOS 14 Observation framework so SwiftUI views update automatically
/// without `@Published`.
@Observable
final class StreamViewModel {
    private(set) var sections: [StreamSection] = []
    /// True when the most recent load fell back to the bundled sample
    /// fixture (no `~/.quickpad/stream.md` on disk).
    private(set) var isShowingSample: Bool = false
    /// Last write error, surfaced to the UI so we can show a subtle
    /// warning instead of silently dropping user input.
    private(set) var lastWriteError: String?

    private let store = MarkdownFileStore()
    private let writer = StreamWriter()

    func load() {
        let result = store.load()
        sections = result.sections
        isShowingSample = result.usedFallback
    }

    /// Append a new entry to stream.md and reload so the UI reflects
    /// the change. Empty/whitespace content is a no-op — the input bar
    /// should also guard against this so this is just belt-and-suspenders.
    func append(bulletType: BulletType, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try writer.append(bulletType: bulletType, content: trimmed)
            lastWriteError = nil
            // Reload from disk so we see exactly what ended up on disk
            // (including any vim edits that raced us) rather than an
            // optimistic in-memory version.
            load()
        } catch {
            lastWriteError = "failed to write stream.md: \(error)"
        }
    }
}
