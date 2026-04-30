import SwiftUI

/// Activity heatmap (12 weeks × 7 days) plus three count chips. Fixed
/// pixels on the heatmap so the bar never reflows at 420pt; chips on
/// the right carry the numbers a heatmap can't express (today's input,
/// month closure rate, stale nudge).
///
/// The aggregator is cached on `StreamViewModel` keyed on a sections
/// version + today's date so SwiftUI body re-evals don't re-walk every
/// entry on every keystroke.
struct StreamStatsBar: View {
    @Environment(StreamViewModel.self) private var viewModel
    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private static let weeksShown: Int = 12
    private static let cellSize: CGFloat = 7
    private static let cellGap: CGFloat = 1.5

    var body: some View {
        let agg = viewModel.cachedHeatmap(weeksShown: Self.weeksShown)

        HStack(alignment: .center, spacing: 14) {
            heatmap(grid: agg.grid, today: agg.today)
            rightRail(agg: agg)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(theme.surface(for: colorScheme).opacity(0.4))
        .overlay(alignment: .bottom) { ThemeFadeDivider() }
    }

    // MARK: - Heatmap

    private func heatmap(grid: [[HeatmapAggregator.Day]], today: Date) -> some View {
        VStack(alignment: .leading, spacing: Self.cellGap) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: Self.cellGap) {
                    ForEach(0..<grid.count, id: \.self) { col in
                        cell(for: grid[col][row], isToday: grid[col][row].date == today)
                    }
                }
            }
        }
        .help("Activity over the last \(Self.weeksShown) weeks")
    }

    private func cell(for day: HeatmapAggregator.Day, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(cellColor(for: day))
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.85), lineWidth: 0.8)
                }
            }
            .help(tooltip(for: day))
    }

    /// Cutoffs picked from observation: most active days fall in 1–8
    /// entries, brain-dump days spike to 15+. Saturating at >8 keeps
    /// outliers from washing out the gradient.
    private func cellColor(for day: HeatmapAggregator.Day) -> Color {
        if day.isFuture {
            return theme.divider(for: colorScheme).opacity(0.3)
        }
        switch day.count {
        case 0:    return theme.textTertiary(for: colorScheme).opacity(0.18)
        case 1:    return theme.accent.opacity(0.28)
        case 2...3: return theme.accent.opacity(0.48)
        case 4...8: return theme.accent.opacity(0.72)
        default:   return theme.accent.opacity(0.95)
        }
    }

    private func tooltip(for day: HeatmapAggregator.Day) -> String {
        let dateStr = Self.tooltipDateFormatter.string(from: day.date)
        if day.isFuture { return dateStr }
        switch day.count {
        case 0: return "\(dateStr) · no entries"
        case 1: return "\(dateStr) · 1 entry"
        default: return "\(dateStr) · \(day.count) entries"
        }
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd EEE"
        return f
    }()

    // MARK: - Right rail

    private func rightRail(agg: HeatmapAggregator) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            chip(value: "\(agg.todayAppended)", label: "today")
            chip(
                value: agg.monthTotal > 0 ? "\(agg.monthClosed)/\(agg.monthTotal)" : "0",
                label: "done · \(Self.monthFormatter.string(from: agg.today).lowercased())",
                valueColor: theme.taskDone,
                help: monthTooltip(agg: agg)
            )
            staleChip(agg.staleTaskCount)
        }
    }

    @ViewBuilder
    private func chip(
        value: String,
        label: String,
        valueColor: Color? = nil,
        help: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(theme.monoFont(size: 11, weight: .medium))
                .foregroundStyle(valueColor ?? theme.textPrimary(for: colorScheme))
            Text(label)
                .font(theme.monoFont(size: 9))
                .foregroundStyle(theme.textTertiary(for: colorScheme))
                .tracking(0.2)
        }
        .help(help ?? "")
    }

    private func staleChip(_ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(count)")
                .font(theme.monoFont(size: 11, weight: .medium))
                .foregroundStyle(count > 0 ? theme.priority : theme.textTertiary(for: colorScheme))
            HStack(spacing: 4) {
                Text("stale")
                    .font(theme.monoFont(size: 9))
                    .foregroundStyle(count > 0 ? theme.priority.opacity(0.85) : theme.textTertiary(for: colorScheme))
                    .tracking(0.2)
                if count > 0 {
                    Circle()
                        .fill(theme.priority)
                        .frame(width: 4, height: 4)
                        .offset(y: -1)
                }
            }
        }
        .help(count > 0
              ? "\(count) pending task\(count == 1 ? "" : "s") older than \(StreamEntry.staleThresholdDays) days — open Review (⌘R, then 'stale')"
              : "No pending tasks older than \(StreamEntry.staleThresholdDays) days")
    }

    private func monthTooltip(agg: HeatmapAggregator) -> String {
        let monthName = Self.monthFormatter.string(from: agg.today)
        if agg.monthTotal == 0 {
            return "\(monthName): no tasks logged yet"
        }
        let pct = Int((Double(agg.monthClosed) / Double(agg.monthTotal) * 100).rounded())
        return "\(monthName): \(agg.monthClosed)/\(agg.monthTotal) closed · \(pct)%"
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM"
        return f
    }()
}

