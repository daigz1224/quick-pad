import SwiftUI

/// Centralized color palette for QuickPad. Replaces scattered raw
/// system colors (.yellow, .green, .blue) with muted, coordinated
/// tones that feel premium in both light and dark modes.
///
/// Supports multiple accent palettes that the user can cycle through
/// in the header toolbar.
enum Theme {

    // MARK: - Palettes

    /// A named set of accent colors.
    struct Palette: Equatable {
        let name: String
        let idea: Color
        let taskDone: Color
        let event: Color
        let priority: Color
    }

    static let palettes: [Palette] = [
        Palette(
            name: "default",
            idea:     Color(red: 0.95, green: 0.75, blue: 0.30),  // warm amber
            taskDone: Color(red: 0.30, green: 0.78, blue: 0.60),  // muted teal
            event:    Color(red: 0.40, green: 0.55, blue: 0.90),  // slate blue
            priority: Color(red: 0.90, green: 0.40, blue: 0.40)   // muted coral
        ),
        Palette(
            name: "ocean",
            idea:     Color(red: 0.40, green: 0.82, blue: 0.85),  // cyan
            taskDone: Color(red: 0.35, green: 0.70, blue: 0.55),  // sea green
            event:    Color(red: 0.30, green: 0.50, blue: 0.80),  // deep blue
            priority: Color(red: 0.85, green: 0.50, blue: 0.35)   // burnt orange
        ),
        Palette(
            name: "rose",
            idea:     Color(red: 0.95, green: 0.65, blue: 0.55),  // peach
            taskDone: Color(red: 0.55, green: 0.78, blue: 0.50),  // sage
            event:    Color(red: 0.70, green: 0.45, blue: 0.75),  // lavender
            priority: Color(red: 0.90, green: 0.35, blue: 0.45)   // rose red
        ),
        Palette(
            name: "mono",
            idea:     Color(white: 0.70),                         // light grey
            taskDone: Color(white: 0.55),                         // mid grey
            event:    Color(white: 0.60),                         // grey
            priority: Color(white: 0.45)                          // dark grey
        ),
    ]

    /// Cached palette — avoids hitting UserDefaults on every color access.
    @MainActor
    private static var _cachedPalette: Palette = {
        let idx = UserDefaults.standard.integer(forKey: "accentPalette")
        let safeIdx = idx < palettes.count ? idx : 0
        return palettes[safeIdx]
    }()

    @MainActor
    static var currentPalette: Palette { _cachedPalette }

    @MainActor
    static func cyclePalette() {
        let current = UserDefaults.standard.integer(forKey: "accentPalette")
        let next = (current + 1) % palettes.count
        UserDefaults.standard.set(next, forKey: "accentPalette")
        let safeIdx = next < palettes.count ? next : 0
        _cachedPalette = palettes[safeIdx]
    }

    // MARK: - Accent colors (palette-aware)

    /// Idea glyph — warm amber (default palette).
    @MainActor static var idea: Color { currentPalette.idea }

    /// Task done — muted teal-green (default palette).
    @MainActor static var taskDone: Color { currentPalette.taskDone }

    /// Event / migrated — softer slate-blue (default palette).
    @MainActor static var event: Color { currentPalette.event }

    /// Priority bar — muted coral (default palette).
    @MainActor static var priority: Color { currentPalette.priority }

    // MARK: - Backgrounds

    static func background(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.08, green: 0.08, blue: 0.09)
            : Color(red: 0.98, green: 0.98, blue: 0.99)
    }

    static func background(for scheme: ColorScheme) -> Color {
        background(isDark: scheme == .dark)
    }

    static func surface(isDark: Bool) -> Color {
        isDark
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        surface(isDark: scheme == .dark)
    }

    // MARK: - Button style

    /// A subtle button style that scales down on press and shows a faint
    /// hover background. Used for header toolbar icons.
    struct SubtleButton: ButtonStyle {
        @State private var isHovering = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
                )
                .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }

    // MARK: - Center-fade divider

    /// Gradient divider that fades from transparent → subtle → transparent.
    /// Used for header/input separators and day separator lines.
    static var fadeDivider: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, Color.secondary.opacity(0.2), .clear],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 0.5)
    }
}

// MARK: - Shared empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.event.opacity(0.3))
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
