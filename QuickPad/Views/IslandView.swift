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

    private var recentEntries: [StreamEntry] {
        let all = viewModel.sections.flatMap { $0.entries }
        return Array(all.filter { !$0.isDeleted }.prefix(5))
    }

    private var latestSummary: String {
        guard let first = recentEntries.first else { return "QuickPad" }
        let text = first.content
        return text.count > 28 ? String(text.prefix(28)) + "…" : text
    }

    private var totalEntryCount: Int {
        viewModel.sections.flatMap { $0.entries }.filter { !$0.isDeleted }.count
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
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isInputFocused = true
            }
        }
    }

    // MARK: - Entry row

    private func entryRow(_ entry: StreamEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.displayGlyph)
                .font(Self.contentFont).tracking(-0.15)
                .foregroundStyle(entryGlyphColor(entry))
                .frame(width: 12, alignment: .leading)
            Text(entry.content)
                .font(Self.contentFont).tracking(-0.15)
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(1).lineLimit(2)
                .strikethrough(entry.taskState == .cancelled)
            Spacer(minLength: 6)
            if let t = timeLabel(for: entry) {
                Text(t).font(Self.timeFont)
                    .foregroundStyle(.white.opacity(0.35)).fixedSize()
            }
        }
        .opacity(entry.gravityOpacity)
    }

    // MARK: - Colors

    private func entryGlyphColor(_ entry: StreamEntry) -> Color {
        switch entry.bulletType {
        case .idea: return .yellow
        case .task:
            switch entry.taskState {
            case .done: return .green
            case .cancelled: return .white.opacity(0.3)
            case .migrated: return .blue
            default: return .white.opacity(0.7)
            }
        case .event: return .blue
        case .note: return .white.opacity(0.7)
        case .unknown: return .white.opacity(0.3)
        }
    }

    private var glyphColor: Color {
        switch bulletType {
        case .idea: return .yellow
        case .task: return .white.opacity(0.7)
        case .event: return .blue
        case .note: return .white.opacity(0.7)
        case .unknown: return .white.opacity(0.3)
        }
    }

    // MARK: - Time labels

    private static let shortTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "ha"; return f
    }()

    private func timeLabel(for entry: StreamEntry) -> String? {
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
