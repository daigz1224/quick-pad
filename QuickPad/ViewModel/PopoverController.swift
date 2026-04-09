import AppKit
import Observation

/// Bridges AppKit's `NSPopover` to the SwiftUI view layer. Holds a weak
/// reference to the popover so the pin button can flip `behavior`
/// between `.transient` (auto-dismiss on outside click) and
/// `.applicationDefined` (stays until the user explicitly closes it).
///
/// Phase 3 in the architecture doc describes a more elaborate
/// "drag-to-detach" floating-window pin; this is the lightweight
/// precursor — same mental model, much less plumbing.
@Observable
final class PopoverController {
    /// Injected by `AppDelegate` after the popover is built.
    @ObservationIgnored weak var popover: NSPopover?

    var isPinned: Bool = false {
        didSet { popover?.behavior = isPinned ? .applicationDefined : .transient }
    }
}
