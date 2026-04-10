import AppKit
import Observation

/// Bridges AppKit window management to the SwiftUI view layer. Manages
/// two modes:
///
/// 1. **Popover mode** (default) — attached to the menu bar status item.
///    The pin button toggles between `.transient` (auto-dismiss) and
///    `.applicationDefined` (stays open).
///
/// 2. **Floating mode** — detached into a standalone `FloatingPanel` that
///    stays on top of all windows. Triggered by the detach button (⌘D)
///    in the header.
@Observable
final class PopoverController {
    /// Injected by `AppDelegate` after the popover is built.
    @ObservationIgnored weak var popover: NSPopover?

    var isPinned: Bool = false {
        didSet { popover?.behavior = isPinned ? .applicationDefined : .transient }
    }

    /// True when the UI is showing in a floating window instead of the
    /// menu-bar popover. Drives the header's detach/reattach button.
    var isDetached: Bool = false

    /// Called by the SwiftUI layer when the user clicks detach/reattach.
    /// The actual window management is handled by AppDelegate via this
    /// callback. Ignored by Observation — closures are not view state.
    @ObservationIgnored var onDetachToggle: (() -> Void)?
}
