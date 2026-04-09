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

    /// Nil means "follow system" — SwiftUI interprets nil
    /// `.preferredColorScheme` as no override.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
