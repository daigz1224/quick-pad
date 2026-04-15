import Foundation
import Observation
import SwiftUI

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

    /// Non-nil while an undo is available (soft-delete). Cleared after
    /// the toast timeout or after the undo is consumed.
    var undoEntry: StreamEntry?

    /// Snapshot of stream.md before the last rescue, for undo.
    var undoRescueSnapshot: String?

    private let store = MarkdownFileStore()
    private let writer = StreamWriter()
    private let mutator = StreamMutator()

    /// Set by AppDelegate after wiring. Used to suppress FSEvents
    /// self-triggered reloads during programmatic writes.
    var fileWatcher: StreamFileWatcher?

    func load() {
        let result = store.load()
        sections = result.sections
        isShowingSample = result.usedFallback
    }

    /// Reload with animation so entry additions/removals transition smoothly.
    private func animatedLoad() {
        let result = store.load()
        withAnimation(.easeOut(duration: 0.2)) {
            sections = result.sections
            isShowingSample = result.usedFallback
        }
    }

    /// Append a new entry to stream.md and reload so the UI reflects
    /// the change. Empty/whitespace content is a no-op — the input bar
    /// should also guard against this so this is just belt-and-suspenders.
    func append(bulletType: BulletType, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            fileWatcher?.suppressNextChange()
            try writer.append(bulletType: bulletType, content: trimmed)
            lastWriteError = nil
            animatedLoad()
        } catch {
            lastWriteError = "failed to write stream.md: \(error)"
        }
    }

    // MARK: - Mutation (Phase 1.5)

    /// Edit an existing entry's content in-place. Preserves timestamp,
    /// bullet type, and task state — only the text changes.
    func editEntry(_ entry: StreamEntry, newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastWriteError = "Content cannot be empty."
            return
        }

        do {
            fileWatcher?.suppressNextChange()
            try mutator.editEntry(oldRawLine: entry.rawLine, newContent: trimmed)
            lastWriteError = nil
            animatedLoad()
        } catch {
            lastWriteError = "edit failed: \(error.localizedDescription)"
        }
    }

    /// Soft-delete an entry: marks it as `[type>deleted]` in stream.md.
    /// Stores the entry for undo.
    func deleteEntry(_ entry: StreamEntry) {
        do {
            fileWatcher?.suppressNextChange()
            try mutator.softDelete(rawLine: entry.rawLine)
            lastWriteError = nil
            // Store the *new* rawLine (with >deleted suffix) so undo can
            // find the line as it now exists on disk.
            var deletedEntry = entry
            deletedEntry.rawLine = StreamMutator.insertDeletedSuffix(entry.rawLine)
            deletedEntry.isDeleted = true
            undoEntry = deletedEntry
            animatedLoad()
        } catch {
            lastWriteError = "delete failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Phase 2: Rescue + Task state

    /// Rescue an entry: remove from its current position, update timestamp
    /// to now, and insert at the top of today's section.
    /// Saves a file snapshot for undo.
    func rescueEntry(_ entry: StreamEntry) {
        do {
            // Snapshot for undo.
            let fileURL = MarkdownFileStore.streamFileURL
            undoRescueSnapshot = try? String(contentsOf: fileURL, encoding: .utf8)

            fileWatcher?.suppressNextChange()
            try mutator.rescue(rawLine: entry.rawLine)
            lastWriteError = nil
            animatedLoad()
        } catch {
            undoRescueSnapshot = nil
            lastWriteError = "rescue failed: \(error.localizedDescription)"
        }
    }

    /// Undo the most recent rescue by restoring the file snapshot.
    func undoRescue() {
        guard let snapshot = undoRescueSnapshot else { return }
        do {
            fileWatcher?.suppressNextChange()
            let fileURL = MarkdownFileStore.streamFileURL
            try snapshot.write(to: fileURL, atomically: true, encoding: .utf8)
            undoRescueSnapshot = nil
            lastWriteError = nil
            animatedLoad()
        } catch {
            lastWriteError = "undo rescue failed: \(error.localizedDescription)"
        }
    }

    /// Change an entry's bullet type (note/task/question/idea).
    func changeBulletType(_ entry: StreamEntry, newType: BulletType) {
        guard newType != entry.bulletType else { return }
        do {
            fileWatcher?.suppressNextChange()
            try mutator.changeBulletType(rawLine: entry.rawLine, newType: newType)
            lastWriteError = nil
            animatedLoad()
        } catch {
            lastWriteError = "type change failed: \(error.localizedDescription)"
        }
    }

    /// Toggle a task entry's state. Non-task entries are ignored.
    func setTaskState(_ entry: StreamEntry, newState: TaskState) {
        do {
            fileWatcher?.suppressNextChange()
            try mutator.setTaskState(rawLine: entry.rawLine, newState: newState)
            lastWriteError = nil
            animatedLoad()
        } catch {
            lastWriteError = "task state change failed: \(error.localizedDescription)"
        }
    }

    /// Undo the most recent soft-delete.
    func undoDelete() {
        guard let entry = undoEntry else { return }
        do {
            fileWatcher?.suppressNextChange()
            try mutator.undelete(rawLine: entry.rawLine)
            lastWriteError = nil
            undoEntry = nil
            animatedLoad()
        } catch {
            lastWriteError = "undo failed: \(error.localizedDescription)"
        }
    }
}
