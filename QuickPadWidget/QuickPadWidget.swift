import SwiftUI
import WidgetKit

/// The widget extension's bundle entry point. Exposes a single
/// medium-sized widget showing today's most recent entries from the
/// main app's mirror at
/// `~/Library/Containers/dev.quickpad.QuickPad.Widget/Data/Documents/`.
@main
struct QuickPadWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickPadWidget()
    }
}

struct QuickPadWidget: Widget {
    let kind: String = "QuickPadWidget"

    var body: some WidgetConfiguration {
        // No .containerBackground here — the view body sets it based on
        // the widget's rendering mode so we can fade the parchment
        // surface away when the widget goes inactive (matches the
        // behavior of system widgets like Calendar / Weather).
        StaticConfiguration(kind: kind, provider: QuickPadProvider()) { entry in
            QuickPadWidgetView(entry: entry)
        }
        .configurationDisplayName("QuickPad — Today")
        .description("Latest entries from your rapid log, glanceable on the desktop.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
