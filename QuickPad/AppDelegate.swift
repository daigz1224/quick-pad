import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = StreamViewModel()
    private let popoverController = PopoverController()
    private let themeManager = ThemeManager.shared
    private let hotkeyManager = HotkeyManager()
    private let fileWatcher = StreamFileWatcher()
    private var eventMonitor: Any?
    private var floatingPanel: FloatingPanel?
    private var islandPanel: IslandPanel?
    private var isIslandExpanded = false
    private let archiver = StreamArchiver()
    private var archiveTimer: Timer?
    private let pinnedStore = PinnedNoteStore()
    private var quickCapturePanel: QuickCapturePanel?
    /// Guards against `windowWillClose` firing during a programmatic
    /// `reattachToPopover` call — we don't want the delegate to
    /// double-clear state when we're already handling it.
    private var isReattaching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        configureHotkeys()
        configureFileWatcher()
        viewModel.fileWatcher = fileWatcher
        viewModel.load()
        runArchiveAndSchedule()

        // Wire the detach/reattach toggle.
        popoverController.onDetachToggle = { [weak self] in
            self?.toggleDetach()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        archiveTimer?.invalidate()
        archiveTimer = nil
        hotkeyManager.unregister()
        fileWatcher.stop()
        floatingPanel?.close()
        floatingPanel = nil
        islandPanel?.close()
        islandPanel = nil
        quickCapturePanel?.close()
        quickCapturePanel = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status item

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let icon = MenuBarIcon.make()
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        let isOptionLeftClick = event?.type == .leftMouseUp
            && event?.modifierFlags.contains(.option) == true

        if isRightClick || isOptionLeftClick {
            showContextMenu(from: sender)
        } else {
            // If floating panel is open, bring it to front instead.
            if let panel = floatingPanel, panel.isVisible {
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                togglePopover(sender)
            }
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let islandItem = NSMenuItem(
            title: islandPanel?.isVisible == true ? "Hide Island" : "Show Island",
            action: #selector(toggleIsland),
            keyEquivalent: ""
        )
        menu.addItem(islandItem)

        menu.addItem(.separator())
        menu.addItem(buildPinnedNotesItem())

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit QuickPad",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Pinned notes submenu

    private func buildPinnedNotesItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Pinned Notes", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let urls = pinnedStore.list()

        if urls.isEmpty {
            let placeholder = NSMenuItem(
                title: "No pinned notes — graduate one from a stream entry",
                action: nil,
                keyEquivalent: ""
            )
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            for url in urls {
                let item = NSMenuItem(
                    title: url.deletingPathExtension().lastPathComponent,
                    action: #selector(openPinnedNote(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = url
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let revealAll = NSMenuItem(
                title: "Reveal Folder in Finder",
                action: #selector(revealPinnedFolder),
                keyEquivalent: ""
            )
            revealAll.target = self
            submenu.addItem(revealAll)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func openPinnedNote(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealPinnedFolder() {
        let dir = PinnedNoteStore.pinnedDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    // MARK: - Popover

    private func configurePopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        // Skip the system slide-in animation — for a quick-capture
        // surface, "appears instantly" beats "slides in over 250ms".
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView()
                .environment(viewModel)
                .environment(popoverController)
                .environment(themeManager)
        )
        popoverController.popover = popover
    }

    private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Don't reload on every show — the FSEvents watcher keeps the
        // model live, and any recent mutation reloads via
        // `reloadFromDiskAnimated`. Re-parsing here just adds a stall
        // before the popover slides in.
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Floating window

    private func toggleDetach() {
        if popoverController.isDetached {
            reattachToPopover()
        } else {
            detachToFloatingWindow()
        }
    }

    private func detachToFloatingWindow() {
        // Close the popover first.
        if popover.isShown {
            popover.performClose(nil)
        }

        // Create the floating panel on the same screen as the status item.
        let targetScreen = statusItem.button?.window?.screen
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            targetScreen: targetScreen
        )
        let hostingView = NSHostingController(
            rootView: PopoverRootView()
                .environment(viewModel)
                .environment(popoverController)
                .environment(themeManager)
        )
        panel.contentViewController = hostingView

        // Watch for the panel being closed via the red button.
        panel.delegate = self

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        floatingPanel = panel
        popoverController.isDetached = true
    }

    private func reattachToPopover() {
        isReattaching = true
        floatingPanel?.close()
        floatingPanel = nil
        popoverController.isDetached = false
        isReattaching = false

        // Re-open as popover.
        showPopover()
    }

    // MARK: - Island (Dynamic Island style widget)

    @objc private func toggleIsland() {
        if let panel = islandPanel, panel.isVisible {
            hideIsland()
        } else {
            showIsland()
        }
    }

    private func showIsland() {
        if let existing = islandPanel {
            existing.orderFrontRegardless()
        } else {
            isIslandExpanded = false
            let panel = IslandPanel(screen: nil)

            // SwiftUI-initiated expand/collapse just syncs panel state.
            let handleExpandChange: (Bool) -> Void = { [weak self, weak panel] expanded in
                self?.isIslandExpanded = expanded
                panel?.requestExpand(expanded)
            }

            let hostingView = PassThroughHostingView(
                rootView: IslandView(
                    onExpandChange: handleExpandChange,
                    onDismiss: { [weak self] in self?.hideIsland() },
                    notchHeight: panel.notchHeight
                )
                .environment(viewModel)
                .environment(themeManager)
            )

            // Hit-test: only the visible pill area below the notch zone.
            // NSView.hitTest uses window coords (origin bottom-left), so
            // the pill sits at the TOP of the window, just under the notch:
            //
            //   y = totalH ┌─ notch (38pt) ─┐
            //   y = totalH - notch ├─ pill top ─┤
            //   y = totalH - notch - pillH ├─ pill bottom ─┤
            //   y = 0      └────────────────┘
            //
            hostingView.hitTestRect = { [weak panel] in
                guard let panel else { return .zero }
                let totalH = panel.frame.height
                let notch = panel.notchHeight
                let pillH = panel.isExpanded
                    ? IslandPanel.expandedHeight
                    : IslandPanel.compactHeight
                let pillW = panel.isExpanded
                    ? IslandPanel.expandedWidth
                    : IslandPanel.compactWidth
                let x = (panel.frame.width - pillW) / 2
                let y = totalH - notch - pillH
                return CGRect(x: x, y: y, width: pillW, height: pillH)
            }

            panel.contentView = hostingView
            panel.orderFrontRegardless()
            panel.startHoverTracking()
            panel.installGlobalClickMonitor()
            islandPanel = panel

            // Boot animation: flash open briefly, then auto-collapse.
            // One runloop turn lets SwiftUI render the compact state once
            // so the expand transition has a frame to animate from.
            DispatchQueue.main.async {
                panel.performBootAnimation()
            }
        }
    }

    private func hideIsland() {
        islandPanel?.orderOut(nil)
    }

    // MARK: - Quick Capture (mini panel)

    private func showQuickCapture() {
        // If popover or floating window is already up, route the
        // hotkey to that surface instead — no point stacking inputs.
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let panel = floatingPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Re-use any panel we built earlier — keeps NSPanel state
        // (size, frame) stable across captures and avoids a brief
        // flicker on rapid ⌥⇧N presses.
        if let existing = quickCapturePanel {
            existing.positionAtTopCenter()
            existing.makeKeyAndOrderFront(nil)
            existing.installEscMonitor()
            return
        }

        let panel = QuickCapturePanel()
        let host = NSHostingController(
            rootView: QuickCaptureView(
                onSubmit: { [weak self] type, text in
                    self?.viewModel.append(bulletType: type, content: text)
                    self?.quickCapturePanel?.dismiss()
                },
                onCancel: { [weak self] in
                    self?.quickCapturePanel?.dismiss()
                }
            )
            .environment(viewModel)
            .environment(themeManager)
        )
        host.view.frame = NSRect(x: 0, y: 0, width: 480, height: 56)
        // Make the hosting view transparent so the panel's blur shows.
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = host
        panel.onClose = { [weak self] in
            // Drop the reference so the next ⌥⇧N gets a fresh, freshly
            // focused panel rather than a re-shown one whose TextField
            // may have lost focus state.
            self?.quickCapturePanel = nil
        }
        panel.positionAtTopCenter()
        panel.makeKeyAndOrderFront(nil)
        panel.installEscMonitor()
        quickCapturePanel = panel
    }

    // MARK: - Auto-archive

    private func runArchiveAndSchedule() {
        // Run once on launch.
        runArchive()
        // Then once per day.
        archiveTimer = Timer.scheduledTimer(
            withTimeInterval: 86400,
            repeats: true
        ) { [weak self] _ in
            self?.runArchive()
        }
    }

    private func runArchive() {
        do {
            fileWatcher.suppressNextChange()
            let result = try archiver.run()
            if result.archivedCount > 0 || result.cleanedDeletedCount > 0 {
                viewModel.load()
            }
        } catch {
            // Archive failure is non-critical — log but don't surface.
            print("[QuickPad] archive error: \(error)")
        }
    }

    // MARK: - File watcher

    private func configureFileWatcher() {
        fileWatcher.onChange = { [weak self] in
            self?.viewModel.load()
        }
        fileWatcher.start()
    }

    // MARK: - Hotkeys

    private func configureHotkeys() {
        hotkeyManager.onHotkey = { [weak self] action in
            guard let self else { return }
            switch action {
            case .togglePopover:
                if let panel = self.floatingPanel, panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    self.togglePopover(nil)
                }
            case .quickCapture:
                self.showQuickCapture()
            }
        }
        hotkeyManager.register()
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === floatingPanel,
              !isReattaching else { return }
        // User closed the floating panel via the red button —
        // revert to popover mode (but don't auto-open the popover).
        floatingPanel = nil
        popoverController.isDetached = false
    }
}
