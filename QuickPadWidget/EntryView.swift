import SwiftUI
import WidgetKit

/// Medium-sized widget. Matches the Ephemeris icon's aesthetic when
/// the widget is actively in view: parchment surface, sumi text, one
/// cinnabar accent reserved for the freshest entry.
///
/// When the system marks the widget as **inactive** — a window covers
/// it, or the desktop has been idle long enough — `widgetRenderingMode`
/// flips to `.accented` and we collapse into the system's vibrancy
/// language: container goes translucent so the desktop wallpaper bleeds
/// through, text uses hierarchical system styles so they desaturate to
/// a single tint, and our accent maps to `.tint` so the cinnabar fades
/// alongside everything else. Same effect Apple's Calendar / Weather
/// widgets do when they recede into the background.
///
/// Tap anywhere → opens the main app via `quickpad://`.
struct QuickPadWidgetView: View {
    let entry: QuickPadEntry

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isAccented: Bool { renderingMode == .accented }

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
        .widgetURL(AppURLScheme.openURL)
        .containerBackground(for: .widget) {
            isAccented ? Color.clear : Color.widgetBackground
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("QuickPad")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primaryStyle)
            Text("· today")
                .font(.system(size: 11))
                .foregroundStyle(tertiaryStyle)
            Spacer()
            if entry.totalToday > 0 {
                Text("\(entry.totalToday)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryStyle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(badgeFill)
                    )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("nothing captured yet today")
                .font(.system(size: 11))
                .foregroundStyle(tertiaryStyle)
            Text("⌥N to open · ⌥⇧N to quick-capture")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(tertiaryStyle)
                .opacity(0.75)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for e: StreamEntry, isFreshest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // `.widgetAccentable` opts the cinnabar bullet into the
            // system's inactive-mode tint, so it desaturates alongside
            // everything else when the widget fades.
            Text(e.displayGlyph)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isFreshest ? accentStyle : secondaryStyle)
                .frame(width: 12, alignment: .leading)
                .widgetAccentable(isFreshest)

            Text(e.content)
                .font(.system(size: 11))
                .foregroundStyle(isFreshest ? primaryStyle : secondaryStyle)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Style helpers
    //
    // Hand off to hierarchical system styles in `.accented` so macOS
    // can tint the whole widget uniformly when it goes inactive.

    private var primaryStyle: AnyShapeStyle {
        isAccented
            ? AnyShapeStyle(HierarchicalShapeStyle.primary)
            : AnyShapeStyle(Color.widgetTextPrimary)
    }

    private var secondaryStyle: AnyShapeStyle {
        isAccented
            ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
            : AnyShapeStyle(Color.widgetTextSecondary)
    }

    private var tertiaryStyle: AnyShapeStyle {
        isAccented
            ? AnyShapeStyle(HierarchicalShapeStyle.tertiary)
            : AnyShapeStyle(Color.widgetTextTertiary)
    }

    private var accentStyle: AnyShapeStyle {
        isAccented
            ? AnyShapeStyle(HierarchicalShapeStyle.primary)
            : AnyShapeStyle(Color.widgetAccent)
    }

    private var badgeFill: AnyShapeStyle {
        isAccented
            ? AnyShapeStyle(HierarchicalShapeStyle.quaternary)
            : AnyShapeStyle(Color.widgetTextTertiary.opacity(0.15))
    }
}

// MARK: - Palette tokens
//
// Used only in `.fullColor` rendering — when the widget is active and
// reads as the parchment surface from the Ephemeris icon language.
// `.accented` mode bypasses these in favor of hierarchical system
// styles, which the OS desaturates and tints uniformly.

extension Color {
    /// Warm parchment — the widget's surface when active.
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

// `.widgetAccentable(_ flag: Bool)` is already part of stock SwiftUI
// (`widgetAccentable(_ isAccentable: Bool = true)`), so the `isFreshest`
// call sites resolve directly against Apple's API.
