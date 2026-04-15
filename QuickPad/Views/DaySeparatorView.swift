import SwiftUI

/// Day separator row rendered as a section header in the stream list.
/// Format intentionally mimics the architecture-doc mockup:
///   `─────────── TODAY · APR 9 ───────────`
///
/// Label precision decays with age (gravity system):
/// - Today: "TODAY · APR 9"
/// - Yesterday: "YESTERDAY · APR 8"
/// - 2-7 days: "APR 6 · SUN"
/// - Older: "MAR 20"
struct DaySeparatorView: View {
    let date: Date?
    let rawHeader: String?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            line
            labelView
            line
        }
        .opacity(separatorOpacity)
    }

    @ViewBuilder
    private var labelView: some View {
        let text = Text(label)
            .font(theme.uiFont(size: 10, weight: .medium))
            .tracking(0.3)
            .foregroundStyle(theme.textSecondary(for: colorScheme))
            .fixedSize()

        if isToday {
            text
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(theme.accent.opacity(0.10), in: Capsule())
        } else {
            text
        }
    }

    private var isToday: Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private var line: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, theme.divider(for: colorScheme), .clear],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 0.5)
    }

    /// Separator opacity follows the gravity curve but stays slightly
    /// more visible than entries (structural landmarks should never
    /// fully vanish).
    private var separatorOpacity: Double {
        guard let date else { return 1.0 }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case 0...1:  return 1.0
        case 2...3:  return 0.85
        case 4...7:  return 0.72
        case 8...14: return 0.55
        default:     return 0.40
        }
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
        // Within a week: show weekday for easy recall.
        let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 7 {
            return monthDayWeekdayFormatter.string(from: date).uppercased()
        }
        // Older: just month + day — the weekday is no longer useful.
        return monthDayFormatter.string(from: date).uppercased()
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
