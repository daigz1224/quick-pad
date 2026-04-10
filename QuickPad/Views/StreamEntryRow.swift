import SwiftUI

/// One stream entry: fixed-width glyph column, content, optional time.
/// Opacity / gravity decay is Phase 2 in the architecture doc; rows here
/// render at full opacity.
struct StreamEntryRow: View {
    let entry: StreamEntry
    /// Non-empty while the user is in search mode. Matching substrings
    /// inside `content` are highlighted with a yellow accent.
    var highlightQuery: String = ""
    /// Called when the user edits content via context menu → Edit.
    var onEdit: ((StreamEntry, String) -> Void)?
    /// Called when the user soft-deletes via context menu → Delete.
    var onDelete: ((StreamEntry) -> Void)?

    @State private var isEditing: Bool = false
    @State private var editDraft: String = ""
    @FocusState private var isEditFocused: Bool

    // Fonts are defined once so content / glyph / time / tag all stay
    // locked to the same baseline. Sizes chosen so Chinese + Latin mix
    // stays readable in a 420-wide popover without wrapping too aggressively.
    private static let contentFont = Font.system(size: 12, design: .monospaced)
    private static let timeFont = Font.system(size: 10, design: .monospaced)
    private static let tagFont = Font.system(size: 9, design: .monospaced)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.displayGlyph)
                .font(Self.contentFont)
                .tracking(-0.3)
                .foregroundStyle(glyphColor)
                .frame(width: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                if isEditing {
                    editField
                } else {
                    contentLine
                }
                if let tag = entry.prefixTag {
                    Text(tag)
                        .font(Self.tagFont)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            if let time = timeLabel {
                Text(time)
                    .font(Self.timeFont)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .overlay(alignment: .leading) {
            if entry.isPriority {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: -8)
            }
        }
        .contextMenu {
            if entry.bulletType != .unknown {
                Button {
                    beginEditing()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete?(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Inline edit

    private var editField: some View {
        HStack(spacing: 4) {
            TextField("content", text: $editDraft)
                .textFieldStyle(.plain)
                .font(Self.contentFont)
                .tracking(-0.3)
                .focused($isEditFocused)
                .onSubmit(commitEdit)
                .onExitCommand(perform: cancelEdit)
            Button {
                commitEdit()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            Button {
                cancelEdit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    private func beginEditing() {
        editDraft = entry.content
        isEditing = true
        // Slight delay so the TextField is in the view tree before we
        // try to grab focus.
        DispatchQueue.main.async {
            isEditFocused = true
        }
    }

    private func commitEdit() {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.content else {
            cancelEdit()
            return
        }
        onEdit?(entry, trimmed)
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
        editDraft = ""
    }

    // MARK: - Display

    private var contentLine: some View {
        let body = entry.content.isEmpty ? entry.rawLine : entry.content
        return Self.highlighted(body, query: highlightQuery)
            .font(Self.contentFont)
            .tracking(-0.3)
            .foregroundStyle(.primary)
            .lineSpacing(1)
            .strikethrough(entry.taskState == .cancelled)
    }

    /// Split `text` on every case-insensitive occurrence of `query`
    /// and return a `Text` that styles the matches. SwiftUI's `Text`
    /// concatenation keeps per-segment styling (inner wins over outer
    /// view modifiers) which is exactly what we need.
    private static func highlighted(_ text: String, query: String) -> Text {
        guard !query.isEmpty else { return Text(text) }

        var result = Text("")
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let range = text.range(of: query, options: .caseInsensitive, range: cursor..<text.endIndex) {
            if range.lowerBound > cursor {
                result = result + Text(String(text[cursor..<range.lowerBound]))
            }
            // Use `.bold()` alongside the yellow to ensure the hit is
            // visible even in the rare case where the user's system
            // accent happens to clash with pure yellow.
            result = result + Text(String(text[range]))
                .foregroundStyle(Color.yellow)
                .bold()
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result = result + Text(String(text[cursor..<text.endIndex]))
        }
        return result
    }

    private var glyphColor: Color {
        switch entry.bulletType {
        case .idea: return .yellow
        case .task:
            switch entry.taskState {
            case .done: return .green
            case .cancelled: return .secondary
            case .migrated: return .blue
            default: return .primary
            }
        case .event: return .blue
        case .note: return .primary
        case .unknown: return .secondary
        }
    }

    private var timeLabel: String? {
        guard let timestamp = entry.timestamp else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }
}
