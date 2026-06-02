import Foundation
import Observation
import SwiftUI
import WidgetKit

/// Owns the parsed stream and routes every mutation through
/// `StreamFileIO` so disk-bound writes don't stall the popover when
/// TimeMachine / Spotlight is busy. Initial `load()` stays synchronous —
/// it runs once before the UI exists.
@Observable
final class StreamViewModel {
    private(set) var sections: [StreamSection] = []
    private(set) var isShowingSample: Bool = false
    private(set) var lastWriteError: String?

    /// Bumped on every reload. Cache keys (visible-sections, heatmap)
    /// compare against this instead of hashing the whole array.
    private var sectionsVersion: Int = 0
    private var visibleCache = VisibleCache(version: -1, byFilter: [:])
    private var heatmapCache: HeatmapCacheBox?

    private struct VisibleCache {
        var version: Int
        var byFilter: [BulletType?: [StreamSection]]
    }

    private struct HeatmapCacheBox {
        let key: HeatmapCacheKey
        let aggregator: HeatmapAggregator
    }

    private struct HeatmapCacheKey: Equatable {
        let version: Int
        let weeksShown: Int
        let today: Date
    }

    var undoEntry: StreamEntry?
    var undoRescueSnapshot: String?
    var lastGraduatedNoteURL: URL?

    private let store = MarkdownFileStore()
    private let writer = StreamWriter()
    private let mutator = StreamMutator()
    private let pinnedStore = PinnedNoteStore()

    /// Set by AppDelegate after wiring. Used to suppress FSEvents
    /// self-triggered reloads during programmatic writes.
    var fileWatcher: StreamFileWatcher?

    func load() {
        let result = store.load()
        sections = result.sections
        isShowingSample = result.usedFallback
        sectionsVersion &+= 1
    }

