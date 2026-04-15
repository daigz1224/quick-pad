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
    /// Called when the user changes the bullet type via context menu.
    var onBulletTypeChange: ((StreamEntry, BulletType) -> Void)?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var isEditing: Bool = false
    @State private var editDraft: String = ""
    @State private var isHovering: Bool = false
    @State private var justToggled: Bool = false
    @FocusState private var isEditFocused: Bool

    // Sizes chosen so Chinese + Latin mix stays readable in a 420-wide
    // popover without wrapping too aggressively.
    private static let contentSize: CGFloat = 11

    private var contentFont: Font { theme.contentFont(size: Self.contentSize) }
    private var timeFont: Font    { theme.monoFont(size: 10) }
    private var tagFont: Font     { theme.monoFont(size: 9) }
    private var contentTracking: CGFloat { theme.contentTracking }

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
                        .font(tagFont)
                        .foregroundStyle(theme.textSecondary(for: colorScheme))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.textSecondary(for: colorScheme).opacity(0.12), in: Capsule())
                }
            }

            Spacer(minLength: 6)

            trailingLabel
                .frame(width: 38, alignment: .trailing)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .overlay(alignment: .leading) {
            if entry.isPriority {
                Capsule()
                    .fill(theme.priority)
                    .frame(width: 2)
                    .padding(.vertical, 2)
                    .offset(x: -6)
            }
        }
        .padding(.vertical, theme.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(isHovering ? theme.hover(for: colorScheme) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
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

                // Bullet type submenu
                Divider()
                bulletTypeMenu

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

    // MARK: - Bullet type menu

    @ViewBuilder
    private var bulletTypeMenu: some View {
        Menu {
            ForEach([BulletType.note, .task, .question, .idea], id: \.self) { type in
                Button {
                    onBulletTypeChange?(entry, type)
                } label: {
                    HStack {
                        Text("\(type.glyph) \(type.label)")
                        if type == entry.bulletType {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(type == entry.bulletType)
            }
        } label: {
            Label("Type: \(entry.bulletType.label)", systemImage: "arrow.triangle.swap")
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
                .font(contentFont)
                .tracking(contentTracking)
                .focused($isEditFocused)
                .onSubmit(commitEdit)
                .onExitCommand(perform: cancelEdit)
            Button {
                commitEdit()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.taskDone)
            }
            .buttonStyle(.plain)
            Button {
                cancelEdit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary(for: colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(theme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 4))
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

    private var glyphColor: Color {
        entry.bulletType.glyphColor(theme: theme, scheme: colorScheme, taskState: entry.taskState)
    }

    private var glyphView: some View {
        Group {
            if entry.bulletType == .task {
                Button {
                    let next: TaskState = (entry.taskState == .done) ? .pending : .done
                    onTaskStateChange?(entry, next)
                    justToggled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        justToggled = false
                    }
                } label: {
                    Text(entry.displayGlyph)
                        .font(contentFont)
                        .tracking(contentTracking)
                        .foregroundStyle(glyphColor)
                        .lineLimit(1)
                        .frame(width: 12, alignment: .leading)
                        .scaleEffect(justToggled ? 1.2 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: justToggled)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(entry.displayGlyph)
                    .font(contentFont)
                    .tracking(contentTracking)
                    .foregroundStyle(glyphColor)
                    .lineLimit(1)
                    .frame(width: 12, alignment: .leading)
            }
        }
    }

    private var contentLine: some View {
        let body = entry.content.isEmpty ? entry.rawLine : entry.content
        let shouldItalic = theme.ideaItalic && entry.bulletType == .idea
        return InlineMarkdown.render(
            body,
            theme: theme,
            scheme: colorScheme,
            contentSize: Self.contentSize,
            query: highlightQuery
        )
            .font(contentFont)
            .tracking(contentTracking)
            .italic(shouldItalic)
            .foregroundStyle(theme.textPrimary(for: colorScheme))
            .lineSpacing(theme.lineSpacing)
            .strikethrough(entry.taskState == .cancelled)
    }

    @ViewBuilder
    private var trailingLabel: some View {
        if isHovering && isRescuable {
            Text("↑ rescue")
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.accent.opacity(0.7))
                .fixedSize()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
        } else if let time = timeLabel {
            Text(time)
                .font(timeFont)
                .foregroundStyle(theme.timestampColor(for: colorScheme))
                .fixedSize()
                .transition(.opacity)
        }
    }

    /// Cached formatter for absolute 24h time labels ("15:42"). Created
    /// once to avoid allocating on every SwiftUI body evaluation.
    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeLabel: String? {
        guard let timestamp = entry.timestamp else { return nil }
        // Unified 24h absolute time across all ages — the day separator
        // above each section already carries the date, so "15:42" is
        // enough context on its own.
        return Self.shortTimeFormatter.string(from: timestamp)
    }
}
