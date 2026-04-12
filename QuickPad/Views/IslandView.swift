import SwiftUI

/// The "Dynamic Island" mini floating widget.
///
/// All shape/size animation is driven by `@State` + SwiftUI springs.
/// The hosting NSPanel has a fixed frame — it never resizes.
struct IslandView: View {
    @Environment(StreamViewModel.self) private var viewModel
    @State private var isExpanded: Bool = false
    var onExpandChange: (Bool) -> Void = { _ in }
    var onDismiss: () -> Void
    var notchHeight: CGFloat = 0

    @State private var draft: String = ""
    @State private var bulletType: BulletType = .note
    @FocusState private var isInputFocused: Bool

    /// Toast message (delete / rescue feedback).
    @State private var toastMessage: String? = nil
    @State private var toastTimer: Timer? = nil

    /// Bounce animation: temporary width offset.
    @State private var bounceOffset: CGFloat = 0

    // MARK: - Springs (from claude-island)

    private static let openSpring  = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private static let closeSpring = Animation.spring(response: 0.45, dampingFraction: 1.0)
    private static let bounceSpring = Animation.spring(response: 0.3, dampingFraction: 0.5)

    // MARK: - Animated geometry

    private var pillWidth: CGFloat {
        (isExpanded ? IslandPanel.expandedWidth : IslandPanel.compactWidth) + bounceOffset
    }

    private var pillHeight: CGFloat {
        isExpanded ? IslandPanel.expandedHeight : IslandPanel.compactHeight
    }

    private var bottomRadius: CGFloat {
        isExpanded ? 22 : 16
    }

    // MARK: - Data

    /// Only today's entries — the Island is a "now" view.
    private var recentEntries: [StreamEntry] {
        let todaySections = viewModel.sections.filter { section in
            guard let date = section.date else { return false }
            return Calendar.current.isDateInToday(date)
        }
        return todaySections.flatMap { $0.entries }.filter { !$0.isDeleted }
    }

    private var latestSummary: String {
        guard let first = recentEntries.first else { return "QuickPad" }
        let text = first.content
        return text.count > 28 ? String(text.prefix(28)) + "…" : text
    }

    private var totalEntryCount: Int {
        recentEntries.count
    }

    // MARK: - Fonts

    private static let contentFont = Font.system(size: 11)
    private static let inputFont   = Font.system(size: 12, design: .monospaced)
    private static let headerFont  = Font.system(size: 12, weight: .medium, design: .monospaced)
    private static let timeFont    = Font.system(size: 10, design: .monospaced)

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Black strip merging with the notch (hidden behind menubar).
            Color.black
                .frame(width: pillWidth, height: notchHeight)

