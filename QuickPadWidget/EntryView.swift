import SwiftUI
import WidgetKit

/// Medium-sized widget. Matches the Ephemeris icon's aesthetic:
/// parchment ground, sumi text, one cinnabar accent reserved for the
/// freshest entry. Tap anywhere → opens the main app via `quickpad://`.
struct QuickPadWidgetView: View {
    let entry: QuickPadEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            if entry.entries.isEmpty {
                emptyState
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.entries.enumerated()), id: \.offset) { idx, e in
                        row(for: e, isFreshest: idx == 0)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "quickpad://open"))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("QuickPad")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Color.widgetTextPrimary)
            Text("· today")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.widgetTextTertiary)
            Spacer()
            if entry.totalToday > 0 {
                Text("\(entry.totalToday)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.widgetTextSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.widgetTextTertiary.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("nothing captured yet today")
                .font(.system(size: 11))
                .foregroundStyle(Color.widgetTextTertiary)
            Text("⌥N to open · ⌥⇧N to quick-capture")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.widgetTextTertiary.opacity(0.7))
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for e: StreamEntry, isFreshest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Bullet glyph. The freshest gets cinnabar (the Ephemeris
            // accent — "today's marked observation"); others stay sumi.
            Text(e.displayGlyph)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isFreshest ? Color.widgetAccent : Color.widgetTextSecondary)
                .frame(width: 12, alignment: .leading)

            Text(e.content)
                .font(.system(size: 11))
                .foregroundStyle(isFreshest ? Color.widgetTextPrimary : Color.widgetTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Palette tokens
//
// Pulled from the Ephemeris icon language so the widget reads as the
// same family as the app icon. Kept local to the widget target — the
// main app's Theme is SwiftUI-friendly but assumes ThemeManager
// observation we don't want to drag across the target boundary.

extension Color {
    /// Warm parchment — the widget's surface.
    static let widgetBackground = Color(
        red: 244/255, green: 238/255, blue: 226/255
    )
    /// Sumi ink for primary text.
    static let widgetTextPrimary = Color(
        red:  28/255, green:  25/255, blue:  22/255
    )
    /// Slightly faded sumi for older / supporting text.
    static let widgetTextSecondary = Color(
        red:  64/255, green:  60/255, blue:  56/255
    )
    /// Whispered sumi for labels, count badges, and the empty state.
    static let widgetTextTertiary = Color(
        red: 120/255, green: 114/255, blue: 106/255
    )
    /// Oxidised cinnabar — reserved for the freshest entry's glyph.
    static let widgetAccent = Color(
        red: 172/255, green:  56/255, blue:  44/255
    )
}
