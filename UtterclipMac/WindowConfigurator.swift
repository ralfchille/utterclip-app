import AppKit
import SwiftUI
import os

/// Reaches the `NSWindow` behind the SwiftUI scene to set what SwiftUI has no modifier
/// for: the window level. `.floating` keeps the window above other apps' windows even
/// while Utterclip is not the active app, which is how it is meant to be used — pinned
/// beside Slack, Mail or a browser while you dictate into them.
struct WindowConfigurator: NSViewRepresentable {
    var floatOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = floatOnTop ? .floating : .normal
        // Follow the user to other Spaces and stay visible over full-screen apps, like
        // a utility panel; without this a floating window is left behind on its Space.
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.isMovableByWindowBackground = true
        Self.logger.info("window configured: level=\(window.level.rawValue, privacy: .public) frame=\(NSStringFromRect(window.frame), privacy: .public) visible=\(window.isVisible, privacy: .public)")
    }

    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "window")
}