// MARK: - HeatmapAggregator

/// Single-pass rollup: per-day counts for the heatmap grid plus the
/// month closure stats and the right-rail counters. Pure — testable
/// without instantiating SwiftUI.
struct HeatmapAggregator {
    let grid: [[Day]]
    let today: Date
    let monthClosed: Int
    let monthTotal: Int
    let todayAppended: Int
    let staleTaskCount: Int

    struct Day: Equatable {
        let date: Date
        let count: Int
        let isFuture: Bool
    }

    static func build(
        sections: [StreamSection],
        weeksShown: Int = 12,
        now: Date = Date()
    ) -> HeatmapAggregator {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // Locale-aware: zh-Hans typically Sunday-start, but a custom
        // Calendar (e.g. Monday-start in iCal preferences) propagates.
        let weekday = cal.component(.weekday, from: today)
        let daysSinceWeekStart = (weekday - cal.firstWeekday + 7) % 7
        let thisWeekStart = cal.date(byAdding: .day, value: -daysSinceWeekStart, to: today) ?? today
        let firstWeekStart = cal.date(byAdding: .weekOfYear, value: -(weeksShown - 1), to: thisWeekStart) ?? thisWeekStart

        var byDay: [Date: Int] = [:]
        var monthClosed = 0
        var monthTotal = 0
        var staleTaskCount = 0
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today

        for section in sections {
            for entry in section.entries where !entry.isDeleted {
                if entry.isStaleTask { staleTaskCount += 1 }
                guard let ts = entry.timestamp else { continue }
                let day = cal.startOfDay(for: ts)
                byDay[day, default: 0] += 1

                if ts >= monthStart, entry.bulletType == .task {
                    monthTotal += 1
                    if let state = entry.taskState, state == .done || state == .cancelled {
                        monthClosed += 1
                    }
                }
            }
        }

        var grid: [[Day]] = []
        grid.reserveCapacity(weeksShown)
        for week in 0..<weeksShown {
            var col: [Day] = []
            col.reserveCapacity(7)
            for row in 0..<7 {
                let date = cal.date(byAdding: .day, value: week * 7 + row, to: firstWeekStart) ?? firstWeekStart
                col.append(Day(
                    date: date,
                    count: byDay[date] ?? 0,
                    isFuture: date > today
                ))
            }
            grid.append(col)
        }

        return HeatmapAggregator(
            grid: grid,
            today: today,
            monthClosed: monthClosed,
            monthTotal: monthTotal,
            todayAppended: byDay[today] ?? 0,
            staleTaskCount: staleTaskCount
        )
    }
}
