import Foundation

/// One day's worth of stream entries, anchored at the day separator
/// `--- YYYY-MM-DD Weekday ---` from stream.md.
struct StreamSection: Identifiable, Hashable {
    let id: UUID
    /// The parsed calendar date for the separator. Nil for the implicit
    /// "no separator yet" bucket at the very top of a malformed file.
    var date: Date?
    /// The original separator line, preserved verbatim so we can round-trip.
    var rawHeader: String?
    var entries: [StreamEntry]
    /// True for sections sourced from outside `stream.md` (e.g. the
    /// "FROM ARCHIVE" search bucket). The UI suppresses mutation
    /// affordances on these so a click-to-rescue or context-menu edit
    /// can't try to mutate a file we don't own.
    var isReadOnly: Bool

    init(
        id: UUID = UUID(),
        date: Date?,
        rawHeader: String?,
        entries: [StreamEntry] = [],
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.date = date
        self.rawHeader = rawHeader
        self.entries = entries
        self.isReadOnly = isReadOnly
    }
}
