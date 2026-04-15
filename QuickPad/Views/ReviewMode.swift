import SwiftUI

/// Card-by-card review of entries from N days ago. Activated by ⌘R.
///
/// Why card-by-card and not a list: the point isn't triage speed, it's
/// to force a real decision on each surfaced entry — Karpathy's
/// review step is where value compounds, and a list invites skimming
/// past the slow-burn ideas that need a moment of attention.
struct ReviewMode: View {
    @Environment(StreamViewModel.self) private var viewModel
    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let onClose: () -> Void

    @State private var window: StreamViewModel.ReviewWindow = .sevenDays
    @State private var index: Int = 0
    /// Cached so a Rescue/Graduate that would silently rebuild
    /// `viewModel.sections` mid-session doesn't desync our cursor.
    @State private var pool: [StreamEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            ThemeFadeDivider()
            content
        }
        .background(theme.background(for: colorScheme))
        .onAppear { reload() }
        .onChange(of: window) { _, _ in
            index = 0
            reload()
        }
        // Hidden buttons let us hang keyboard shortcuts off body.
        .background {
            Group {
                Button("Rescue") { performRescue() }.keyboardShortcut("r", modifiers: [])
                Button("Graduate") { performGraduate() }.keyboardShortcut("g", modifiers: [])
                Button("Close") { performClose() }.keyboardShortcut("c", modifiers: [])
                Button("Skip") { performSkip() }.keyboardShortcut("s", modifiers: [])
                Button("Skip2") { performSkip() }.keyboardShortcut(.downArrow, modifiers: [])
                Button("Exit") { onClose() }.keyboardShortcut(.cancelAction)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .foregroundStyle(theme.accent)
            Text("Review")
                .font(theme.uiFont(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary(for: colorScheme))
            Spacer()
            windowPicker
            counter
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Theme.SubtleButton())
            .help("Exit review (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var windowPicker: some View {
        HStack(spacing: 4) {
            ForEach(StreamViewModel.ReviewWindow.allCases) { w in
                Button {
                    window = w
                } label: {
                    Text("\(w.rawValue)d")
                        .font(theme.monoFont(size: 9))
                        .foregroundStyle(
                            w == window
                                ? theme.textPrimary(for: colorScheme)
                                : theme.textSecondary(for: colorScheme)
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(w == window ? theme.accent.opacity(0.18) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    w == window
                                        ? theme.accent.opacity(0.4)
                                        : theme.textTertiary(for: colorScheme).opacity(0.25),
                                    lineWidth: 0.5
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var counter: some View {
        if !pool.isEmpty {
            Text("\(min(index + 1, pool.count)) / \(pool.count)")
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.textSecondary(for: colorScheme))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if pool.isEmpty {
            emptyState
        } else if index >= pool.count {
            doneState
        } else {
            card(for: pool[index])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(theme.textTertiary(for: colorScheme))
            Text("Nothing to review from \(window.rawValue) days ago")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.textSecondary(for: colorScheme))
            Text("Try a different window above")
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.textTertiary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(theme.accent)
            Text("Reviewed \(pool.count) entries from \(window.rawValue) days ago")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.textSecondary(for: colorScheme))
            Button {
                onClose()
            } label: {
                Text("Done · Esc")
                    .font(theme.monoFont(size: 10, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .strokeBorder(theme.accent.opacity(0.4), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(for entry: StreamEntry) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(entry.displayGlyph)
                        .font(theme.contentFont(size: 24))
                        .foregroundStyle(entry.bulletType.glyphColor(theme: theme, scheme: colorScheme, taskState: entry.taskState))
                    Text(relativeAge(entry))
                        .font(theme.monoFont(size: 10))
                        .foregroundStyle(theme.textTertiary(for: colorScheme))
                    Spacer()
                    if let tag = entry.prefixTag {
                        Text(tag)
                            .font(theme.monoFont(size: 9))
                            .foregroundStyle(theme.textSecondary(for: colorScheme))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.textSecondary(for: colorScheme).opacity(0.12), in: Capsule())
                    }
                }

                Text(entry.content)
                    .font(theme.contentFont(size: 14))
                    .foregroundStyle(theme.textPrimary(for: colorScheme))
                    .lineSpacing(theme.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if entry.rescueCount >= 3 {
                    HStack(spacing: 5) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 9))
                        Text("rescued \(entry.rescueCount)× — consider Graduate")
                            .font(theme.monoFont(size: 10))
                    }
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.accent.opacity(0.10), in: Capsule())
                } else if entry.rescueCount > 0 {
                    Text("rescued \(entry.rescueCount)×")
                        .font(theme.monoFont(size: 9))
                        .foregroundStyle(theme.textTertiary(for: colorScheme))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surface(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.divider(for: colorScheme), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            actionRow(for: entry)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    private func actionRow(for entry: StreamEntry) -> some View {
        HStack(spacing: 8) {
            actionButton(label: "Rescue", key: "R", color: theme.accent) { performRescue() }
            actionButton(label: "Graduate", key: "G", color: theme.accent) { performGraduate() }
            actionButton(label: closeLabel(for: entry), key: "C", color: theme.priority) { performClose() }
            Spacer()
            actionButton(label: "Skip", key: "S", color: theme.textTertiary(for: colorScheme)) { performSkip() }
        }
    }

    private func closeLabel(for entry: StreamEntry) -> String {
        switch entry.bulletType {
        case .task: return "Done"
        default:    return "Cancel"
        }
    }

    private func actionButton(label: String, key: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(theme.monoFont(size: 10, weight: .medium))
                Text(key)
                    .font(theme.monoFont(size: 8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.18), in: Capsule())
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .strokeBorder(color.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pool / actions

    private func reload() {
        pool = viewModel.reviewPool(window: window)
    }

    private func currentEntry() -> StreamEntry? {
        guard index >= 0, index < pool.count else { return nil }
        return pool[index]
    }

    private func advance() {
        index += 1
    }

    private func performRescue() {
        guard let entry = currentEntry() else { return }
        viewModel.rescueEntry(entry)
        advance()
    }

    private func performGraduate() {
        guard let entry = currentEntry() else { return }
        viewModel.graduateEntry(entry)
        advance()
    }

    private func performClose() {
        guard let entry = currentEntry() else { return }
        if entry.bulletType == .task {
            viewModel.setTaskState(entry, newState: .done)
        } else {
            viewModel.deleteEntry(entry)
        }
        advance()
    }

    private func performSkip() {
        advance()
    }

    // MARK: - Display helpers

    private func relativeAge(_ entry: StreamEntry) -> String {
        let days = entry.ageInDays
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }
}
