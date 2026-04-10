import Foundation

enum TaskState: String, Codable, Hashable {
    case pending
    case done
    case migrated
    case cancelled

    /// Glyph used to override `BulletType.task`'s default `☐` once the
    /// task has moved past the pending state.
    var glyph: String {
        switch self {
        case .pending: return "☐"
        case .done: return "✓"
        case .migrated: return "▶"
        case .cancelled: return "✕"
        }
    }

    /// Parse the suffix portion of a `task>done` style token. Returns
    /// `.pending` when no suffix is present (`task`), nil for unknown
    /// or empty suffixes (`task>`, `task>garbage`).
    ///
    /// `omittingEmptySubsequences: false` is important: Swift's split
    /// default drops the trailing empty string, so `"task>".split(...)`
    /// would return `["task"]` and we'd mistake the malformed token
    /// for a bare pending task.
    static func parse(token: String) -> TaskState? {
        let parts = token.split(
            separator: ">",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else { return .pending }
        return TaskState(rawValue: String(parts[1]))
    }
}
