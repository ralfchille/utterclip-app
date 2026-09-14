import CoreText
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The one typeface in the app that is ours rather than Apple's.
///
/// It sets two things and no more: the rewritten text — what you actually read, edit and copy —
/// and the wordmark. Everything else stays on the system font, which is better at 10 pt, lines
/// up with SF Symbols, and scales with Dynamic Type without being asked. Schibsted Grotesk sits
/// within 0.1 pt of SF Pro Text's x-height at any size, so the type sizes and line heights
/// around it did not have to move.
enum IdentityFont {
    /// Weights the app actually uses. The file carries 400 to 900; these are the four that
    /// appear, and each maps to a named instance inside the variable font.
    enum Weight {
        case regular, medium, semibold, bold

        var postScriptName: String {
            switch self {
            case .regular:  "SchibstedGrotesk-Regular"
            case .medium:   "SchibstedGrotesk-Regular_Medium"
            case .semibold: "SchibstedGrotesk-Regular_SemiBold"
            case .bold:     "SchibstedGrotesk-Regular_Bold"
            }
        }

        #if os(macOS)
        var system: NSFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
        #else
        var system: UIFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
        #endif
    }

    static let family = "Schibsted Grotesk"

    /// Registered from the bundle rather than declared in an Info.plist key, because the key
    /// differs per platform and depends on where the file lands in the bundle. This does not.
    /// Safe to call more than once.
    static func register() {
        guard !isAvailable else { return }
        var urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        urls += Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls where url.lastPathComponent.hasPrefix("SchibstedGrotesk") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// False if the font did not register — a build with the resource missing keeps working,
    /// on the system font, rather than falling back to something arbitrary.
    static var isAvailable: Bool {
        #if os(macOS)
        NSFont(name: Weight.regular.postScriptName, size: 12) != nil
        #else
        UIFont(name: Weight.regular.postScriptName, size: 12) != nil
        #endif
    }

    /// `relativeTo` is what keeps Dynamic Type working: the size scales with the user's
    /// setting exactly as a semantic style would.
    static func text(size: CGFloat, weight: Weight = .regular, relativeTo style: Font.TextStyle) -> Font {
        isAvailable
            ? .custom(weight.postScriptName, size: size, relativeTo: style)
            : .system(size: size, weight: swiftUIWeight(weight))
    }

    private static func swiftUIWeight(_ weight: Weight) -> Font.Weight {
        switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    #if os(macOS)
    static func nsFont(size: CGFloat, weight: Weight = .regular) -> NSFont {
        NSFont(name: weight.postScriptName, size: size) ?? .systemFont(ofSize: size, weight: weight.system)
    }
    #else
    static func uiFont(size: CGFloat, weight: Weight = .regular) -> UIFont {
        UIFont(name: weight.postScriptName, size: size) ?? .systemFont(ofSize: size, weight: weight.system)
    }
    #endif
}
