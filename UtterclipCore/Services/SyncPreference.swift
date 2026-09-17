import Foundation

/// Whether history, styles and the API key follow the user through iCloud. On by default;
/// the Settings toggle turns it off. The stores read it at launch — changing it takes effect
/// for history and settings on the next launch (the Settings footer says so); the API key
/// follows immediately.
public enum SyncPreference {
    public static let key = "iCloudSync"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The CloudKit container both apps share.
    public static let containerIdentifier = "iCloud.com.ralfchille.voicer"
}