            // Pill content.
            ZStack(alignment: .top) {
                if isExpanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85, anchor: .top)
                                .combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    compactContent
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        ))
                }
            }
            .frame(width: pillWidth, height: pillHeight)
            .clipped()
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: bottomRadius,
                bottomTrailingRadius: bottomRadius,
                topTrailingRadius: 0
            )
            .fill(.black)
            .shadow(color: .black.opacity(isExpanded ? 0.35 : 0.2), radius: isExpanded ? 12 : 6, y: 4)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: bottomRadius,
                bottomTrailingRadius: bottomRadius,
                topTrailingRadius: 0
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // — Notifications from IslandPanel —
        .onReceive(NotificationCenter.default.publisher(for: IslandPanel.collapseNotification)) { _ in
            guard isExpanded else { return }
            isInputFocused = false
            withAnimation(Self.closeSpring) { isExpanded = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: IslandPanel.expandNotification)) { _ in
            guard !isExpanded else { return }
            withAnimation(Self.openSpring) { isExpanded = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: IslandPanel.bounceNotification)) { _ in
            performBounce()
        }
        .onExitCommand { collapse() }
        .onChange(of: totalEntryCount) { old, new in
            // Bounce when new entries appear while compact.
            if new > old && !isExpanded {
                performBounce()
            }
        }
    }

    // MARK: - Compact

    private var compactContent: some View {
        Button { expand() } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.dash")
                    .foregroundStyle(.white.opacity(0.5))
                Text(latestSummary)
                    .font(Self.contentFont)
                    .tracking(-0.15)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "list.dash")
                    .foregroundStyle(.white.opacity(0.5))
                Text("QuickPad")
                    .font(Self.headerFont)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button { collapse() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color.white.opacity(0.1))

            // Input bar
            HStack(alignment: .center, spacing: 8) {
                Button { cycleBullet() } label: {
                    Text(bulletType.glyph)
                        .font(Self.inputFont)
                        .tracking(-0.3)
                        .foregroundStyle(glyphColor)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(Self.inputFont)
                    .tracking(-0.3)
                    .foregroundStyle(.white)
                    .focused($isInputFocused)
                    .onSubmit(appendEntry)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }

            // Entries
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(recentEntries) { entry in
                            entryRow(entry)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let msg = toastMessage {
                    Text(msg)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 4)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: toastMessage != nil)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isInputFocused = true
            }
        }
    }

    // MARK: - Entry row

    private func entryRow(_ entry: StreamEntry) -> some View {
        IslandEntryRow(
            entry: entry,
            onEdit: { entry, newContent in
                viewModel.editEntry(entry, newContent: newContent)
            },
            onDelete: { entry in
                viewModel.deleteEntry(entry)
                showToast("deleted")
            },
            onRescue: { entry in
                viewModel.rescueEntry(entry)
                showToast("rescued ↑")
            },
            onTaskStateChange: { entry, newState in
                viewModel.setTaskState(entry, newState: newState)
            },
            onBulletTypeChange: { entry, newType in
                viewModel.changeBulletType(entry, newType: newType)
            }
        )
        .opacity(entry.gravityOpacity)
    }

    private func showToast(_ message: String) {
        toastTimer?.invalidate()
        toastMessage = message
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async { toastMessage = nil }
        }
    }

    // MARK: - Input bar colors

    private var glyphColor: Color {
        switch bulletType {
        case .idea: return Theme.idea
        case .task: return .white.opacity(0.7)
        case .event: return Theme.event
        case .note: return .white.opacity(0.7)
        case .unknown: return .white.opacity(0.3)
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

    // MARK: - Actions

    private func expand() {
        withAnimation(Self.openSpring) { isExpanded = true }
        onExpandChange(true)
    }

    private func collapse() {
        isInputFocused = false
        withAnimation(Self.closeSpring) { isExpanded = false }
        onExpandChange(false)
    }

    private func performBounce() {
        withAnimation(Self.bounceSpring) { bounceOffset = 16 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(Self.bounceSpring) { bounceOffset = 0 }
        }
    }

    private func cycleBullet() { bulletType = bulletType.next }

    private func appendEntry() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.append(bulletType: bulletType, content: trimmed)
        draft = ""
        isInputFocused = true
    }
}

// MARK: - Island entry row (dark theme, full interaction)

/// Interactive entry row styled for the dark Island background.
/// Supports task toggle, inline edit, context menu (edit/delete/rescue/task state).
private struct IslandEntryRow: View {
    let entry: StreamEntry
    var onEdit: ((StreamEntry, String) -> Void)?
    var onDelete: ((StreamEntry) -> Void)?
    var onRescue: ((StreamEntry) -> Void)?
    var onTaskStateChange: ((StreamEntry, TaskState) -> Void)?
    var onBulletTypeChange: ((StreamEntry, BulletType) -> Void)?

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editDraft = ""
    @State private var justToggled = false
    @FocusState private var isEditFocused: Bool

    private static let contentFont = Font.system(size: 11)
    private static let timeFont = Font.system(size: 10, design: .monospaced)

