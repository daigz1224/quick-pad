import Foundation

enum BulletType: String, Codable, Hashable, CaseIterable {
    case note
    case task
    case question
    case idea
    case unknown

    /// Display glyph rendered in the fixed-width column to the left of every entry.
    var glyph: String {
        switch self {
        case .note: return "—"
        case .task: return "☐"
        case .question: return "?"
        case .idea: return "!"
        case .unknown: return "⋯"
        }
    }

    /// Parse the bracketed token from a stream entry. Accepts the bare type
    /// (`task`) or a type with a task-state suffix (`task>done`).
    /// `event` is accepted as a legacy alias for `question` so streams
    /// written before the rename continue to load without a migration pass.
    /// Returns nil for tokens we do not recognise so callers can fall back
    /// to `.unknown`.
    static func parse(token: String) -> BulletType? {
        let head = token.split(separator: ">", maxSplits: 1).first.map(String.init) ?? token
        if head == "event" { return .question }
        return BulletType(rawValue: head)
    }

    /// Cycle order used by the input bar's bullet-type button and the
    /// Tab key shortcut. `.unknown` is not part of the user-facing cycle
    /// — it only shows up when the parser couldn't classify a line — so
    /// it maps back to `.note` if we ever land on it.
    var next: BulletType {
        switch self {
        case .note: return .task
        case .task: return .question
        case .question: return .idea
        case .idea: return .note
        case .unknown: return .note
        }
    }

    /// Human-readable label for the input bar's help text / accessibility.
    var label: String {
        switch self {
        case .note: return "note"
        case .task: return "task"
        case .question: return "question"
        case .idea: return "idea"
        case .unknown: return "unknown"
        }
    }
}
