import SwiftUI

/// Renders a `StreamViewModel`'s sections as a scrollable day-grouped
/// stream. Deliberately avoids SwiftUI `List`:
///
///   1. `List` in macOS auto-selects the first focusable row when the
///      popover opens, which flashes an unwanted highlight.
///   2. `List` section headers pick up a subtle fill that makes the
///      first "TODAY" header visibly darker than the rest in dark mode.
///   3. Phase 2 will add click-to-rescue animations on rows — raw
///      `LazyVStack` keeps full control of hit-testing and transitions.
struct StreamListView: View {
    let sections: [StreamSection]
    /// Forwarded to every `StreamEntryRow` so matches get highlighted
    /// inline. Empty string = no highlighting (normal render).
    var highlightQuery: String = ""
    /// Overridable empty-state body. The default shows the first-run
    /// "stream.md is empty" hint; `PopoverRootView` swaps in a
    /// search-specific message when a query returns no matches.
    var emptyStateOverride: AnyView? = nil
    /// Callbacks for mutation (edit / delete / rescue / task state).
    var onEdit: ((StreamEntry, String) -> Void)?
    var onDelete: ((StreamEntry) -> Void)?
    var onRescue: ((StreamEntry) -> Void)?
    var onTaskStateChange: ((StreamEntry, TaskState) -> Void)?

    /// Active type filter. Nil = show all.
    var typeFilter: BulletType? = nil

    /// Sections with soft-deleted entries filtered out, plus optional
    /// type filter applied.
    private var visibleSections: [StreamSection] {
        sections.compactMap { section in
            var visible = section.entries.filter { !$0.isDeleted }
            if let filter = typeFilter {
                visible = visible.filter { $0.bulletType == filter }
            }
            guard !visible.isEmpty else {
                if section.rawHeader != nil && section.entries.isEmpty {
                    return section
                }
                return nil
            }
            var copy = section
            copy.entries = visible
            return copy
        }
    }

    var body: some View {
        if visibleSections.isEmpty {
            emptyStateOverride ?? AnyView(defaultEmptyState)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                        DaySeparatorView(
                            date: section.date,
                            rawHeader: section.rawHeader
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, index == 0 ? 6 : 10)
                        .padding(.bottom, 4)

                        ForEach(section.entries) { entry in
                            StreamEntryRow(
                                entry: entry,
                                highlightQuery: highlightQuery,
                                onEdit: onEdit,
                                onDelete: onDelete,
                                onRescue: onRescue,
                                onTaskStateChange: onTaskStateChange
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var defaultEmptyState: some View {
        VStack(spacing: 6) {
            Text("stream.md is empty")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("write to ~/.quickpad/stream.md and relaunch")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
