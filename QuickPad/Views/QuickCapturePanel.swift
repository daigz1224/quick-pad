import AppKit
import SwiftUI

/// Borderless `NSPanel` that hosts the mini quick-capture input.
///
/// Why an `NSPanel` (not a popover or window):
/// - `.nonactivatingPanel` style means our app does not steal frontmost
///   focus when the panel is shown — the user can fire ⌥⇧N from any
///   app, type, hit Enter, and they're back in their original app
///   without ever seeing QuickPad come to the foreground.
/// - `.floating` level so it sits above whatever the user is doing.
/// - We take key window status only while the panel is up, then resign
///   on close so the prior app refocuses naturally.
final class QuickCapturePanel: NSPanel {

    /// Called by the AppDelegate when the user submits an entry. Lives
    /// here so the SwiftUI view doesn't need to know about NSPanel.
    var onSubmit: ((BulletType, String) -> Void)?

    /// Called when the panel dismisses (Esc, click-away, or after submit).
    var onClose: (() -> Void)?

    /// Resign-on-resign-key is what gives us the click-away-to-dismiss
    /// behaviour without needing an event monitor.
    private var localKeyMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        // The panel frame now equals the rounded pill (no SwiftUI
        // padding around it), so the system shadow tracks the visible
        // shape via Core Animation — no boxy halo.
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        // Critical for LSUIElement background apps: if true, the panel
        // is hidden the instant it appears because our app is never
        // "active" when the user fires ⌥⇧N from another app. We rely
        // on Esc + resignKey for dismissal instead.
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Click-away dismissal: the moment another window steals key
    /// status, fold the panel up. Replaces hidesOnDeactivate (which we
    /// can't use — see init).
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            self?.dismiss()
        }
    }

    /// Position the panel centered horizontally on the active screen,
    /// with its TOP edge at ~80% of screen height (about a fifth down
    /// from the top of the visible area).
    ///
    /// Anchored to the top-left rather than bottom-left because
    /// SwiftUI's intrinsic-size layout can grow the panel after we
    /// position it — if we anchored the bottom, the panel would
    /// visibly drift upward between invocations.
    func positionAtTopCenter() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = self.frame.size
        let x = visible.minX + (visible.width - size.width) / 2
        let topY = visible.minY + visible.height * 0.80
        self.setFrameTopLeftPoint(NSPoint(x: x, y: topY))
    }

    func dismiss() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        self.orderOut(nil)
        onClose?()
    }

    /// Called by AppDelegate after `makeKeyAndOrderFront`. Installs an
    /// Esc-key local monitor so the user can dismiss without clicking.
    func installEscMonitor() {
        if localKeyMonitor != nil { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc keyCode = 53
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
    }
}
