import SwiftUI

/// One stream entry: fixed-width glyph column, content, optional time.
/// Opacity decays with age via the gravity system (Phase 2).
struct StreamEntryRow: View {
    let entry: StreamEntry
    /// Non-empty while the user is in search mode. Matching substrings
    /// inside `content` are highlighted with a yellow accent.
    var highlightQuery: String = ""
    /// Called when the user edits content via context menu → Edit.
    var onEdit: ((StreamEntry, String) -> Void)?
    /// Called when the user soft-deletes via context menu → Delete.
    var onDelete: ((StreamEntry) -> Void)?
    /// Called when the user clicks an old entry to rescue it to today.
    var onRescue: ((StreamEntry) -> Void)?
    /// Called when the user toggles a task's state.
    var onTaskStateChange: ((StreamEntry, TaskState) -> Void)?

    @State private var isEditing: Bool = false
    @State private var editDraft: String = ""
    @State private var isHovering: Bool = false
    @FocusState private var isEditFocused: Bool

    // Fonts are defined once so content / glyph / time / tag all stay
    // locked to the same baseline. Sizes chosen so Chinese + Latin mix
    // stays readable in a 420-wide popover without wrapping too aggressively.
    private static let contentFont = Font.system(size: 11)
    private static let timeFont = Font.system(size: 10, design: .monospaced)
    private static let tagFont = Font.system(size: 9, design: .monospaced)

    /// Whether this entry is old enough to show the "click to rescue" hint.
    private var isRescuable: Bool {
        entry.ageInDays >= 1 && entry.bulletType != .unknown
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            glyphView

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

            trailingLabel
                .frame(width: 46, alignment: .trailing)
        }
        .overlay(alignment: .leading) {
            if entry.isPriority {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: -8)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if isRescuable {
                onRescue?(entry)
            }
        }
        .opacity(entry.gravityOpacity)
        .contextMenu {
            if entry.bulletType != .unknown {
                Button {
                    beginEditing()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                // Task state submenu
                if entry.bulletType == .task {
                    Divider()
                    taskStateMenu
                }

                // Rescue option for old entries
                if isRescuable {
                    Divider()
                    Button {
                        onRescue?(entry)
                    } label: {
                        Label("Rescue to Today", systemImage: "arrow.up.to.line")
                    }
                }

                Divider()
                Button(role: .destructive) {
                    onDelete?(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Task state menu

    @ViewBuilder
    private var taskStateMenu: some View {
        let current = entry.taskState ?? .pending

        if current != .done {
            Button {
                onTaskStateChange?(entry, .done)
            } label: {
                Label("Mark Done", systemImage: "checkmark")
            }
        }
        if current != .pending {
            Button {
                onTaskStateChange?(entry, .pending)
            } label: {
                Label("Mark Pending", systemImage: "circle")
            }
        }
        if current != .migrated {
            Button {
                onTaskStateChange?(entry, .migrated)
            } label: {
                Label("Mark Migrated", systemImage: "arrow.right")
            }
        }
        if current != .cancelled {
            Button {
                onTaskStateChange?(entry, .cancelled)
            } label: {
                Label("Mark Cancelled", systemImage: "xmark")
            }
        }
    }

    // MARK: - Inline edit

    private var editField: some View {
        HStack(spacing: 4) {
            TextField("content", text: $editDraft)
                .textFieldStyle(.plain)
                .font(Self.contentFont)
                .tracking(-0.15)
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

    private var glyphView: some View {
        Group {
            if entry.bulletType == .task {
                // Clickable glyph for tasks: cycles pending → done.
                Button {
                    let next: TaskState = (entry.taskState == .done) ? .pending : .done
                    onTaskStateChange?(entry, next)
                } label: {
                    Text(entry.displayGlyph)
                        .font(Self.contentFont)
                        .tracking(-0.15)
                        .foregroundStyle(glyphColor)
                        .frame(width: 12, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(entry.displayGlyph)
                    .font(Self.contentFont)
                    .tracking(-0.15)
                    .foregroundStyle(glyphColor)
                    .frame(width: 12, alignment: .leading)
            }
        }
    }

    private var contentLine: some View {
        let body = entry.content.isEmpty ? entry.rawLine : entry.content
        return InlineMarkdown.render(body, query: highlightQuery)
            .font(Self.contentFont)
            .tracking(-0.15)
            .foregroundStyle(.primary)
            .lineSpacing(1)
            .strikethrough(entry.taskState == .cancelled)
    }

    @ViewBuilder
    private var trailingLabel: some View {
        if isHovering && isRescuable {
            Text("↑ rescue")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.7))
                .fixedSize()
        } else if let time = timeLabel {
            Text(time)
                .font(Self.timeFont)
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
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

    /// Cached formatter for short time labels ("3pm"). Created once to
    /// avoid allocating on every SwiftUI body evaluation.
    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "ha"
        return f
    }()

    private var timeLabel: String? {
        guard let timestamp = entry.timestamp else { return nil }
        // Gravity-aware time labels from architecture doc:
        // Today: relative ("now" / "2m" / "3h")
        // 1-3 days: "11pm" / "3pm"
        // 4+ days: omitted
        let days = entry.ageInDays

        if days == 0 {
            let seconds = Int(Date().timeIntervalSince(timestamp))
            if seconds < 60 { return "now" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes)m" }
            let hours = minutes / 60
            return "\(hours)h"
        } else if days <= 3 {
            return Self.shortTimeFormatter.string(from: timestamp).lowercased()
        }
        // 4+ days: omit timestamp per gravity decay spec.
        return nil
    }
}
