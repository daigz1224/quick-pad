import SwiftUI

/// One-line stats strip wedged between the popover header and the
/// input row. Tells you what your stream looks like right now —
/// today's append count, the last 7 days' task closure rate, and
/// total rescues — turning the gravity system from "things fade out"
/// into "look, you actually do come back to old stuff."
struct StreamStatsBar: View {
    let sections: [StreamSection]

    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private struct Stats {
        var todayAppended: Int = 0
        var weekAppended: Int = 0
        var weekTasksClosed: Int = 0
        var totalRescued: Int = 0
        var staleTaskCount: Int = 0
    }

    private var stats: Stats {
        var out = Stats()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today

        for section in sections {
            for entry in section.entries where !entry.isDeleted {
                guard let ts = entry.timestamp else { continue }
                if ts >= today {
                    out.todayAppended += 1
                }
                if ts >= weekAgo {
                    out.weekAppended += 1
                    if entry.bulletType == .task,
                       let state = entry.taskState,
                       state == .done || state == .cancelled {
                        out.weekTasksClosed += 1
                    }
                }
                out.totalRescued += entry.rescueCount
                if entry.isStaleTask {
                    out.staleTaskCount += 1
                }
            }
        }
        return out
    }

    var body: some View {
        let s = stats
        HStack(spacing: 10) {
            statChip(label: "today", value: "\(s.todayAppended)")
            divider
            statChip(label: "7d", value: "\(s.weekAppended)")
            divider
            statChip(label: "✓", value: "\(s.weekTasksClosed)", help: "tasks closed in the last 7 days")
            divider
            statChip(label: "↑", value: "\(s.totalRescued)", help: "lifetime rescues across visible entries")
            if s.staleTaskCount > 0 {
                divider
                staleChip(s.staleTaskCount)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(theme.surface(for: colorScheme).opacity(0.5))
        .overlay(alignment: .bottom) {
            ThemeFadeDivider()
        }
    }

    private var divider: some View {
        Text("·")
            .font(theme.monoFont(size: 9))
            .foregroundStyle(theme.textTertiary(for: colorScheme))
    }

    private func statChip(label: String, value: String, help: String? = nil) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(theme.textTertiary(for: colorScheme))
            Text(value)
                .foregroundStyle(theme.textSecondary(for: colorScheme))
        }
        .font(theme.monoFont(size: 9))
        .help(help ?? "")
    }

    private func staleChip(_ count: Int) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(theme.priority)
                .frame(width: 4, height: 4)
            Text("\(count) stale")
                .foregroundStyle(theme.priority)
        }
        .font(theme.monoFont(size: 9))
        .help("Pending tasks older than 7 days — open Review (⌘R) to triage")
    }
}
