import SwiftUI

/// Top-level container for the menu-bar popover. Owns the
/// `StreamViewModel` lookup via `@Environment` so the AppDelegate can
/// inject one shared instance.
struct PopoverRootView: View {
    @Environment(StreamViewModel.self) private var viewModel
    @Environment(PopoverController.self) private var popoverController
    @Environment(\.colorScheme) private var systemColorScheme

    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.auto.rawValue

    // Search mode.
    @State private var searchQuery: String = ""
    @State private var isSearching: Bool = false

    // Type filter (⌘1-5). Nil = show all.
    @State private var typeFilter: BulletType? = nil

    /// Auto-dismiss timer for the undo toast.
    @State private var undoTimer: Timer?

    /// Toast message for rescue feedback.
    @State private var rescueToast: String? = nil
    @State private var rescueTimer: Timer? = nil

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    private var isDark: Bool {
        switch appearance {
        case .light: return false
        case .dark: return true
        case .auto: return systemColorScheme == .dark
        }
    }

    private var backgroundColor: Color {
        if isDark {
            return Color(red: 0.09, green: 0.09, blue: 0.10)
        } else {
            return Color(red: 0.99, green: 0.99, blue: 1.00)
        }
    }

    var body: some View {
        @Bindable var popoverController = popoverController

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                Divider()
                    .opacity(0.5)
                if isSearching {
                    SearchBar(query: $searchQuery, onDismiss: dismissSearch)
                } else {
                    InputBar()
                }

                // Type filter indicator
                if let filter = typeFilter {
                    filterBar(filter)
                }

                StreamListView(
                    sections: filteredSections,
                    highlightQuery: isSearching ? searchQuery : "",
                    emptyStateOverride: emptyStateOverride,
                    onEdit: { entry, newContent in
                        viewModel.editEntry(entry, newContent: newContent)
                    },
                    onDelete: { entry in
                        viewModel.deleteEntry(entry)
                        scheduleUndoDismissal()
                    },
                    onRescue: { entry in
                        viewModel.rescueEntry(entry)
                        showRescueToast()
                    },
                    onTaskStateChange: { entry, newState in
                        viewModel.setTaskState(entry, newState: newState)
                    },
                    typeFilter: typeFilter
                )
            }

            // Undo toast
            if viewModel.undoEntry != nil {
                undoToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }

            // Rescue toast
            if let msg = rescueToast {
                rescueToastView(msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 420, height: 520)
        .background(backgroundColor)
        .preferredColorScheme(appearance.colorScheme)
        .textSelection(.disabled)
        .focusEffectDisabled()
        .background {
            // Hidden keyboard shortcut handlers.
            Group {
                Button("Find") { isSearching = true }
                    .keyboardShortcut("f", modifiers: .command)

                Button("Undo") { performUndo() }
                    .keyboardShortcut("z", modifiers: .command)

                // ⌘1-5 type filters
                Button("FilterNote") { toggleFilter(.note) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("FilterTask") { toggleFilter(.task) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("FilterEvent") { toggleFilter(.event) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("FilterIdea") { toggleFilter(.idea) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("FilterAll") { typeFilter = nil }
                    .keyboardShortcut("5", modifiers: .command)

                // ⌘E export
                Button("Export") { StreamExporter.savePanel(sections: filteredSections) }
                    .keyboardShortcut("e", modifiers: .command)

                // ⌘D detach/reattach
                Button("Detach") { popoverController.onDetachToggle?() }
                    .keyboardShortcut("d", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .onAppear { viewModel.load() }
        .animation(.easeInOut(duration: 0.2), value: viewModel.undoEntry != nil)
        .animation(.easeInOut(duration: 0.2), value: rescueToast != nil)
    }

    // MARK: - Type filter

    private func toggleFilter(_ type: BulletType) {
        if typeFilter == type {
            typeFilter = nil
        } else {
            typeFilter = type
        }
    }

    private func filterBar(_ filter: BulletType) -> some View {
        HStack(spacing: 6) {
            Text("Showing: \(filter.label)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                typeFilter = nil
            } label: {
                Text("⌘5 clear")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.06))
    }

    // MARK: - Search helpers

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

    private var emptyStateOverride: AnyView? {
        if isSearching && !searchQuery.isEmpty {
            return AnyView(searchEmptyState)
        }
        if typeFilter != nil {
            return AnyView(filterEmptyState)
        }
        return nil
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

    private var filterEmptyState: some View {
        VStack(spacing: 6) {
            Text("no \(typeFilter?.label ?? "") entries")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("⌘5 to clear filter")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Undo toast

    private var undoToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Deleted")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                performUndo()
            } label: {
                Text("Undo ⌘Z")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .padding(.horizontal, 16)
    }

    private func performUndo() {
        undoTimer?.invalidate()
        undoTimer = nil
        viewModel.undoDelete()
    }

    private func scheduleUndoDismissal() {
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                viewModel.undoEntry = nil
            }
        }
    }

    // MARK: - Rescue toast

    private func rescueToastView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.to.line")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .padding(.horizontal, 16)
    }

    private func showRescueToast() {
        rescueTimer?.invalidate()
        rescueToast = "rescued ↑ back to today"
        rescueTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async {
                rescueToast = nil
            }
        }
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

            exportButton
            appearanceButton
            detachButton
            if !popoverController.isDetached {
                pinButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var exportButton: some View {
        Button {
            StreamExporter.savePanel(sections: filteredSections)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Export visible entries (⌘E)")
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

    /// Detach from popover into floating window, or reattach.
    private var detachButton: some View {
        Button {
            popoverController.onDetachToggle?()
        } label: {
            Image(systemName: popoverController.isDetached
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11))
                .foregroundStyle(popoverController.isDetached ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(popoverController.isDetached
              ? "Reattach to menu bar"
              : "Detach to floating window")
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
