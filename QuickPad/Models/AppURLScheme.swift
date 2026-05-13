import Foundation

/// Single source of truth for QuickPad's custom URL scheme. Compiled
/// into both the main app (which handles incoming URLs) and the widget
/// extension (which constructs them on tap) so the two can't drift
/// apart. Must stay in sync with `CFBundleURLSchemes` in
/// `QuickPad/Info.plist`.
enum AppURLScheme {
    static let scheme = "quickpad"

    /// `quickpad://open` — fired when the user taps anywhere on a
    /// desktop widget. The main app brings up the popover.
    static let openURL = URL(string: "\(scheme)://open")!
}
