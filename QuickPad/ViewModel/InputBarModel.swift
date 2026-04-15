import Foundation
import Observation

/// Thin shared state for the popover's input row and the hint bar
/// underneath it. Lives in its own object so HintBar can flip the
/// bullet type or prepend a prefix without InputBar having to expose
/// internal `@State`.
@Observable
final class InputBarModel {
    var bulletType: BulletType = .note
    var draft: String = ""

    /// Cycle to the next bullet type (Tab / glyph click / chip click).
    func cycleBullet() {
        bulletType = bulletType.next
    }

    /// Set bullet type explicitly (chip click in HintBar).
    func setBullet(_ type: BulletType) {
        bulletType = type
    }

    /// Prepend a prefix string into the draft. Idempotent — won't add
    /// the same prefix twice if it's already at the start.
    func prependPrefix(_ prefix: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(prefix) { return }
        if draft.isEmpty {
            draft = prefix
        } else {
            draft = prefix + draft
        }
    }

    func clearDraft() {
        draft = ""
    }
}
