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
            // Let the window settle (sheet animations, layout) before drawing.
            NSApp.activate(ignoringOtherApps: true) // render as the active window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Self.write() }
        }
    }

    private static func write() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Utterclip" }) ?? NSApp.keyWindow,
              let view = window.contentView?.superview ?? window.contentView, // frame view: title bar included
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot.png")
        try? png.write(to: url, options: .atomic)

    }
}

extension View {
    func debugSnapshot() -> some View { modifier(DebugSnapshot()) }
}
#endif
