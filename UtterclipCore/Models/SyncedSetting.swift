import Foundation
import SwiftData

/// One preference that follows the user: the `UserDefaults` key, its value as a property
/// list, and when it was last set (newest wins when two devices disagree). Stored in the
/// CloudKit-backed store next to the dictations. Same CloudKit rules as `Dictation`:
/// defaults for every property, no uniqueness constraint (duplicates by key are collapsed on
/// read), no relationships.
@Model
public final class SyncedSetting {
    public var key: String = ""
    public var value: Data?
    public var updatedAt: Date = Date()

    public init(key: String, value: Data?, updatedAt: Date = .now) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}
