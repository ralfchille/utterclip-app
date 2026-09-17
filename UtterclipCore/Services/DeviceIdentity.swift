import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Who this install is, for telling devices apart in the synced store. The id is minted once
/// per install and never leaves the device except inside the user's own iCloud records.
public enum DeviceIdentity {
    private static let key = "deviceIdentity"

    public static let id: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }()

    /// What to call this device on the other one: "iPhone", "iPad" or "Mac".
    public static var kind: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}
