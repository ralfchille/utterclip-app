import Foundation

/// Whether history, styles and the API key follow the user through iCloud. On by default;
/// the Settings toggle (plan phase 5) turns it off. Read at launch by the stores — changing
/// it takes effect on the next launch, which the Settings footer says.
public enum SyncPreference {
    public static let key = "iCloudSync"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The CloudKit container both apps share.
    public static let containerIdentifier = "iCloud.com.ralfchille.voicer"

    /// An iCloud account is signed in on this device (CloudKit and the key-value store
    /// need one; without it everything stays local, silently).
    public static var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
