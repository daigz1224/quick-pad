import SwiftUI
import WidgetKit

/// The widget extension's bundle entry point. Exposes a single
/// medium-sized widget showing today's most recent entries from
/// `~/.quickpad/stream.md`. The widget runs un-sandboxed so it can
/// read the canonical file directly (mirroring our App Group rationale
/// for the main app's data store).
@main
struct QuickPadWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickPadWidget()
    }
}

struct QuickPadWidget: Widget {
    let kind: String = "QuickPadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickPadProvider()) { entry in
            QuickPadWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.widgetBackground
                }
        }
        .configurationDisplayName("QuickPad — Today")
        .description("Latest entries from your rapid log, glanceable on the desktop.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
