#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `open "utterclip://snapshot"` makes the app write a PNG of its own
/// window to `<container>/tmp/snapshot.png`, for a tool without Screen Recording permission
/// (or a CI job). Caveat: the offline render cannot draw compositor-only content — Liquid
/// Glass views and animated indicators come out blank — so treat it as a layout check,
/// not a pixel-true screenshot. Compiled out of Release builds.
struct DebugSnapshot: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard url.host == "snapshot" else { return }
            NSApp.activate(ignoringOtherApps: true) // render as the active window
            // utterclip://snapshot?show=settings|history opens that sheet first, so the
            // sheets can be checked the same way as the main window.
            let show = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "show" })?.value
            switch show {
            case "settings": NotificationCenter.default.post(name: .utterclipShowSettings, object: nil)
            case "history": NotificationCenter.default.post(name: .utterclipShowHistory, object: nil)
            default: break
            }
            // Let the window settle (sheet animations, layout) before drawing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { Self.write() }
        }
    }

    private static func write() {
        // Remove last time's image first, so a failed render can't pass for a fresh one.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot.png")
        try? FileManager.default.removeItem(at: url)
        // A presented sheet wins; otherwise the main window.
        let visible = NSApp.windows.filter(\.isVisible)
        guard let window = visible.first(where: \.isSheet) ?? visible.first(where: { $0.title == "Utterclip" }),
              let view = window.contentView?.superview ?? window.contentView, // frame view: title bar included
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)

    }
}

extension View {
    func debugSnapshot() -> some View { modifier(DebugSnapshot()) }
}
#endif
