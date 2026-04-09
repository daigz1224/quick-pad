import Foundation

struct StreamEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var timestamp: Date?
    var bulletType: BulletType
    var taskState: TaskState?
    var content: String
    var isPriority: Bool
    var prefixTag: String?
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
        rawLine: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bulletType = bulletType
        self.taskState = taskState
        self.content = content
        self.isPriority = isPriority
        self.prefixTag = prefixTag
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
}
