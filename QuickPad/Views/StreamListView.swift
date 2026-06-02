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
    /// Caller has already applied soft-delete + type-filter passes.
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
    var onBulletTypeChange: ((StreamEntry, BulletType) -> Void)?
    var onGraduate: ((StreamEntry) -> Void)?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var scheme

    private var visibleSections: [StreamSection] { sections }

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
                        .padding(.horizontal, 10)
                        .padding(.top, index == 0 ? 6 : 10)
                        .padding(.bottom, 4)

                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { entryIdx, entry in
                            StreamEntryRow(
                                entry: entry,
                                highlightQuery: highlightQuery,
                                onEdit: section.isReadOnly ? nil : onEdit,
                                onDelete: section.isReadOnly ? nil : onDelete,
                                onRescue: section.isReadOnly ? nil : onRescue,
                                onTaskStateChange: section.isReadOnly ? nil : onTaskStateChange,
                                onBulletTypeChange: section.isReadOnly ? nil : onBulletTypeChange,
                                onGraduate: section.isReadOnly ? nil : onGraduate
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            if entryIdx < section.entries.count - 1 {
                                // Whisper-quiet hairline between entries — gives
                                // each capture a contained "card" feel without
                                // adding visual weight.
                                Rectangle()
                                    .fill(theme.divider(for: scheme).opacity(0.35))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 18)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
            .mask(
                VStack(spacing: 0) {
                    Color.black
                    // Bottom fade hint — indicates scrollable content below
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 12)
                }
            )
        }
    }

    private var defaultEmptyState: some View {
        EmptyStateView(icon: "text.justify.leading", title: "your stream is empty", hint: "type above to start capturing")
    }
}
