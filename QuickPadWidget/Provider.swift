import Foundation
import WidgetKit

/// What the widget renders. A snapshot of today's most recent entries,
/// captured at `date`.
struct QuickPadEntry: TimelineEntry {
    let date: Date
    let entries: [StreamEntry]
    let totalToday: Int

    static let placeholder = QuickPadEntry(
        date: Date(),
        entries: [
            StreamEntry(timestamp: Date(), bulletType: .note,
                        content: "morning weight 73.4kg", rawLine: ""),
            StreamEntry(timestamp: Date(), bulletType: .task,
                        content: "ship widget MVP", rawLine: ""),
            StreamEntry(timestamp: Date(), bulletType: .idea,
                        content: "cinnabar accent on the icon → carry into the widget", rawLine: ""),
            StreamEntry(timestamp: Date(), bulletType: .question,
                        content: "why does FSEvents debounce feel slow at first launch?", rawLine: ""),
        ],
        totalToday: 4
    )
}

/// Reads `~/.quickpad/stream.md` directly (widget extension is un-
/// sandboxed, matching the main app's posture). Parses with the same
/// `StreamParser` the main app uses, then filters to today's entries.
///
/// Refreshes on a 15-minute timeline. For instant updates after an
/// in-app capture, the main app pushes `WidgetCenter.reloadAllTimelines()`
/// from its mutation pipeline.
struct QuickPadProvider: TimelineProvider {

    /// Mirrored stream URL — the main app writes a fresh copy of
    /// `~/.quickpad/stream.md` into this widget's own sandbox container
    /// on every change. We read from the container directly; no
    /// entitlement gymnastics required.
    private var streamURL: URL {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return docs.appendingPathComponent("stream.md", isDirectory: false)
    }

    func placeholder(in context: Context) -> QuickPadEntry {
        QuickPadEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickPadEntry) -> Void) {
        // For the gallery preview, use placeholder data so the widget
        // looks alive before it has any real content.
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickPadEntry>) -> Void) {
        let entry = currentEntry()
        // Next forced refresh in 15 minutes. The main app will also
        // push `reloadAllTimelines()` after every write, so most updates
        // arrive long before this fires — this is just the fallback for
        // when QuickPad isn't running.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> QuickPadEntry {
        guard let text = try? String(contentsOf: streamURL, encoding: .utf8) else {
            return QuickPadEntry(date: Date(), entries: [], totalToday: 0)
        }
        let todayEntries = StreamParser.parse(text).todayEntries()
        // Show the most recent 4 — fits cleanly in a medium widget.
        let visible = Array(todayEntries.prefix(4))
        return QuickPadEntry(date: Date(), entries: visible, totalToday: todayEntries.count)
    }
}
