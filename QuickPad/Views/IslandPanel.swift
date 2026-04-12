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
///
/// Click pass-through uses a three-layer approach (matching claude-island):
///   1. `ignoresMouseEvents` toggled per state: compact=true, expanded=false
///   2. `PassThroughHostingView.hitTest` limits clickable area when expanded
///   3. `sendEvent` re-posts unclaimed clicks to apps behind via CGEvent
final class IslandPanel: NSPanel {

    let targetScreen: NSScreen
    let notchHeight: CGFloat

    /// Single persistent global monitor — installed once, never removed.
    /// State checks inside the callback handle both compact and expanded modes.
    /// This avoids reliability issues from repeated add/remove cycles.
    private var globalClickMonitor: Any?
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

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .init(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovable = false
        isMovableByWindowBackground = false
        // Default: ignore all mouse events. Compact pill clicks are
        // detected via a global event monitor instead. This ensures
        // the transparent panel area never blocks clicks to apps below.
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    deinit {
        if let m = globalClickMonitor {
            NSEvent.removeMonitor(m)
        }
        hoverTimer?.invalidate()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }

    // MARK: - sendEvent: re-post unclaimed clicks

    /// When expanded, forward only events that land on a view.
    /// If hitTest returns nil, collapse and re-post the click to apps behind.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            if let contentView, contentView.hitTest(event.locationInWindow) == nil {
                let screenLoc = convertPoint(toScreen: event.locationInWindow)
                // Collapse synchronously for snappy feedback.
                requestExpand(false)
                // Repost async — ignoresMouseEvents must take effect first.
                DispatchQueue.main.async { [weak self] in
                    self?.repostMouseEvent(event, at: screenLoc)
                }
                return
            }
        case .leftMouseUp, .rightMouseUp:
            if let contentView, contentView.hitTest(event.locationInWindow) == nil {
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Re-post a mouse event to the system so apps behind receive it.
    private func repostMouseEvent(_ event: NSEvent, at screenLocation: NSPoint) {
        // CGEvent uses top-left origin relative to the PRIMARY display.
        // NSScreen.screens.first is always the primary display (origin 0,0).
        guard let primaryScreen = NSScreen.screens.first else { return }
        let cgPoint = CGPoint(
            x: screenLocation.x,
            y: primaryScreen.frame.height - screenLocation.y
        )

        let cgEventType: CGEventType
        switch event.type {
        case .leftMouseDown:  cgEventType = .leftMouseDown
        case .leftMouseUp:    cgEventType = .leftMouseUp
        case .rightMouseDown: cgEventType = .rightMouseDown
        case .rightMouseUp:   cgEventType = .rightMouseUp
        default: return
        }

        guard let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: cgEventType,
            mouseCursorPosition: cgPoint,
            mouseButton: event.type == .rightMouseDown || event.type == .rightMouseUp ? .right : .left
        ) else { return }

        cgEvent.post(tap: .cghidEventTap)
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
            // Accept mouse events so SwiftUI controls work.
            ignoresMouseEvents = false
            acceptsMouseMovedEvents = true
            // nonactivatingPanel — only makeKey, never NSApp.activate.
            makeKey()
        } else {
            // Stop accepting events — all clicks pass through to apps.
            ignoresMouseEvents = true
            acceptsMouseMovedEvents = false
            resignKey()
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

    // MARK: - Global click monitor (single persistent monitor)

    /// Install once — handles both compact-click-to-expand and
    /// expanded-click-outside-to-collapse via state checks.
    func installGlobalClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            let mouse = NSEvent.mouseLocation
            if self.isExpanded {
                if !self.expandedPillScreenRect.contains(mouse) {
                    self.requestExpand(false)
                }
            } else {
                if self.compactPillScreenRect.contains(mouse) {
                    self.requestExpand(true)
                }
            }
        }
    }

    /// The expanded pill rect in screen coordinates (origin bottom-left).
    private var expandedPillScreenRect: NSRect {
        let x = frame.origin.x
        let y = frame.origin.y + frame.height - notchHeight - Self.expandedHeight
        return NSRect(x: x, y: y, width: Self.expandedWidth, height: Self.expandedHeight)
    }

    /// Compact pill rect in screen coordinates.
    var compactPillScreenRect: NSRect {
        let w = Self.compactWidth
        let h = Self.compactHeight
        let x = frame.origin.x + (frame.width - w) / 2
        let y = frame.origin.y + frame.height - notchHeight - h
        return NSRect(x: x, y: y, width: w, height: h)
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
        let y = frame.height - notchHeight - h
        return NSRect(x: x, y: y, width: w, height: h)
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
