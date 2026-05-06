import SwiftUI

/// Top-level container for the menu-bar popover. Owns the
/// `StreamViewModel` lookup via `@Environment` so the AppDelegate can
/// inject one shared instance.
struct PopoverRootView: View {
    @Environment(StreamViewModel.self) private var viewModel
    @Environment(PopoverController.self) private var popoverController
    @Environment(ThemeManager.self) private var theme
    @State private var systemAppearance = SystemAppearance.shared

    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.auto.rawValue
    // Default on so filtering is discoverable without learning ⌘1-5.
    @AppStorage("showHintBar") private var showHintBar: Bool = true
    @AppStorage("showStatsBar") private var showStatsBar: Bool = true

    /// Owns bullet-type + draft state shared between InputBar and HintBar.
    @State private var inputModel = InputBarModel()

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

    /// Toast for graduate feedback, with a Reveal action.
    @State private var graduateToast: URL? = nil
    @State private var graduateTimer: Timer? = nil

    /// Keyboard shortcut hints overlay.
    @State private var showShortcutHints: Bool = false

    /// Review mode overlay (⌘R).
    @State private var showReview: Bool = false

    /// ⌘⇧E ranged-export sheet. ⌘E remains "export everything visible";
    /// ⌘⇧E adds the time-window picker without changing the muscle memory.
    @State private var showExportSheet: Bool = false


    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    private var effectiveScheme: ColorScheme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemAppearance.scheme
        }
    }

    private var backgroundColor: Color {
        theme.background(for: effectiveScheme)
    }

    var body: some View {
        @Bindable var popoverController = popoverController

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                ThemeFadeDivider()
                if showStatsBar && !viewModel.sections.isEmpty && !isSearching {
                    StreamStatsBar()
                        .transition(.opacity)
                }
                if isSearching {
                    SearchBar(query: $searchQuery, onDismiss: dismissSearch)
                } else {
                    InputBar()
                    if showHintBar {
                        HintBar(typeFilter: $typeFilter)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
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
                    onBulletTypeChange: { entry, newType in
                        viewModel.changeBulletType(entry, newType: newType)
                    },
                    onGraduate: { entry in
                        viewModel.graduateEntry(entry)
                        showGraduateToast()
                    }
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

            // Graduate toast
            if let url = graduateToast {
                graduateToastView(url)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }

            // Review mode overlay (⌘R)
            if showReview {
                ReviewMode(onClose: { showReview = false })
                    .frame(width: 420, height: 520)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            // Shortcut hints overlay
            if showShortcutHints {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showShortcutHints = false }

                ShortcutHintsView { showShortcutHints = false }
            }
        }
        .frame(width: 420, height: 520)
        .background(backgroundColor)
        .preferredColorScheme(effectiveScheme)
        .environment(inputModel)
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
                Button("FilterQuestion") { toggleFilter(.question) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("FilterIdea") { toggleFilter(.idea) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("FilterAll") { typeFilter = nil }
                    .keyboardShortcut("5", modifiers: .command)

                // ⌘E export
                Button("Export") { StreamExporter.savePanel(sections: filteredSections) }
                    .keyboardShortcut("e", modifiers: .command)

                // ⌘⇧E ranged export
                Button("ExportRange") { showExportSheet = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                // ⌘D detach/reattach
                Button("Detach") { popoverController.onDetachToggle?() }
                    .keyboardShortcut("d", modifiers: .command)

                // ⌘/ shortcut hints
                Button("Hints") { showShortcutHints.toggle() }
                    .keyboardShortcut("/", modifiers: .command)

                // ⌘R review mode
                Button("Review") { showReview.toggle() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .onAppear {
            // FSEvents + the launch-time `viewModel.load()` keep the
            // model fresh, so we don't reload on appear — that just
            // adds a stall on first show.
            //
            // Pre-warm the archive cache so the first ⌘F keystroke
            // doesn't pay the disk hit when the user wants to search
            // back into archived months.
            Task.detached(priority: .utility) {
                _ = MarkdownFileStore().loadArchives()
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportRangeSheet { interval in
                StreamExporter.savePanel(
                    sections: filteredSections,
                    dateInterval: interval
                )
            }
            .environment(theme)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.undoEntry != nil)
        .animation(.easeInOut(duration: 0.2), value: rescueToast != nil)
        .animation(.easeInOut(duration: 0.2), value: graduateToast != nil)
        .animation(.easeInOut(duration: 0.15), value: typeFilter)
        .animation(.easeInOut(duration: 0.2), value: showShortcutHints)
        .animation(.easeInOut(duration: 0.15), value: showHintBar)
        .animation(.easeInOut(duration: 0.15), value: showStatsBar)
        .animation(.easeInOut(duration: 0.2), value: showReview)
    }

    // MARK: - Type filter

    private func toggleFilter(_ type: BulletType) {
        if typeFilter == type {
            typeFilter = nil
        } else {
            typeFilter = type
        }
    }

    // MARK: - Search helpers

    private var filteredSections: [StreamSection] {
        // Hot path: no search active. Use the cached visibility filter
        // on the view model so this doesn't recompute on every render.
        guard isSearching, !searchQuery.isEmpty else {
            return viewModel.visibleSections(typeFilter: typeFilter)
        }

        let needle = searchQuery.lowercased()
        var results = viewModel.sections.compactMap { section -> StreamSection? in
            let hits = section.entries.filter { matches($0, needle: needle) }
            guard !hits.isEmpty else { return nil }
            var copy = section
            copy.entries = hits
            return copy
        }

        // Extend the search into ~/.quickpad/archive/*.md so months-old
        // entries remain findable. Hits go into a single synthetic
        // "FROM ARCHIVE" section appended to the end of the result list.
        // `loadArchives` itself is cached (signature-keyed) so repeated
        // keystrokes don't re-parse the archive on disk.
        let archiveHits = MarkdownFileStore()
            .loadArchives()
            .flatMap { $0.entries }
            .filter { matches($0, needle: needle) }

        if !archiveHits.isEmpty {
            results.append(StreamSection(
                date: nil,
                rawHeader: "── FROM ARCHIVE ──",
                entries: archiveHits,
                isReadOnly: true
            ))
        }
        // Search results still need the soft-delete + type-filter pass
        // before rendering. Uncached because the input changes per
        // keystroke and the result set is small.
        return StreamViewModel.applyVisibilityFilter(results, typeFilter: typeFilter)
    }

    private func matches(_ entry: StreamEntry, needle: String) -> Bool {
        entry.content.lowercased().contains(needle)
            || entry.rawLine.lowercased().contains(needle)
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
        EmptyStateView(icon: "magnifyingglass", title: "no matches", hint: "esc to exit search")
    }

    private var filterEmptyState: some View {
        EmptyStateView(icon: "line.3.horizontal.decrease", title: "no \(typeFilter?.label ?? "") entries", hint: "⌘5 to clear filter")
    }

    // MARK: - Undo toast

    private var undoToast: some View {
        toastPill(icon: "trash", iconColor: theme.priority.opacity(0.8), message: "Deleted", onAction: performUndo)
    }

    private func performUndo() {
        // Rescue undo takes priority if both are active.
        if rescueToast != nil && viewModel.undoRescueSnapshot != nil {
            performUndoRescue()
        } else {
            undoTimer?.invalidate()
            undoTimer = nil
            viewModel.undoDelete()
        }
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
        toastPill(icon: "arrow.up.to.line", iconColor: theme.accent, message: message, onAction: performUndoRescue)
    }

    private func toastPill(icon: String, iconColor: Color, message: String, onAction: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
            Text(message)
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.textPrimary(for: effectiveScheme))
            Spacer()
            Button(action: onAction) {
                Text("Undo ⌘Z")
                    .font(theme.monoFont(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(Theme.SubtleButton())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 24)
    }

    private func showRescueToast() {
        rescueTimer?.invalidate()
        rescueToast = "rescued ↑ back to today"
        rescueTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                rescueToast = nil
                viewModel.undoRescueSnapshot = nil
            }
        }
    }

    private func performUndoRescue() {
        rescueTimer?.invalidate()
        rescueTimer = nil
        rescueToast = nil
        viewModel.undoRescue()
    }

    // MARK: - Graduate toast

    private func graduateToastView(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 10))
                .foregroundStyle(theme.accent)
            Text("graduated → \(url.lastPathComponent)")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.textPrimary(for: effectiveScheme))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Text("Reveal")
                    .font(theme.monoFont(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(Theme.SubtleButton())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 24)
    }

    private func showGraduateToast() {
        guard let url = viewModel.lastGraduatedNoteURL else { return }
        graduateTimer?.invalidate()
        graduateToast = url
        graduateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            DispatchQueue.main.async {
                graduateToast = nil
                viewModel.lastGraduatedNoteURL = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var popoverController = popoverController

        return HStack(spacing: 10) {
            Text("QuickPad")
                .font(theme.uiFont(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary(for: effectiveScheme))
                .tracking(0.1)
            if viewModel.isShowingSample {
                Text("sample")
                    .font(theme.monoFont(size: 9))
                    .tracking(0.3)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Group the chrome into two clusters so 4-5 icons don't
            // read as a single overwhelming strip. Left cluster is
            // "view settings", right cluster is "window state".
            HStack(spacing: 2) {
                statsBarToggle
                hintBarToggle
                appearanceButton
                exportButton
            }
            Rectangle()
                .fill(theme.textTertiary(for: effectiveScheme).opacity(0.18))
                .frame(width: 0.5, height: 14)
                .padding(.horizontal, 2)
            HStack(spacing: 2) {
                detachButton
                if !popoverController.isDetached {
                    pinButton
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statsBarToggle: some View {
        Button {
            showStatsBar.toggle()
        } label: {
            Image(systemName: showStatsBar ? "chart.bar.fill" : "chart.bar")
                .font(.system(size: 10))
                .foregroundStyle(showStatsBar ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(Theme.SubtleButton())
        .help(showStatsBar ? "Hide stats strip" : "Show stats strip")
    }

    private var hintBarToggle: some View {
        Button {
            showHintBar.toggle()
        } label: {
            Image(systemName: showHintBar ? "rectangle.bottomthird.inset.filled" : "rectangle")
                .font(.system(size: 11))
                .foregroundStyle(showHintBar ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(Theme.SubtleButton())
        .help(showHintBar ? "Hide hint bar" : "Show hint bar")
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
        .buttonStyle(Theme.SubtleButton())
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
        .buttonStyle(Theme.SubtleButton())
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
        .buttonStyle(Theme.SubtleButton())
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
        .buttonStyle(Theme.SubtleButton())
        .help(popoverController.isPinned ? "Unpin (auto-close on click outside)" : "Pin (stay open)")
    }
}
