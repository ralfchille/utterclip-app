import Foundation

/// One finished dictation: the raw transcript plus the latest styled result.
/// Styled text tracks whatever rewrite or edit the entry ended up with.
public struct HistoryEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    public let date: Date
    public var rawTranscript: String
    public var styledText: String?
    public var styleID: String?
    /// `DeviceIdentity.id` of the device that dictated it (nil for 1.0 entries).
    public var originDevice: String? = nil

    public init(id: UUID = UUID(), date: Date = .now, rawTranscript: String, styledText: String? = nil,
                styleID: String? = nil, originDevice: String? = nil) {
        self.id = id
        self.date = date
        self.rawTranscript = rawTranscript
        self.styledText = styledText
        self.styleID = styleID
        self.originDevice = originDevice
    }
}
