import AppKit
import SwiftUI

/// A borderless, always-on-top panel that hosts the same `PopoverRootView`
/// as the menu-bar popover. Created when the user clicks the "detach"
/// button in the header; destroyed when they click "reattach" or close
/// the panel.
///
/// Key design choices:
/// - `NSPanel` with `.nonactivatingPanel` so the app behind QuickPad
///   doesn't lose focus when the user interacts with the panel — except
///   when typing in the input bar (we call `makeKey()` explicitly then).
/// - `.floating` window level so it stays above regular windows.
/// - Transparent titlebar with full-size content view for a clean look.
/// - Movable by background so any empty area acts as a drag handle.
final class FloatingPanel: NSPanel {

    /// - Parameter targetScreen: The screen to place the panel on. Falls
    ///   back to `NSScreen.main` if nil. Pass the screen where the
    ///   status item lives so the panel appears on the same display.
    init(contentRect: NSRect, targetScreen: NSScreen? = nil) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false

        // Minimum size to keep the UI usable.
        minSize = NSSize(width: 320, height: 400)

        // Allow the panel to become key so the TextField can receive
        // keystrokes, but don't force it — `.nonactivatingPanel` means
        // clicking a non-input area won't steal focus from other apps.
        isFloatingPanel = true

        // Center horizontally, upper quarter of the target screen.
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.origin.x + (visibleFrame.width - contentRect.width) / 2
            let y = visibleFrame.origin.y + visibleFrame.height * 0.65
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Allow the panel to become key window so text fields work.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
