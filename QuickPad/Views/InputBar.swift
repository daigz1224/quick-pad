import SwiftUI

/// Single-line input row that lives between the header and the stream.
/// Users pick a bullet type by clicking the glyph (or cycle with Tab),
/// type the body, hit Enter to append.
///
/// Intentionally dumb: the bar owns only the draft text and the current
/// bullet selection. All disk writes go through `StreamViewModel.append`.
struct InputBar: View {
    @Environment(StreamViewModel.self) private var viewModel

    @State private var draft: String = ""
    @State private var bulletType: BulletType = .note
    @FocusState private var isFocused: Bool

    private static let font = Font.system(size: 12, design: .monospaced)

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            bulletButton

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(Self.font)
                .tracking(-0.3)
                .focused($isFocused)
                .onSubmit(submit)
                .submitLabel(.send)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(alignment: .bottom) {
            // Hairline under the input to mirror the divider above the
            // stream body, so the input feels like its own band.
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
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
            bulletType = bulletType.next
        } label: {
            Text(bulletType.glyph)
                .font(Self.font)
                .tracking(-0.3)
                .foregroundStyle(glyphColor)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(bulletType.label) — click to cycle")
    }

    private var glyphColor: Color {
        switch bulletType {
        case .idea: return .yellow
        case .task: return .primary
        case .event: return .blue
        case .note: return .primary
        case .unknown: return .secondary
        }
    }

    private var placeholder: String {
        switch bulletType {
        case .note: return "note — what's on your mind?"
        case .task: return "task — what needs doing?"
        case .event: return "event — what happened?"
        case .idea: return "idea — capture the spark"
        case .unknown: return "…"
        }
    }

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
