import AppKit
import SwiftUI

// MARK: - NSScreen extensions

extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }
        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else {
            return CGSize(width: 180, height: notchHeight)
        }
        return CGSize(width: fullWidth - leftPadding - rightPadding + 4, height: notchHeight)
    }

    var hasPhysicalNotch: Bool { safeAreaInsets.top > 0 }

    static var builtinOrMain: NSScreen {
        screens.first(where: { $0.hasPhysicalNotch }) ?? main ?? screens[0]
    }
}

// MARK: - Pass-through hosting view

/// Only captures mouse events within the pill rect; everything else
/// passes through to apps behind.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestRect().contains(point) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - IslandPanel

/// A transparent, fixed-size overlay panel that sits above the menubar.
/// The window NEVER resizes — all animation happens inside SwiftUI.
/// This eliminates dual-animation-system conflicts (AppKit vs SwiftUI).
final class IslandPanel: NSPanel {

    let targetScreen: NSScreen
    let notchHeight: CGFloat

    private var clickOutsideMonitor: Any?
    private var hoverTimer: Timer?
    private(set) var isExpanded: Bool = false

    // MARK: - Notifications (panel → SwiftUI sync)

    static let collapseNotification = Notification.Name("IslandPanelCollapse")
    static let expandNotification  = Notification.Name("IslandPanelExpand")
    static let bounceNotification  = Notification.Name("IslandPanelBounce")

    // MARK: - Sizing constants (used by IslandView for the pill shape)

    static let compactWidth:  CGFloat = 220
    static let compactHeight: CGFloat = 34
    static let expandedWidth: CGFloat = 360
    static let expandedHeight: CGFloat = 340

    // MARK: - Init

    init(screen: NSScreen?) {
        let target = screen ?? .builtinOrMain
        self.targetScreen = target
        self.notchHeight = target.safeAreaInsets.top

        // Fixed frame: always large enough for the expanded state.
        // The window never resizes — SwiftUI animates the pill inside.
        let fixedFrame = Self.fixedFrame(on: target)

        super.init(
            contentRect: fixedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .init(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    deinit {
        removeClickOutsideMonitor()
        hoverTimer?.invalidate()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }

    // MARK: - Fixed frame

    /// The one-and-only frame: top-anchored at screen top, wide enough
    /// for the expanded pill, tall enough for notch + expanded content.
    static func fixedFrame(on screen: NSScreen) -> NSRect {
        let notch = screen.safeAreaInsets.top
        let totalHeight = notch + expandedHeight
        let x = screen.frame.midX - expandedWidth / 2
        let y = screen.frame.maxY - totalHeight
        return NSRect(x: x, y: y, width: expandedWidth, height: totalHeight)
    }

    // MARK: - Expand / Collapse (driven by notifications)

    /// Centralized expand/collapse. Posts a notification so SwiftUI
    /// updates `@State isExpanded` — the pill shape animates via springs.
    func requestExpand(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded

        if expanded {
            installClickOutsideMonitor()
        } else {
            removeClickOutsideMonitor()
        }

        NotificationCenter.default.post(
            name: expanded ? Self.expandNotification : Self.collapseNotification,
            object: nil
        )
    }

    // MARK: - Bounce

    func bounce() {
        guard !isExpanded else { return }
        NotificationCenter.default.post(name: Self.bounceNotification, object: nil)
    }

    // MARK: - Boot animation

    func performBootAnimation() {
        requestExpand(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.requestExpand(false)
        }
    }

    // MARK: - Click outside

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isExpanded else { return }
            let mouse = NSEvent.mouseLocation
            let pillRect = self.expandedPillScreenRect
            if !pillRect.contains(mouse) {
                DispatchQueue.main.async {
                    self.requestExpand(false)
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
    }

    /// The expanded pill rect in screen coordinates.
    private var expandedPillScreenRect: NSRect {
        let x = frame.origin.x
        let y = frame.origin.y
        return NSRect(x: x, y: y, width: Self.expandedWidth, height: Self.expandedHeight)
    }

    // MARK: - Hover

    func startHoverTracking() {
        guard let contentView else { return }
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        contentView.addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isExpanded else { return }
        if compactPillLocalRect.contains(event.locationInWindow) {
            startHoverTimer()
        }
    }

    override func mouseExited(with event: NSEvent) {
        cancelHoverTimer()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isExpanded else { return }
        if compactPillLocalRect.contains(event.locationInWindow) {
            if hoverTimer == nil { startHoverTimer() }
        } else {
            cancelHoverTimer()
        }
    }

    /// Compact pill rect in window-local coords (origin bottom-left).
    private var compactPillLocalRect: NSRect {
        let w = Self.compactWidth
        let h = Self.compactHeight
        let x = (frame.width - w) / 2
        // Pill sits at the bottom of the notch zone → y = 0 to compactHeight
        return NSRect(x: x, y: 0, width: w, height: h)
    }

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self, !self.isExpanded else { return }
            self.requestExpand(true)
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
