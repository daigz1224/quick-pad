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
        HStack(spacing: 6) {
            ForEach(Self.bulletTypes, id: \.self) { type in
                bulletChip(type)
            }
            Text("·")
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.textTertiary(for: colorScheme))
                .padding(.horizontal, 2)
            ForEach(Self.prefixes, id: \.value) { entry in
                prefixChip(label: entry.label, value: entry.value, help: entry.help)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(theme.surface(for: colorScheme).opacity(0.6))
        .overlay(alignment: .bottom) {
            ThemeFadeDivider()
        }
    }

    @ViewBuilder
    private func bulletChip(_ type: BulletType) -> some View {
        let isActive = model.bulletType == type
        Button {
            model.setBullet(type)
        } label: {
            HStack(spacing: 3) {
                Text(type.glyph)
                    .foregroundStyle(type.glyphColor(theme: theme, scheme: colorScheme))
                Text(type.label)
                    .foregroundStyle(
                        isActive
                            ? theme.textPrimary(for: colorScheme)
                            : theme.textSecondary(for: colorScheme)
                    )
            }
            .font(theme.monoFont(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isActive ? theme.accent.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? theme.accent.opacity(0.4) : theme.textTertiary(for: colorScheme).opacity(0.25),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .help("\(type.label) — click to set type")
    }

    @ViewBuilder
    private func prefixChip(label: String, value: String, help: String) -> some View {
        Button {
            model.prependPrefix(value)
        } label: {
            Text(label)
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.textSecondary(for: colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            theme.textTertiary(for: colorScheme).opacity(0.25),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
