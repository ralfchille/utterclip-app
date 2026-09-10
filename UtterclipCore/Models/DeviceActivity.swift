import Foundation
import SwiftData

/// What one device is doing right now — recording, transcribing, rewriting, done or idle —
/// one record per device, updated in place, synced like everything else in the store. The
/// Mac reads the other devices' records to mirror a dictation happening on the phone.
/// Same CloudKit rules as `Dictation`: defaults for every property, no uniqueness constraint
/// (duplicates by device collapse when written), no relationships.
@Model
public final class DeviceActivity {
    public var deviceID: String = ""
    public var deviceName: String = ""
    public var phase: String = "idle"
    /// The dictation a `done` phase refers to, so the reader can pair the two records.
    public var dictationID: UUID?
    public var updatedAt: Date = Date()

    public init(deviceID: String, deviceName: String, phase: String = "idle", dictationID: UUID? = nil, updatedAt: Date = .now) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.phase = phase
        self.dictationID = dictationID
        self.updatedAt = updatedAt
    }
}
