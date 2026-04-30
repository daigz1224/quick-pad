import SwiftUI

/// One filter chip per bullet type plus a clear button when a filter
/// is active. Driven by a `@Binding` so this and the ⌘1-4 / ⌘5
/// shortcuts in `PopoverRootView` share a single source of truth.
struct HintBar: View {
    @Binding var typeFilter: BulletType?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private static let bulletTypes: [BulletType] = [.note, .task, .question, .idea]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.bulletTypes, id: \.self) { type in
                filterChip(type)
            }
            Spacer()
            if typeFilter != nil {
                clearButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(theme.surface(for: colorScheme).opacity(0.4))
        .overlay(alignment: .bottom) { ThemeFadeDivider() }
        .animation(.easeInOut(duration: 0.15), value: typeFilter)
    }

    @ViewBuilder
    private func filterChip(_ type: BulletType) -> some View {
        let isActive = typeFilter == type
        Button {
            typeFilter = isActive ? nil : type
        } label: {
            HStack(spacing: 4) {
                Text(type.glyph)
                    .foregroundStyle(
                        isActive
                            ? type.glyphColor(theme: theme, scheme: colorScheme)
                            : type.glyphColor(theme: theme, scheme: colorScheme).opacity(0.5)
                    )
                Text(type.label)
                    .foregroundStyle(
                        isActive
                            ? theme.textPrimary(for: colorScheme)
                            : theme.textTertiary(for: colorScheme)
                    )
            }
            .font(theme.monoFont(size: 9, weight: isActive ? .medium : .regular))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isActive ? theme.accent.opacity(0.18) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? theme.accent.opacity(0.40) : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .help(isActive
              ? "Showing only \(type.label) — click to clear"
              : "Show only \(type.label) (\(Self.shortcut(for: type)))")
    }

    private var clearButton: some View {
        Button {
            typeFilter = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                Text("⌘5")
                    .font(theme.monoFont(size: 9))
            }
            .foregroundStyle(theme.accent.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .help("Clear filter (⌘5)")
        .transition(.opacity)
    }

    private static func shortcut(for type: BulletType) -> String {
        switch type {
        case .note:     return "⌘1"
        case .task:     return "⌘2"
        case .question: return "⌘3"
        case .idea:     return "⌘4"
        case .unknown:  return ""
        }
    }
}
