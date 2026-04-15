import SwiftUI

/// Compact row of clickable chips beneath the InputBar:
///   `[— note] [☐ task] [? question] [! idea] · [r:] [w:] [l:] [*]`
///
/// Bullet chips set the active bullet type. Prefix chips prepend the
/// corresponding token into the draft (no-op if it's already there).
/// Toggleable via `View › Show Hint Bar` (persisted in @AppStorage)
/// for users who've internalised the cycle and want the screen back.
struct HintBar: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(InputBarModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private static let bulletTypes: [BulletType] = [.note, .task, .question, .idea]

    private static let prefixes: [(label: String, value: String, help: String)] = [
        ("r:", "read: ", "tag as read"),
        ("w:", "watch: ", "tag as watch"),
        ("l:", "listen: ", "tag as listen"),
        ("*", "* ", "mark priority")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.bulletTypes, id: \.self) { type in
                bulletChip(type)
            }
            divider
            ForEach(Self.prefixes, id: \.value) { entry in
                prefixChip(label: entry.label, value: entry.value, help: entry.help)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(theme.surface(for: colorScheme).opacity(0.4))
        .overlay(alignment: .bottom) {
            ThemeFadeDivider()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.textTertiary(for: colorScheme).opacity(0.2))
            .frame(width: 0.5, height: 9)
            .padding(.horizontal, 4)
    }

    /// Bullet chips: only the active one carries a container. Inactive
    /// chips are plain text so they read as "quick-select choices" not
    /// "eight buttons demanding attention."
    @ViewBuilder
    private func bulletChip(_ type: BulletType) -> some View {
        let isActive = model.bulletType == type
        Button {
            model.setBullet(type)
        } label: {
            HStack(spacing: 4) {
                Text(type.glyph)
                    .foregroundStyle(
                        isActive
                            ? type.glyphColor(theme: theme, scheme: colorScheme)
                            : type.glyphColor(theme: theme, scheme: colorScheme).opacity(0.6)
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
                    .fill(isActive ? theme.accent.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help("\(type.label) — click to set type")
    }

    /// Prefix chips: borderless, letter-style. They insert a token,
    /// they're not persistent state, so they shouldn't wear a button
    /// outline.
    @ViewBuilder
    private func prefixChip(label: String, value: String, help: String) -> some View {
        Button {
            model.prependPrefix(value)
        } label: {
            Text(label)
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.textTertiary(for: colorScheme))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
