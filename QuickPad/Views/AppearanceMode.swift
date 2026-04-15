import AppKit
import SwiftUI

/// Persisted in `@AppStorage("appearanceMode")`. The header button cycles
/// through these on click.
enum AppearanceMode: String, CaseIterable {
    case auto
    case light
    case dark

    var next: AppearanceMode {
        switch self {
        case .auto: return .light
        case .light: return .dark
        case .dark: return .auto
        }
    }

    /// SF Symbol for the header button.
    var iconName: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var tooltip: String {
        switch self {
        case .auto: return "Appearance: Auto (follow system)"
        case .light: return "Appearance: Light"
        case .dark: return "Appearance: Dark"
        }
    }
}

/// Observable wrapper around `NSApp.effectiveAppearance`. We can't rely
/// on `@Environment(\.colorScheme)` inside an `NSPopover` — the popover
/// host doesn't propagate system appearance changes consistently, which
/// is why "Auto" used to look stuck on Dark. KVO on
/// `NSApplication.effectiveAppearance` gives us the live system value.
@Observable
@MainActor
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var scheme: ColorScheme

    private var observation: NSKeyValueObservation?

    private init() {
        scheme = Self.resolve(NSApp.effectiveAppearance)
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            let new = Self.resolve(app.effectiveAppearance)
            Task { @MainActor in
                self?.scheme = new
            }
        }
    }

    private static func resolve(_ appearance: NSAppearance) -> ColorScheme {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }
}
