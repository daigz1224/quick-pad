import SwiftUI

/// Day separator row rendered as a section header in the stream list.
/// Format intentionally mimics the architecture-doc mockup:
///   `─────────── TODAY · APR 9 ───────────`
struct DaySeparatorView: View {
    let date: Date?
    let rawHeader: String?

    var body: some View {
        // Padding is controlled by the parent (`StreamListView`) so
        // section spacing stays consistent and this view stays a pure
        // label.
        HStack(spacing: 6) {
            line
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .fixedSize()
            line
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 1)
    }

    private var label: String {
        guard let date else {
            return rawHeader ?? "—"
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY · \(monthDayFormatter.string(from: date))".uppercased()
        }
        if calendar.isDateInYesterday(date) {
            return "YESTERDAY · \(monthDayFormatter.string(from: date))".uppercased()
        }
        // Older dates fall back to "MMM d · EEE" — the doc's gravity decay
        // for date headers is Phase 2; here we just keep it short.
        return monthDayWeekdayFormatter.string(from: date).uppercased()
    }

    private var monthDayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }

    private var monthDayWeekdayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d · EEE"
        return f
    }
}
