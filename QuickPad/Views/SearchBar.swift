import SwiftUI

/// Compact search field that takes over the `InputBar` slot when the
/// user hits ⌘F. Intentionally mirrors `InputBar`'s layout (same
/// height, same horizontal padding, same monospaced font) so toggling
/// between the two modes doesn't visually shift anything below it.
struct SearchBar: View {
    @Binding var query: String
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    private static let font = Font.system(size: 12, design: .monospaced)

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            TextField("search stream", text: $query)
                .textFieldStyle(.plain)
                .font(Self.font)
                .tracking(-0.3)
                .focused($isFocused)
                // Escape closes search mode (SwiftUI intercepts this
                // before NSPopover's transient auto-close sees it, so
                // the popover stays open — exactly what we want).
                .onExitCommand(perform: onDismiss)

            if !query.isEmpty {
                Button {
                    query = ""
                    // Keep focus in the field so the user can type a
                    // fresh query without grabbing the mouse.
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface(for: colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFocused ? Theme.event.opacity(0.3) : Color.secondary.opacity(0.1))
                .frame(height: isFocused ? 1.5 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .onAppear {
            // Delay matches InputBar's pattern — gives the popover a
            // tick to finish becoming key before we grab first-responder
            // status, otherwise the first keystroke can get dropped.
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
