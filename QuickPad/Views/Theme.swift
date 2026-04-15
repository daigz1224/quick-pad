import SwiftUI

/// View primitives that don't depend on the theme. Colors, fonts, and
/// density tokens live in `ThemeManager` (see `ThemePreset.swift` —
/// kept under that filename for git history).
enum Theme {

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
}

// MARK: - Shared empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let hint: String

    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(theme.accent.opacity(0.3))
            Text(title)
                .font(theme.uiFont(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary(for: scheme))
            Text(hint)
                .font(theme.monoFont(size: 10))
                .foregroundStyle(theme.textTertiary(for: scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
