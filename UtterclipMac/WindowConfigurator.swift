import AppKit
import SwiftUI

/// Reaches the `NSWindow` behind the SwiftUI scene to set what SwiftUI has no modifier
/// for: the window level. `.floating` keeps the window above other apps' windows even
/// while Utterclip is not the active app, which is how it is meant to be used — pinned
/// beside Slack, Mail or a browser while you dictate into them.
struct WindowConfigurator: NSViewRepresentable {
    var floatOnTop: Bool

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.onWindow = { Self.apply(floatOnTop: floatOnTop, to: $0) }
        return view
    }

    func updateNSView(_ view: WindowObservingView, context: Context) {
        view.onWindow = { Self.apply(floatOnTop: floatOnTop, to: $0) }
        if let window = view.window { Self.apply(floatOnTop: floatOnTop, to: window) }
    }

    private static func apply(floatOnTop: Bool, to window: NSWindow) {
        window.level = floatOnTop ? .floating : .normal
        // A floating utility follows the user to other Spaces and stays visible over
        // full-screen apps; a normal window behaves like any other document window.
        let utilityBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if floatOnTop {
            window.collectionBehavior.insert(utilityBehavior)
        } else {
            window.collectionBehavior.remove(utilityBehavior)
        }
        window.isMovableByWindowBackground = true
    }
}

/// Invisible view that reports when it lands in a window — the only reliable moment to
/// configure that window (during `makeNSView` there is none yet).
final class WindowObservingView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow?(window) }
    }
}
