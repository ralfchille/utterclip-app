import CloudKit
import Foundation
import Observation

/// What Settings shows next to the iCloud switch: whether this device has an iCloud account
/// CloudKit can use. Asked of CloudKit directly — the iCloud Drive identity token is nil on
/// devices where iCloud Drive is switched off (by the user or by a management profile),
/// while CloudKit and iCloud Keychain keep working there.
@Observable
@MainActor
public final class SyncStatus {
    public static let shared = SyncStatus()

    /// nil while the check is in flight.
    public private(set) var accountAvailable: Bool?

    private init() {
        refresh()
    }

    public func refresh() {
        Task { @MainActor in
            let status = try? await CKContainer(identifier: SyncPreference.containerIdentifier).accountStatus()
            accountAvailable = status == .available
        }
    }
}
