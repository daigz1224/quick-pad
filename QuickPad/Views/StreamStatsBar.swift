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
        // Only render chips with signal. A `✓ 0` or `↑ 0` next to a
        // real number is just noise — the lack of value is itself
        // information the user doesn't need reminding of.
        HStack(spacing: 14) {
            statChip(value: "\(s.todayAppended)", label: "today")
            if s.weekAppended != s.todayAppended {
                divider
                statChip(value: "\(s.weekAppended)", label: "this week")
            }
            if s.weekTasksClosed > 0 {
                divider
                statChip(
                    value: "\(s.weekTasksClosed)",
                    label: "done",
                    valueColor: theme.taskDone,
                    help: "tasks closed in the last 7 days"
                )
            }
            if s.totalRescued > 0 {
                divider
                statChip(
                    value: "\(s.totalRescued)↑",
                    label: "rescued",
                    help: "lifetime rescues across visible entries"
                )
            }
            if s.staleTaskCount > 0 {
                divider
                staleChip(s.staleTaskCount)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(theme.surface(for: colorScheme).opacity(0.4))
        .overlay(alignment: .bottom) {
            ThemeFadeDivider()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.textTertiary(for: colorScheme).opacity(0.25))
            .frame(width: 0.5, height: 9)
    }

    private func statChip(
        value: String,
        label: String,
        valueColor: Color? = nil,
        help: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(theme.monoFont(size: 10, weight: .medium))
                .foregroundStyle(valueColor ?? theme.textPrimary(for: colorScheme))
            Text(label)
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.textTertiary(for: colorScheme))
                .tracking(0.3)
        }
        .help(help ?? "")
    }

    private func staleChip(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Circle()
                .fill(theme.priority)
                .frame(width: 4, height: 4)
                .offset(y: -1)
            Text("\(count)")
                .font(theme.monoFont(size: 10, weight: .medium))
                .foregroundStyle(theme.priority)
            Text("stale")
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.priority.opacity(0.8))
                .tracking(0.3)
        }
        .help("Pending tasks older than 7 days — open Review (⌘R) to triage")
    }
}