    private var isRescuable: Bool {
        entry.ageInDays >= 1 && entry.bulletType != .unknown
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            glyphView

            if isEditing {
                editField
            } else {
                Text(entry.content)
                    .font(Self.contentFont).tracking(-0.15)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(1).lineLimit(2)
                    .strikethrough(entry.taskState == .cancelled)
            }

            Spacer(minLength: 6)
            trailingLabel
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(.white.opacity(isHovering ? 0.06 : 0))
        )
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if isRescuable { onRescue?(entry) }
        }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Glyph

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
                        .font(Self.contentFont).tracking(-0.15)
                        .foregroundStyle(glyphColor)
                        .frame(width: 12, alignment: .leading)
                        .scaleEffect(justToggled ? 1.2 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: justToggled)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(entry.displayGlyph)
                    .font(Self.contentFont).tracking(-0.15)
                    .foregroundStyle(glyphColor)
                    .frame(width: 12, alignment: .leading)
            }
        }
    }

    // MARK: - Inline edit

    private var editField: some View {
        HStack(spacing: 4) {
            TextField("content", text: $editDraft)
                .textFieldStyle(.plain)
                .font(Self.contentFont).tracking(-0.15)
                .foregroundStyle(.white)
                .focused($isEditFocused)
                .onSubmit(commitEdit)
                .onExitCommand(perform: cancelEdit)
            Button { commitEdit() } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.taskDone)
            }
            .buttonStyle(.plain)
            Button { cancelEdit() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    private func beginEditing() {
        editDraft = entry.content
        isEditing = true
        DispatchQueue.main.async { isEditFocused = true }
    }

    private func commitEdit() {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.content else {
            cancelEdit(); return
        }
        onEdit?(entry, trimmed)
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
        editDraft = ""
    }

    // MARK: - Trailing label

    @ViewBuilder
    private var trailingLabel: some View {
        if isHovering && isRescuable {
            Text("↑")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.event.opacity(0.7))
                .fixedSize()
        } else if let t = timeLabel {
            Text(t).font(Self.timeFont)
                .foregroundStyle(.white.opacity(0.35)).fixedSize()
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if entry.bulletType != .unknown {
            Button { beginEditing() } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()
            bulletTypeMenu

            if entry.bulletType == .task {
                Divider()
                taskStateMenu
            }

            if isRescuable {
                Divider()
                Button { onRescue?(entry) } label: {
                    Label("Rescue to Today", systemImage: "arrow.up.to.line")
                }
            }

            Divider()
            Button(role: .destructive) { onDelete?(entry) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var bulletTypeMenu: some View {
        Menu {
            ForEach([BulletType.note, .task, .event, .idea], id: \.self) { type in
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

    @ViewBuilder
    private var taskStateMenu: some View {
        let current = entry.taskState ?? .pending
        if current != .done {
            Button { onTaskStateChange?(entry, .done) } label: {
                Label("Mark Done", systemImage: "checkmark")
            }
        }
        if current != .pending {
            Button { onTaskStateChange?(entry, .pending) } label: {
                Label("Mark Pending", systemImage: "circle")
            }
        }
        if current != .migrated {
            Button { onTaskStateChange?(entry, .migrated) } label: {
                Label("Mark Migrated", systemImage: "arrow.right")
            }
        }
        if current != .cancelled {
            Button { onTaskStateChange?(entry, .cancelled) } label: {
                Label("Mark Cancelled", systemImage: "xmark")
            }
        }
    }

    // MARK: - Colors & time

    private var glyphColor: Color {
        switch entry.bulletType {
        case .idea: return Theme.idea
        case .task:
            switch entry.taskState {
            case .done: return Theme.taskDone
            case .cancelled: return .white.opacity(0.3)
            case .migrated: return Theme.event
            default: return .white.opacity(0.7)
            }
        case .event: return Theme.event
        case .note: return .white.opacity(0.7)
        case .unknown: return .white.opacity(0.3)
        }
    }

    private static let shortTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "ha"; return f
    }()

    private var timeLabel: String? {
        guard let ts = entry.timestamp else { return nil }
        let days = entry.ageInDays
        if days == 0 {
            let s = Int(Date().timeIntervalSince(ts))
            if s < 60 { return "now" }
            let m = s / 60; if m < 60 { return "\(m)m" }
            return "\(m / 60)h"
        } else if days <= 3 {
            return Self.shortTimeFmt.string(from: ts).lowercased()
        }
        return nil
    }
}
