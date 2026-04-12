import SwiftUI

/// Translucent overlay showing all available keyboard shortcuts.
/// Triggered by ⌘/ and dismissed by any key or click.
struct ShortcutHintsView: View {
    var onDismiss: () -> Void

    private static let sections: [(title: String, shortcuts: [(key: String, label: String)])] = [
        ("Navigation", [
            ("⌥N", "Toggle popover"),
            ("⌥⇧N", "Quick Append panel"),
            ("⌘D", "Detach / reattach"),
        ]),
        ("Input", [
            ("Tab", "Cycle bullet type"),
            ("Enter", "Append entry"),
            ("Esc", "Cancel / dismiss"),
        ]),
        ("Actions", [
            ("⌘F", "Search stream"),
            ("⌘Z", "Undo delete / rescue"),
            ("⌘E", "Export visible entries"),
        ]),
        ("Filters", [
            ("⌘1", "Notes only"),
            ("⌘2", "Tasks only"),
            ("⌘3", "Events only"),
            ("⌘4", "Ideas only"),
            ("⌘5", "Clear filter"),
        ]),
        ("Hints", [
            ("⌘/", "Toggle this panel"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                Text("⌘/ to dismiss")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ForEach(Self.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)

                    ForEach(section.shortcuts, id: \.key) { shortcut in
                        HStack(spacing: 0) {
                            Text(shortcut.key)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.event)
                                .frame(width: 52, alignment: .leading)
                            Text(shortcut.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onExitCommand { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
    }
}
