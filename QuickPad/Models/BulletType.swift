import Foundation

enum BulletType: String, Codable, Hashable, CaseIterable {
    case note
    case task
    case event
    case idea
    case unknown

    /// Display glyph rendered in the fixed-width column to the left of every entry.
    var glyph: String {
        switch self {
        case .note: return "—"
        case .task: return "☐"
        case .event: return "○"
        case .idea: return "!"
        case .unknown: return "?"
        }
    }

    /// Parse the bracketed token from a stream entry. Accepts the bare type
    /// (`task`) or a type with a task-state suffix (`task>done`).
    /// Returns nil for tokens we do not recognise so callers can fall back
    /// to `.unknown`.
    static func parse(token: String) -> BulletType? {
        let head = token.split(separator: ">", maxSplits: 1).first.map(String.init) ?? token
        return BulletType(rawValue: head)
    }

    /// Cycle order used by the input bar's bullet-type button and the
    /// Tab key shortcut. `.unknown` is not part of the user-facing cycle
    /// — it only shows up when the parser couldn't classify a line — so
    /// it maps back to `.note` if we ever land on it.
    var next: BulletType {
        switch self {
        case .note: return .task
        case .task: return .event
        case .event: return .idea
        case .idea: return .note
        case .unknown: return .note
        }
    }

    /// Human-readable label for the input bar's help text / accessibility.
    var label: String {
        switch self {
        case .note: return "note"
        case .task: return "task"
        case .event: return "event"
        case .idea: return "idea"
        case .unknown: return "unknown"
        }
    }
}
