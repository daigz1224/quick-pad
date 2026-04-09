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
    /// `.pending` when no suffix is present, nil for unknown suffixes.
    static func parse(token: String) -> TaskState? {
        let parts = token.split(separator: ">", maxSplits: 1)
        guard parts.count == 2 else { return .pending }
        return TaskState(rawValue: String(parts[1]))
    }
}
