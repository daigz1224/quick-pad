import SwiftUI

/// Mini single-line input that lives inside `QuickCapturePanel`.
/// Designed to disappear after Enter — no header, no stream, no
/// shortcut bar. Just: pick type, type, hit Enter.
struct QuickCaptureView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// Called with the trimmed content + bullet type when the user
    /// hits Enter on a non-empty draft. The panel handles dismissal.
    let onSubmit: (BulletType, String) -> Void
    /// Called when the user explicitly cancels (Esc / blur).
    let onCancel: () -> Void

    @State private var draft: String = ""
    @State private var bulletType: BulletType = .note
    @FocusState private var isFocused: Bool

    private var font: Font { theme.uiFont(size: 14) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            bulletButton

            TextField(bulletType.placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .tracking(theme.contentTracking)
                .focused($isFocused)
                .onSubmit(submit)
                .submitLabel(.send)

            // Tiny hint so first-time users know Enter sends.
            Text("⏎")
                .font(theme.monoFont(size: 10))
                .foregroundStyle(theme.textTertiary(for: colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.22), lineWidth: 0.75)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
        .onKeyPress(.tab) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                bulletType = bulletType.next
            }
            return .handled
        }
    }

    private var bulletButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                bulletType = bulletType.next
            }
        } label: {
            Text(bulletType.glyph)
                .font(font)
                .tracking(theme.contentTracking)
                .foregroundStyle(bulletType.glyphColor(theme: theme, scheme: colorScheme))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(bulletType.label) — Tab to cycle")
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            onCancel()
            return
        }
        onSubmit(bulletType, text)
    }
}
