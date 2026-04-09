import SwiftUI

/// Top-level container for the menu-bar popover. Owns the
/// `StreamViewModel` lookup via `@Environment` so the AppDelegate can
/// inject one shared instance.
struct PopoverRootView: View {
    @Environment(StreamViewModel.self) private var viewModel
    @Environment(PopoverController.self) private var popoverController
    @Environment(\.colorScheme) private var systemColorScheme

    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.auto.rawValue

    // Search mode. @State persists across popover open/close cycles
    // because NSHostingController keeps the SwiftUI view tree alive,
    // which we want — reopening the popover shouldn't throw away an
    // in-progress search.
    @State private var searchQuery: String = ""
    @State private var isSearching: Bool = false

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    /// The effective light/dark state after the Auto/Light/Dark override
    /// is applied. We compute this ourselves instead of reading
    /// `colorScheme` after `preferredColorScheme` because the background
    /// color has to match the appearance *we* chose, not whatever the
    /// hosting window defaults to on first mount.
    private var isDark: Bool {
        switch appearance {
        case .light: return false
        case .dark: return true
        case .auto: return systemColorScheme == .dark
        }
    }

    /// Deeper-than-system background. `NSColor.windowBackgroundColor` in
    /// dark mode sits around #2E2E2E which reads as medium gray; here we
    /// push to ~#17171A to match the "真·黑夜" look of apps like Raycast
    /// and Linear.
    private var backgroundColor: Color {
        if isDark {
            return Color(red: 0.09, green: 0.09, blue: 0.10)
        } else {
            return Color(red: 0.99, green: 0.99, blue: 1.00)
        }
    }

    var body: some View {
        @Bindable var popoverController = popoverController

        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.5)
            if isSearching {
                SearchBar(query: $searchQuery, onDismiss: dismissSearch)
            } else {
                InputBar()
            }
            StreamListView(
                sections: filteredSections,
                highlightQuery: isSearching ? searchQuery : "",
                emptyStateOverride: isSearching && !searchQuery.isEmpty
                    ? AnyView(searchEmptyState)
                    : nil
            )
        }
        .frame(width: 420, height: 520)
        .background(backgroundColor)
        .preferredColorScheme(appearance.colorScheme)
        // Belt-and-suspenders against the "everything looks selected"
        // artifact: disable text selection on every Text underneath and
        // disable the focus ring that macOS 14 draws around the first
        // focusable button when the popover is shown.
        .textSelection(.disabled)
        .focusEffectDisabled()
        // Hidden ⌘F handler. `.keyboardShortcut` on a Button intercepts
        // the combo from anywhere in the popover — even while the
        // `InputBar` TextField has first-responder focus — because
        // SwiftUI routes keyboard shortcuts through the view hierarchy
        // before the responder chain sees them.
        .background {
            Button("Find") {
                isSearching = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - Search helpers

    /// Entries filtered by the current search query. Case-insensitive
    /// substring match against `content` (falling back to `rawLine`
    /// for unparsed entries). Sections with zero matches are dropped
    /// so the user doesn't see bare day separators.
    private var filteredSections: [StreamSection] {
        guard isSearching, !searchQuery.isEmpty else {
            return viewModel.sections
        }
        let needle = searchQuery.lowercased()
        return viewModel.sections.compactMap { section in
            let hits = section.entries.filter { entry in
                entry.content.lowercased().contains(needle)
                    || entry.rawLine.lowercased().contains(needle)
            }
            guard !hits.isEmpty else { return nil }
            var copy = section
            copy.entries = hits
            return copy
        }
    }

    private func dismissSearch() {
        isSearching = false
        searchQuery = ""
    }

    private var searchEmptyState: some View {
        VStack(spacing: 6) {
            Text("no matches")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("esc to exit search")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var popoverController = popoverController

        return HStack(spacing: 8) {
            Image(systemName: "list.dash")
                .foregroundStyle(.secondary)
            Text("QuickPad")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            if viewModel.isShowingSample {
                Text("sample")
                    .font(.system(size: 9, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()

            appearanceButton
            pinButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var appearanceButton: some View {
        Button {
            appearanceRaw = appearance.next.rawValue
        } label: {
            Image(systemName: appearance.iconName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appearance.tooltip)
    }

    @ViewBuilder
    private var pinButton: some View {
        @Bindable var popoverController = popoverController

        Button {
            popoverController.isPinned.toggle()
        } label: {
            Image(systemName: popoverController.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .foregroundStyle(popoverController.isPinned ? Color.accentColor : .secondary)
                .rotationEffect(.degrees(popoverController.isPinned ? -30 : 0))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(popoverController.isPinned ? "Unpin (auto-close on click outside)" : "Pin (stay open)")
    }
}
