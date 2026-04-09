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

    init(
        id: UUID = UUID(),
        date: Date?,
        rawHeader: String?,
        entries: [StreamEntry] = []
    ) {
        self.id = id
        self.date = date
        self.rawHeader = rawHeader
        self.entries = entries
    }
}
