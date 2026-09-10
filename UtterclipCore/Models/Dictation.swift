import Foundation
import SwiftData

/// One finished dictation as stored by SwiftData and synced through CloudKit. The views
/// keep working with the value type `HistoryEntry`; `HistoryStore` converts between the two.
///
/// CloudKit rules shape this class: every stored property has a default or is optional,
/// there is no `@Attribute(.unique)` (uniqueness of `id` is by convention and enforced when
/// the store refreshes), and there are no relationships.
@Model
public final class Dictation {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var rawTranscript: String = ""
    public var styledText: String?
    public var styleID: String?
    /// Which install dictated it (`DeviceIdentity.id`); the Mac mirrors dictations from others.
    public var originDevice: String?

    public init(id: UUID = UUID(), date: Date = .now, rawTranscript: String, styledText: String? = nil, styleID: String? = nil, originDevice: String? = nil) {
        self.id = id
        self.date = date
        self.rawTranscript = rawTranscript
        self.styledText = styledText
        self.styleID = styleID
        self.originDevice = originDevice
    }

    var entry: HistoryEntry {
        HistoryEntry(id: id, date: date, rawTranscript: rawTranscript, styledText: styledText, styleID: styleID, originDevice: originDevice)
    }
}
