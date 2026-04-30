import SwiftUI

/// Time-window picker for ⌘⇧E. ⌘E continues to export everything visible;
/// this sheet adds the range picker without disturbing that muscle memory.
struct ExportRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(\.colorScheme) private var scheme

    /// Invoked with the chosen interval (nil = export all).
    var onConfirm: (DateInterval?) -> Void

    @State private var preset: Preset = .last7d
    @State private var customStart: Date = Calendar.current
        .date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    enum Preset: String, CaseIterable, Identifiable {
        case today = "Today"
        case last7d = "Last 7 days"
        case last30d = "Last 30 days"
        case all = "All time"
        case custom = "Custom"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Stream")
                    .font(theme.uiFont(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary(for: scheme))
                Text("Pick a time window for the exported entries.")
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(theme.textSecondary(for: scheme))
            }

            Picker("Range", selection: $preset) {
                ForEach(Preset.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if preset == .custom {
                customRangeFields
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    onConfirm(intervalForCurrentSelection())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.background(for: scheme))
    }

    private var customRangeFields: some View {
        HStack(spacing: 12) {
            DatePicker(
                "From",
                selection: $customStart,
                displayedComponents: .date
            )
            .labelsHidden()
            Text("→")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.textTertiary(for: scheme))
            DatePicker(
                "To",
                selection: $customEnd,
                displayedComponents: .date
            )
            .labelsHidden()
        }
        .font(theme.monoFont(size: 11))
    }

    /// Convert the picker state into a DateInterval. Half-open at the
    /// upper bound (`end = startOfDay(lastDay + 1)`) so an entry timestamped
    /// at 23:59 of the last selected day is still included.
    private func intervalForCurrentSelection() -> DateInterval? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today

        switch preset {
        case .today:
            return DateInterval(start: today, end: tomorrow)
        case .last7d:
            let start = cal.date(byAdding: .day, value: -6, to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        case .last30d:
            let start = cal.date(byAdding: .day, value: -29, to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        case .all:
            return nil
        case .custom:
            // Guard against a "from > to" mis-set so DateInterval's
            // precondition doesn't trap.
            let lo = cal.startOfDay(for: min(customStart, customEnd))
            let hi = cal.startOfDay(for: max(customStart, customEnd))
            let hiNext = cal.date(byAdding: .day, value: 1, to: hi) ?? hi
            return DateInterval(start: lo, end: hiNext)
        }
    }
}
