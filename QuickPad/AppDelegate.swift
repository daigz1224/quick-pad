import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = StreamViewModel()
    private let popoverController = PopoverController()
    private let hotkeyManager = HotkeyManager()
    private let fileWatcher = StreamFileWatcher()
    private var eventMonitor: Any?
    private var floatingPanel: FloatingPanel?
    private var islandPanel: IslandPanel?
    private var isIslandExpanded = false
    private let archiver = StreamArchiver()
    private var archiveTimer: Timer?
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
        if event?.type == .rightMouseUp {
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

    // MARK: - Popover

    private func configurePopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView()
                .environment(viewModel)
                .environment(popoverController)
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
        viewModel.load()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                panel.performBootAnimation()
            }
        }
    }

    private func hideIsland() {
        islandPanel?.orderOut(nil)
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
                if let panel = self.floatingPanel, panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    self.showPopover()
                }
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
