import UIKit

/// UIPasteboard wrapper (plan Phase 4).
enum Clipboard {
    static func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}
