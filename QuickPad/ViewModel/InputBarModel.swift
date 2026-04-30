import Foundation
import Observation

/// Thin shared state for the popover's input row. Lives in its own
/// object so the InputBar's bullet glyph and the surrounding chrome
/// can mutate compose state without InputBar exposing `@State`.
@Observable
final class InputBarModel {
    var bulletType: BulletType = .note
    var draft: String = ""

    /// Cycle to the next bullet type (Tab / glyph click).
    func cycleBullet() {
        bulletType = bulletType.next
    }

    func clearDraft() {
        draft = ""
    }
}
