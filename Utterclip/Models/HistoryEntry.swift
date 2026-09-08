import Foundation

/// One finished dictation: the raw transcript plus the latest styled result.
/// Styled text tracks whatever rewrite or edit the entry ended up with.
struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    var rawTranscript: String
    var styledText: String?
    var styleID: String?
}
