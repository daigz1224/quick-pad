import Foundation

/// Bridges QuickPad's canonical `~/.quickpad/stream.md` into the widget
/// extension's sandbox container so the widget — which IS sandboxed by
/// macOS even with ad-hoc signing — has something to read.
///
/// ## Why not App Groups
///
/// The textbook bridge is an App Group, but
/// `com.apple.security.application-groups` requires a paid Apple
/// Developer ID's provisioning profile. Ad-hoc signing's `-` identity
/// can't claim it.
///
/// ## Why not `temporary-exception.files.home-relative-path`
///
/// The escape hatch entitlement compiles in and embeds in the signature
/// fine, but Apple's sandbox runtime only honors it for binaries signed
/// by an Apple-issued cert. Under ad-hoc signing the entitlement is
/// silently ignored — the widget gets "permission denied" reading
/// `~/.quickpad/stream.md`.
///
/// ## What we do instead
///
/// The widget's sandbox container at
/// `~/Library/Containers/<widget-bundle-id>/Data/Documents/` is wide-
/// open from the *widget's* perspective. The main app, which is not
/// sandboxed, can also write there as a normal user-level filesystem
/// op. So: every time `stream.md` changes, the main app drops a fresh
/// copy at that path. The widget reads its own `.documentDirectory`
/// with no extra entitlement.
enum WidgetMirror {
    /// Bundle identifier of the widget extension. Hard-coded — has to
    /// stay in sync with `project.yml`'s `QuickPadWidget` target.
    static let widgetBundleID = "dev.quickpad.QuickPad.Widget"

    /// Mirror destination — inside the widget's sandbox container.
    /// Filename matches the canonical name so widget code can use the
    /// same parsing path with no special-casing.
    static var streamMirrorURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleID, isDirectory: true)
            .appendingPathComponent("Data/Documents", isDirectory: true)
            .appendingPathComponent("stream.md", isDirectory: false)
    }

    /// Copy the canonical stream.md into the widget's container. Writes
    /// atomically so the widget never sees a partial read. Returns
    /// false on any failure (source missing, container not yet
    /// provisioned by the OS, write denied) — callers can ignore;
    /// the next FSEvent will try again.
    @discardableResult
    static func mirrorStream(from source: URL) -> Bool {
        let dest = streamMirrorURL
        let destDir = dest.deletingLastPathComponent()

        do {
            // The widget's container is auto-created the first time
            // the widget runs; pre-creating from here lets the very
            // first capture land before the user adds the widget.
            try FileManager.default.createDirectory(
                at: destDir, withIntermediateDirectories: true
            )
            let data = try Data(contentsOf: source)
            try data.write(to: dest, options: .atomic)
            return true
        } catch {
            // Non-fatal — widget stays one tick behind; next FSEvent
            // retries. Log for debugging.
            print("[WidgetMirror] failed: \(error.localizedDescription)")
            return false
        }
    }
}
