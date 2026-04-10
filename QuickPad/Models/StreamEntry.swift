import Foundation

struct StreamEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var timestamp: Date?
    var bulletType: BulletType
    var taskState: TaskState?
    var content: String
    var isPriority: Bool
    var prefixTag: String?
    /// True when the entry has been soft-deleted (`[type>deleted]`).
    /// The UI hides these by default; undo restores them.
    var isDeleted: Bool
    /// The original line from stream.md, kept verbatim so a future
    /// write-back never silently mutates content the parser did not
    /// fully understand.
    var rawLine: String

    init(
        id: UUID = UUID(),
        timestamp: Date?,
        bulletType: BulletType,
        taskState: TaskState? = nil,
        content: String,
        isPriority: Bool = false,
        prefixTag: String? = nil,
        isDeleted: Bool = false,
        rawLine: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bulletType = bulletType
        self.taskState = taskState
        self.content = content
        self.isPriority = isPriority
        self.prefixTag = prefixTag
        self.isDeleted = isDeleted
        self.rawLine = rawLine
    }

    /// Glyph to render in the fixed-width column. Tasks override the
    /// default bullet glyph based on their state.
    var displayGlyph: String {
        if bulletType == .task, let state = taskState {
            return state.glyph
        }
        return bulletType.glyph
    }

    /// Number of calendar days between entry timestamp and now. Returns
    /// 0 for entries without a timestamp (treated as "today"). Clamped
    /// to non-negative so a future timestamp (timezone edge case) never
    /// produces a stale opacity.
    var ageInDays: Int {
        guard let timestamp else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: timestamp, to: Date()).day ?? 0)
    }

    /// Opacity driven by the gravity-decay curve from `ARCHITECTURE.md`.
    /// Older entries fade out, creating the visual "sedimentation" effect.
    var gravityOpacity: Double {
        switch ageInDays {
        case 0:      return 1.0
        case 1:      return 0.85
        case 2...3:  return 0.68
        case 4...7:  return 0.50
        case 8...14: return 0.35
        default:     return 0.22
        }
    }
}
