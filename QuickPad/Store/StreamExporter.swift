import AppKit
import Foundation

/// Exports stream sections to a Markdown file via NSSavePanel.
enum StreamExporter {

    /// `dateInterval` is half-open `[start, end)`. Sections that end up
    /// with zero kept entries under the filter are skipped entirely so
    /// the export doesn't carry orphan day separators.
    static func markdown(
        from sections: [StreamSection],
        dateInterval: DateInterval? = nil
    ) -> String {
        var lines: [String] = []
        var hasEmittedSection = false
        for section in sections {
            let kept = section.entries.filter { entry in
                guard !entry.isDeleted else { return false }
                if let interval = dateInterval {
                    guard let ts = entry.timestamp else { return false }
                    return interval.contains(ts)
                }
                return true
            }
            if dateInterval != nil && kept.isEmpty { continue }

            if let header = section.rawHeader {
                if hasEmittedSection { lines.append("") }
                lines.append(header)
                lines.append("")
            }
            for entry in kept {
                lines.append(entry.rawLine)
            }
            hasEmittedSection = true
        }
        if lines.last != "" { lines.append("") }
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func savePanel(
        sections: [StreamSection],
        dateInterval: DateInterval? = nil
    ) {
        let content = markdown(from: sections, dateInterval: dateInterval)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Stream"
        panel.nameFieldStringValue = suggestedFilename(for: dateInterval)
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private static func suggestedFilename(for interval: DateInterval?) -> String {
        guard let interval else { return "quickpad-export.md" }
        // `end` is exclusive (next-day start). Subtract a second so the
        // filename reads as the last *included* day.
        let endShown = interval.end.addingTimeInterval(-1)
        return "quickpad-export-\(filenameDayFormatter.string(from: interval.start))_\(filenameDayFormatter.string(from: endShown)).md"
    }

    private static let filenameDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
