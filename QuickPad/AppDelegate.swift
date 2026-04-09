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

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        configureHotkeys()
        configureFileWatcher()
        viewModel.load()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        fileWatcher.stop()
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
            togglePopover(sender)
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
        // Detach menu so left-click reverts to popover behaviour next time.
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
        // Give the pin button a handle to mutate behavior at runtime.
        popoverController.popover = popover
    }

    private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    /// Opens the popover if it isn't already, reloads stream.md, and
    /// brings QuickPad forward so the `InputBar` TextField can receive
    /// keystrokes even when another app was frontmost (this is the hot
    /// path for the ⌥N / ⌥⇧N global hotkeys).
    ///
    /// Notes on the "everything looks selected" artifact: we rely on
    /// `.focusEffectDisabled()` on the SwiftUI root + `@FocusState` in
    /// `InputBar` landing first-responder on the text field itself
    /// (never on a button), so `makeKey()` no longer paints that bright
    /// outline around the first focusable header button.
    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Reload from disk on every open so vim/grep edits show up
        // even before the FSEvents watcher lands.
        viewModel.load()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - File watcher

    private func configureFileWatcher() {
        fileWatcher.onChange = { [weak self] in
            // FSEvents fires for our own writes too — `StreamViewModel.append`
            // already reloads eagerly, so a second reload here is a
            // no-op but strictly correct (catches races where vim and
            // QuickPad both touch the file between ticks).
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
                // ⌥N — mirrors clicking the menu bar icon.
                self.togglePopover(nil)
            case .quickCapture:
                // ⌥⇧N — "always open, never close". Hammering on this
                // from another app should never accidentally hide the
                // popover mid-thought.
                self.showPopover()
            }
        }
        hotkeyManager.register()
    }
}
