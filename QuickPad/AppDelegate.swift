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

        // Wire the detach/reattach toggle.
        popoverController.onDetachToggle = { [weak self] in
            self?.toggleDetach()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        fileWatcher.stop()
        floatingPanel?.close()
        floatingPanel = nil
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