    @MainActor
    private func reloadFromDiskAnimated() async {
        let store = self.store
        let result: (sections: [StreamSection], usedFallback: Bool)
        do {
            result = try await StreamFileIO.perform { store.load() }
        } catch {
            // store.load() doesn't throw; the catch satisfies the
            // generic `throws` of StreamFileIO.perform. Mutation already
            // succeeded, so swallow.
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            sections = result.sections
            isShowingSample = result.usedFallback
        }
        sectionsVersion &+= 1
        // Push the desktop widget to refresh — every successful mutation
        // is a content change worth reflecting. WidgetKit rate-limits
        // reloads internally, so spamming this is safe.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Visible sections (cached)

    /// Use from the popover when not searching. Search mode operates on
    /// an already-small filtered subset and should call
    /// `applyVisibilityFilter` directly.
    func visibleSections(typeFilter: BulletType? = nil) -> [StreamSection] {
        if visibleCache.version != sectionsVersion {
            visibleCache = VisibleCache(version: sectionsVersion, byFilter: [:])
        }
        if let cached = visibleCache.byFilter[typeFilter] {
            return cached
        }
        let result = Self.applyVisibilityFilter(sections, typeFilter: typeFilter)
        visibleCache.byFilter[typeFilter] = result
        return result
    }

    /// Returns the original section unchanged when nothing was filtered,
    /// so the no-deletes / no-filter case avoids extra allocations.
    static func applyVisibilityFilter(
        _ sections: [StreamSection],
        typeFilter: BulletType?
    ) -> [StreamSection] {
        sections.compactMap { section in
            let kept = section.entries.filter { entry in
                if entry.isDeleted { return false }
                if let filter = typeFilter, entry.bulletType != filter { return false }
                return true
            }
            if kept.isEmpty {
                if section.rawHeader != nil && section.entries.isEmpty {
                    return section
                }
                return nil
            }
            if kept.count == section.entries.count {
                return section
            }
            var copy = section
            copy.entries = kept
            return copy
        }
    }

    // MARK: - Heatmap (cached)

    /// Cache key includes `today` so the highlighted cell rolls over at
    /// midnight even when no mutation has happened.
    func cachedHeatmap(weeksShown: Int = 12, now: Date = Date()) -> HeatmapAggregator {
        let key = HeatmapCacheKey(
            version: sectionsVersion,
            weeksShown: weeksShown,
            today: Calendar.current.startOfDay(for: now)
        )
        if let cache = heatmapCache, cache.key == key {
            return cache.aggregator
        }
        let agg = HeatmapAggregator.build(sections: sections, weeksShown: weeksShown, now: now)
        heatmapCache = HeatmapCacheBox(key: key, aggregator: agg)
        return agg
    }

    // MARK: - Mutation pipeline

    /// Runs `work` on the file-IO queue, reloads on success, surfaces the
    /// error message on failure. `onSuccess` and `onFailure` run on the
    /// main thread with `self` already known to be alive.
    private func performMutation<T>(
        errorPrefix: String,
        onSuccess: ((StreamViewModel, T) -> Void)? = nil,
        onFailure: ((StreamViewModel) -> Void)? = nil,
        work: @escaping () throws -> T
    ) {
        let watcher = self.fileWatcher
        Task { @MainActor [weak self] in
            do {
                let result = try await StreamFileIO.perform {
                    // Set the suppress window from the IO queue, right
                    // before the write — scheduling-time suppression is
                    // racy when the queue is congested.
                    watcher?.suppressNextChange()
                    return try work()
                }
                guard let self else { return }
                onSuccess?(self, result)
                self.lastWriteError = nil
                await self.reloadFromDiskAnimated()
            } catch {
                guard let self else { return }
                onFailure?(self)
                self.lastWriteError = "\(errorPrefix): \(error.localizedDescription)"
            }
        }
    }

    /// Collapse every run of whitespace (spaces, tabs, embedded
    /// newlines) into a single space, and trim. Voice dictation and
    /// paste-from-clipboard often slip `\n` inside a single logical
    /// thought; without this, the embedded newlines would split it
    /// into multiple stream entries on disk and break the atomicity
    /// of delete / edit / rescue / graduate.
    static func normalize(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Fast path for clean single-line input (the common case): no
        // embedded line break, no internal whitespace run. Skips the
        // split/filter/join allocation entirely.
        if !trimmed.contains(where: { $0.isNewline })
            && !trimmed.contains("  ")
            && !trimmed.contains("\t")
        {
            return trimmed
        }
        return trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func append(bulletType: BulletType, content: String) {
        let trimmed = Self.normalize(content)
        guard !trimmed.isEmpty else { return }
        let writer = self.writer
        performMutation(errorPrefix: "failed to write stream.md") {
            try writer.append(bulletType: bulletType, content: trimmed)
        }
    }

    func editEntry(_ entry: StreamEntry, newContent: String) {
        let trimmed = Self.normalize(newContent)
        guard !trimmed.isEmpty else {
            lastWriteError = "Content cannot be empty."
            return
        }
        let mutator = self.mutator
        performMutation(errorPrefix: "edit failed") {
            try mutator.editEntry(oldRawLine: entry.rawLine, newContent: trimmed)
        }
    }

    func deleteEntry(_ entry: StreamEntry) {
        let mutator = self.mutator
        performMutation(
            errorPrefix: "delete failed",
            onSuccess: { vm, _ in
                // Store the new (post-soft-delete) rawLine so undo can
                // find the line as it now exists on disk.
                var deletedEntry = entry
                deletedEntry.rawLine = StreamMutator.insertDeletedSuffix(entry.rawLine)
                deletedEntry.isDeleted = true
                vm.undoEntry = deletedEntry
            }
        ) {
            try mutator.softDelete(rawLine: entry.rawLine)
        }
    }

    /// Snapshot read + rescue write share one queue submission so
    /// nothing else can write to stream.md between them.
    func rescueEntry(_ entry: StreamEntry) {
        let mutator = self.mutator
        performMutation(
            errorPrefix: "rescue failed",
            onSuccess: { vm, snapshot in vm.undoRescueSnapshot = snapshot },
            onFailure: { vm in vm.undoRescueSnapshot = nil }
        ) { () -> String? in
            let snap = try? String(contentsOf: MarkdownFileStore.streamFileURL, encoding: .utf8)
            try mutator.rescue(rawLine: entry.rawLine)
            return snap
        }
    }

    func undoRescue() {
        guard let snapshot = undoRescueSnapshot else { return }
        performMutation(
            errorPrefix: "undo rescue failed",
            onSuccess: { vm, _ in vm.undoRescueSnapshot = nil }
        ) {
            try snapshot.write(to: MarkdownFileStore.streamFileURL, atomically: true, encoding: .utf8)
        }
    }

    func changeBulletType(_ entry: StreamEntry, newType: BulletType) {
        guard newType != entry.bulletType else { return }
        let mutator = self.mutator
        performMutation(errorPrefix: "type change failed") {
            try mutator.changeBulletType(rawLine: entry.rawLine, newType: newType)
        }
    }

    func setTaskState(_ entry: StreamEntry, newState: TaskState) {
        let mutator = self.mutator
        performMutation(errorPrefix: "task state change failed") {
            try mutator.setTaskState(rawLine: entry.rawLine, newState: newState)
        }
    }

    /// Pinned write first, then remove from stream — if removal fails,
    /// roll back the pinned file so we don't orphan a note.
    func graduateEntry(_ entry: StreamEntry) {
        let mutator = self.mutator
        let pinnedStore = self.pinnedStore
        performMutation(
            errorPrefix: "graduate failed",
            onSuccess: { vm, url in vm.lastGraduatedNoteURL = url }
        ) { () -> URL in
            let url = try pinnedStore.graduate(entry: entry)
            do {
                try mutator.removeLine(rawLine: entry.rawLine)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
            return url
        }
    }

    func undoDelete() {
        guard let entry = undoEntry else { return }
        let mutator = self.mutator
        performMutation(
            errorPrefix: "undo failed",
            onSuccess: { vm, _ in vm.undoEntry = nil }
        ) {
            try mutator.undelete(rawLine: entry.rawLine)
        }
    }

    // MARK: - Phase 7: Review mode pool

    /// `daysAgo` asks "what did past-you think N days ago?";
    /// `staleTasks` asks "what's been pending too long?", catching
    /// long-stuck items that don't fall on a 7/30/90-day boundary.
    enum ReviewWindow: Hashable, Identifiable {
        case daysAgo(Int)
        case staleTasks

        static let allCases: [ReviewWindow] = [.daysAgo(7), .daysAgo(30), .daysAgo(90), .staleTasks]

        var id: Self { self }

        var label: String {
            switch self {
            case .daysAgo(let n): return "\(n) days ago"
            case .staleTasks:     return "stale tasks"
            }
        }

        var shortLabel: String {
            switch self {
            case .daysAgo(let n): return "\(n)d"
            case .staleTasks:     return "stale"
            }
        }
    }

    /// `daysAgo`: timestamp within ±1 day of (today − N), excluding
    /// soft-deleted entries and closed tasks (migrated tasks DO appear —
    /// "did this come back?" is the review question).
    /// `staleTasks`: every pending task ≥7 days old, oldest-first.
    func reviewPool(window: ReviewWindow, now: Date = Date()) -> [StreamEntry] {
        switch window {
        case .staleTasks:
            return stalePool()
        case .daysAgo(let days):
            let cal = Calendar.current
            let target = cal.startOfDay(for: cal.date(byAdding: .day, value: -days, to: now) ?? now)
            let lower = cal.date(byAdding: .day, value: -1, to: target) ?? target
            let upper = cal.date(byAdding: .day, value: 1, to: target) ?? target

            var pool: [StreamEntry] = []
            for section in sections {
                for entry in section.entries where !entry.isDeleted {
                    guard let ts = entry.timestamp else { continue }
                    let day = cal.startOfDay(for: ts)
                    guard day >= lower && day <= upper else { continue }
                    if entry.bulletType == .task,
                       let state = entry.taskState,
                       state == .done || state == .cancelled {
                        continue
                    }
                    pool.append(entry)
                }
            }
            return pool
        }
    }

    private func stalePool() -> [StreamEntry] {
        sections
            .flatMap(\.entries)
            .filter(\.isStaleTask)
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }
}
