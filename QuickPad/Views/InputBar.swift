import SwiftUI

/// Single-line input row that lives between the header and the stream.
/// Users pick a bullet type by clicking the glyph (or cycle with Tab),
/// type the body, hit Enter to append.
///
/// Intentionally dumb: the bar owns only the draft text and the current
/// bullet selection. All disk writes go through `StreamViewModel.append`.
struct InputBar: View {
    @Environment(StreamViewModel.self) private var viewModel
    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: String = ""
    @State private var bulletType: BulletType = .note
    @State private var bulletBounce: Bool = false
    @FocusState private var isFocused: Bool

    private var font: Font { theme.uiFont(size: 12) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            bulletButton

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .tracking(theme.contentTracking)
                .focused($isFocused)
                .onSubmit(submit)
                .submitLabel(.send)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface(for: colorScheme))
        .overlay(alignment: .bottom) {
            // Focus accent line — visible when typing.
            Rectangle()
                .fill(isFocused ? theme.accent.opacity(0.3) : Color.secondary.opacity(0.1))
                .frame(height: isFocused ? 1.5 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        .onAppear {
            // Slight delay so the popover finishes becoming key before
            // we grab focus — otherwise the first keystroke can get
            // swallowed by the hosting window.
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private var bulletButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                bulletType = bulletType.next
                bulletBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                bulletBounce = false
            }
        } label: {
            Text(bulletType.glyph)
                .font(font)
                .tracking(theme.contentTracking)
                .foregroundStyle(bulletType.glyphColor(theme: theme, scheme: colorScheme))
                .frame(width: 18, height: 18)
                .scaleEffect(bulletBounce ? 1.25 : 1.0)
                .rotationEffect(.degrees(bulletBounce ? -15 : 0))
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bulletBounce)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(bulletType.label) — click to cycle")
    }

    private var placeholder: String { bulletType.placeholder }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.append(bulletType: bulletType, content: text)
        draft = ""
        // Stay focused so the user can chain entries without touching
        // the mouse. Keep the current bullet type — if they were in a
        // "task" streak they probably want to keep logging tasks.
        isFocused = true
    }
}
