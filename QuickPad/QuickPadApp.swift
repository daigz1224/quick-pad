import SwiftUI

@main
struct QuickPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The whole UI lives in the menu bar popover the AppDelegate
        // owns. `Settings` is a no-op scene that doesn't open a window
        // on launch — it just keeps SwiftUI's `App` happy without us
        // having to declare a real `WindowGroup`.
        Settings {
            EmptyView()
        }
    }
}
