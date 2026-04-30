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
    /// Number of times this entry has been rescued back to today.
    /// Stored inline in the bracket token as `@rN` (`[task @r3] foo`).
    /// Drives Review mode's "frequently rescued — consider Graduate"
    /// hint and the Phase 7 stats strip. Defaults to 0; absence in
    /// stream.md parses as 0 so old files remain forward-compatible.
    var rescueCount: Int
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
        rescueCount: Int = 0,
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
        self.rescueCount = rescueCount
        self.rawLine = rawLine
    }

    /// Glyph to render in the fixed-width column. Non-pending task
    /// states (done/cancelled/migrated) use semantic glyphs (✓ ✕ ▶);
    /// everything else falls back to the bullet type's glyph.
    var displayGlyph: String {
        if bulletType == .task, let state = taskState, state != .pending {
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
        let cal = Calendar.current
        let entryDay = cal.startOfDay(for: timestamp)
        let today = cal.startOfDay(for: Date())
        return max(0, cal.dateComponents([.day], from: entryDay, to: today).day ?? 0)
    }

    /// Days a pending task can sit before it's flagged stale. Sits well
    /// below the 30-day archive rule so users notice the nudge before
    /// the archiver removes anything.
    static let staleThresholdDays: Int = 7

    /// Pending task that's been open at least `staleThresholdDays` —
    /// drives the row's pulsing dot and the stale stats chip.
    var isStaleTask: Bool {
        bulletType == .task
            && (taskState == nil || taskState == .pending)
            && ageInDays >= Self.staleThresholdDays
    }

    /// Default 3 = "survived three rescue passes." Override via
    /// `defaults write dev.quickpad.QuickPad graduateHintThreshold -int N`.
    static let graduateHintThresholdDefault: Int = 3
    static let graduateHintThresholdKey: String = "graduateHintThreshold"

    static var graduateHintThreshold: Int {
        let stored = UserDefaults.standard.integer(forKey: graduateHintThresholdKey)
        return stored > 0 ? stored : graduateHintThresholdDefault
    }

    var shouldShowGraduateHint: Bool {
        guard !isDeleted, bulletType != .unknown else { return false }
        if bulletType == .task, let state = taskState, state != .pending {
            return false
        }
        return rescueCount >= Self.graduateHintThreshold
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
