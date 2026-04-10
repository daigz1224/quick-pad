import AppKit
import Foundation

/// Exports stream sections to a Markdown file via NSSavePanel.
enum StreamExporter {

    /// Build a Markdown string from the given sections (respects
    /// current filter/search state — caller passes the visible sections).
    static func markdown(from sections: [StreamSection]) -> String {
        var lines: [String] = []
        for (i, section) in sections.enumerated() {
            if let header = section.rawHeader {
                if i > 0 { lines.append("") }
                lines.append(header)
                lines.append("")
            }
            for entry in section.entries where !entry.isDeleted {
                lines.append(entry.rawLine)
            }
        }
        // Ensure trailing newline.
        if lines.last != "" { lines.append("") }
        return lines.joined(separator: "\n")
    }

    /// Show NSSavePanel and write the exported Markdown.
    /// Runs asynchronously on the main thread.
    @MainActor
    static func savePanel(sections: [StreamSection]) {
        let content = markdown(from: sections)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Stream"
        panel.nameFieldStringValue = "quickpad-export.md"
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
}
