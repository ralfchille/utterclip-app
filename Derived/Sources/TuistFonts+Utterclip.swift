// swiftlint:disable:this file_name
// swiftlint:disable all
// swift-format-ignore-file
// swiftformat:disable all
// Generated using tuist — https://github.com/tuist/tuist

#if os(macOS)
  import AppKit.NSFont
#elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  import UIKit.UIFont
#endif
#if canImport(SwiftUI)
  import SwiftUI
#endif

// swiftlint:disable superfluous_disable_command
// swiftlint:disable file_length

// MARK: - Fonts

// swiftlint:disable identifier_name line_length type_body_length
public enum UtterclipFontFamily: Sendable {
  public enum SchibstedGrotesk: Sendable {
    public static let italic = UtterclipFontConvertible(name: "SchibstedGrotesk-Italic", family: "Schibsted Grotesk", path: "SchibstedGrotesk-Italic[wght].ttf")
    public static let blackItalic = UtterclipFontConvertible(name: "SchibstedGrotesk-Italic_Black-Italic", family: "Schibsted Grotesk", path: "SchibstedGrotesk-Italic[wght].ttf")
    public static let boldItalic = UtterclipFontConvertible(name: "SchibstedGrotesk-Italic_Bold-Italic", family: "Schibsted Grotesk", path: "SchibstedGrotesk-Italic[wght].ttf")
    public static let extraBoldItalic = UtterclipFontConvertible(name: "SchibstedGrotesk-Italic_ExtraBold-Italic", family: "Schibsted Grotesk", path: "SchibstedGrotesk-Italic[wght].ttf")
    public static let mediumItalic = UtterclipFontConvertible(name: "SchibstedGrotesk-Italic_Medium-Italic", family: "Schibsted Grotesk", path: "SchibstedGrotesk-Italic[wght].ttf")
    public static let semiBoldItalic = UtterclipFontConvertible(name: "SchibstedGrotesk-Italic_SemiBold-Italic", family: "Schibsted Grotesk", path: "SchibstedGrotesk-Italic[wght].ttf")
    public static let regular = UtterclipFontConvertible(name: "SchibstedGrotesk-Regular", family: "Schibsted Grotesk", path: "SchibstedGrotesk[wght].ttf")
    public static let black = UtterclipFontConvertible(name: "SchibstedGrotesk-Regular_Black", family: "Schibsted Grotesk", path: "SchibstedGrotesk[wght].ttf")
    public static let bold = UtterclipFontConvertible(name: "SchibstedGrotesk-Regular_Bold", family: "Schibsted Grotesk", path: "SchibstedGrotesk[wght].ttf")
    public static let extraBold = UtterclipFontConvertible(name: "SchibstedGrotesk-Regular_ExtraBold", family: "Schibsted Grotesk", path: "SchibstedGrotesk[wght].ttf")
    public static let medium = UtterclipFontConvertible(name: "SchibstedGrotesk-Regular_Medium", family: "Schibsted Grotesk", path: "SchibstedGrotesk[wght].ttf")
    public static let semiBold = UtterclipFontConvertible(name: "SchibstedGrotesk-Regular_SemiBold", family: "Schibsted Grotesk", path: "SchibstedGrotesk[wght].ttf")
    public static let all: [UtterclipFontConvertible] = [italic, blackItalic, boldItalic, extraBoldItalic, mediumItalic, semiBoldItalic, regular, black, bold, extraBold, medium, semiBold]
  }
  public static let allCustomFonts: [UtterclipFontConvertible] = [SchibstedGrotesk.all].flatMap { $0 }
  public static func registerAllCustomFonts() {
    allCustomFonts.forEach { $0.register() }
  }
}
// swiftlint:enable identifier_name line_length type_body_length

// MARK: - Implementation Details

public struct UtterclipFontConvertible: Sendable {
  public let name: String
  public let family: String
  public let path: String

  #if os(macOS)
  public typealias Font = NSFont
  #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  public typealias Font = UIFont
  #endif

  public func font(size: CGFloat) -> Font {
    guard let font = Font(font: self, size: size) else {
      fatalError("Unable to initialize font '\(name)' (\(family))")
    }
    return font
  }

  #if canImport(SwiftUI)
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
  public func swiftUIFont(size: CGFloat) -> SwiftUI.Font {
    guard let font = Font(font: self, size: size) else {
      fatalError("Unable to initialize font '\(name)' (\(family))")
    }
    #if os(macOS)
    return SwiftUI.Font.custom(font.fontName, size: font.pointSize)
    #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    return SwiftUI.Font(font)
    #endif
  }
  #endif

  public func register() {
    // swiftlint:disable:next conditional_returns_on_newline
    guard let url = url else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }

  fileprivate var url: URL? {
    // swiftlint:disable:next implicit_return
    return Bundle.module.url(forResource: path, withExtension: nil)
  }
}

public extension UtterclipFontConvertible.Font {
  convenience init?(font: UtterclipFontConvertible, size: CGFloat) {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    if !UIFont.fontNames(forFamilyName: font.family).contains(font.name) {
      font.register()
    }
    #elseif os(macOS)
    if let url = font.url, CTFontManagerGetScopeForURL(url as CFURL) == .none {
      font.register()
    }
    #endif

    self.init(name: font.name, size: size)
  }
}
// swiftformat:enable all
// swiftlint:enable all
