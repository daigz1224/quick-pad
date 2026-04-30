import SwiftUI

/// Single-line input row that lives between the header and the stream.
/// State (bullet type + draft text) is owned by `InputBarModel` so the
/// HintBar underneath can mutate the same fields without any coupling.
struct InputBar: View {
    @Environment(StreamViewModel.self) private var viewModel
    @Environment(ThemeManager.self) private var theme
    @Environment(InputBarModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    @State private var bulletBounce: Bool = false
    @FocusState private var isFocused: Bool

    private var font: Font { theme.uiFont(size: 12) }

    var body: some View {
        @Bindable var model = model

        HStack(alignment: .center, spacing: 8) {
            bulletButton

            TextField(model.bulletType.placeholder, text: $model.draft)
                .textFieldStyle(.plain)
                .font(font)
                .tracking(theme.contentTracking)
                .focused($isFocused)
                .onSubmit(submit)
                .submitLabel(.send)
                // The popover has one logical input target, so Tab has
                // no useful focus target — repurpose to cycle bullet
                // type. Shift-Tab is left alone as an escape hatch.
                .onKeyPress(.tab) {
                    cycleBulletWithBounce()
                    return .handled
                }
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
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private var bulletButton: some View {
        Button {
            cycleBulletWithBounce()
        } label: {
            Text(model.bulletType.glyph)
                .font(font)
                .tracking(theme.contentTracking)
                .foregroundStyle(model.bulletType.glyphColor(theme: theme, scheme: colorScheme))
                .frame(width: 18, height: 18)
                .scaleEffect(bulletBounce ? 1.25 : 1.0)
                .rotationEffect(.degrees(bulletBounce ? -15 : 0))
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bulletBounce)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(model.bulletType.label) — click to cycle")
    }

    private func cycleBulletWithBounce() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            model.cycleBullet()
            bulletBounce = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            bulletBounce = false
        }
    }

    private func submit() {
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.append(bulletType: model.bulletType, content: text)
        model.clearDraft()
        // Stay focused so the user can chain entries without touching
        // the mouse. Keep the current bullet type — if they were in a
        // "task" streak they probably want to keep logging tasks.
        isFocused = true
    }
}
