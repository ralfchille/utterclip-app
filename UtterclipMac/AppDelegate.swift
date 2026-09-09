import AppKit
import SwiftUI

/// Menu bar presence and the one window. Left-click on the status item toggles the window;
/// right-click shows a menu with the same commands the keyboard shortcuts offer, plus
/// Float on Top and Quit (the only way to quit an app without a Dock tile).
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var windowController: MainWindowController?

    /// Window level preference; on by default because the whole point of the Mac version
    /// is to dictate into another app without hunting for this window.
    private static let floatOnTopKey = "floatOnTop"
    private var floatOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: Self.floatOnTopKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.floatOnTopKey); windowController?.floatOnTop = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        UserDefaults.standard.register(defaults: [Self.floatOnTopKey: true])

        let controller = MainWindowController(rootView: ContentView())
        controller.floatOnTop = floatOnTop
        windowController = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(named: "MenuBarIcon") // template: follows the menu bar's light/dark
            button.toolTip = "Utterclip — click to open, right-click for commands"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        // Launched deliberately (Finder, Spotlight, login item): show the window once, so a
        // first launch isn't "nothing happened". Closing it returns the app to the icon.
        showWindow()
    }

    /// Menu-bar apps keep running with no windows; that is the point.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Re-launching from Finder/Spotlight while running brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// `utterclip://record` from a launcher or automation; `utterclip://snapshot` in Debug.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host {
            case "record":
                AppCommand.startRecording.perform()
            case "snapshot":
                #if DEBUG
                DebugSnapshot.handle(url)
                #endif
            default:
                break
            }
        }
    }

    // MARK: - Window

    func showWindow() {
        windowController?.show()
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            windowController?.toggle()
        }
    }

    /// The menu is attached only for the duration of the click, so a plain left-click keeps
    /// toggling the window instead of opening the menu.
    private func showStatusMenu() {
        guard let item = statusItem else { return }
        item.menu = buildStatusMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            menu.addItem(item)
        }
        add("Start / Stop Dictation", "r", .command, #selector(menuToggleRecording))
        add("Continue Dictating", "r", [.command, .shift], #selector(menuContinueRecording))
        menu.addItem(.separator())
        add(windowController?.isShowing == true ? "Hide Utterclip" : "Show Utterclip", "", [], #selector(menuToggleWindow))
        add("History…", "y", .command, #selector(menuShowHistory))
        add("Settings…", ",", .command, #selector(menuShowSettings))
        menu.addItem(.separator())
        let float = NSMenuItem(title: "Float on Top", action: #selector(menuToggleFloat), keyEquivalent: "t")
        float.keyEquivalentModifierMask = [.command, .option]
        float.state = floatOnTop ? .on : .off
        float.target = self
        menu.addItem(float)
        menu.addItem(.separator())
        add("Quit Utterclip", "q", .command, #selector(menuQuit))
        return menu
    }

    @objc private func menuToggleRecording() { AppCommand.toggleRecording.perform() }
    @objc private func menuContinueRecording() { AppCommand.continueRecording.perform() }
    @objc private func menuToggleWindow() { windowController?.toggle() }
    @objc private func menuShowHistory() { AppCommand.showHistory.perform() }
    @objc private func menuShowSettings() { AppCommand.showSettings.perform() }
    @objc private func menuToggleFloat() { floatOnTop.toggle() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}

/// The app's single window: 420 × 720 by default, resizable down to 380 × 600, floating
/// above other apps when asked, and never actually closed — the close button hides it, the
/// status item brings it back, and the SwiftUI view inside keeps its state meanwhile.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    var floatOnTop = true {
        didSet { applyLevel() }
    }

    var isShowing: Bool { window?.isVisible == true }

    init(rootView: some View) {
        let hosting = NSHostingController(rootView: rootView)
        // Let the SwiftUI toolbar (History, Settings) and navigation title drive the window.
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unifiedCompact
        window.setContentSize(NSSize(width: 420, height: 720))
        window.contentMinSize = NSSize(width: 380, height: 600)
        window.isReleasedWhenClosed = false // hide on close; keep the view tree alive
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("Utterclip.main")
        if !window.setFrameUsingName("Utterclip.main") { window.center() }
        super.init(window: window)
        window.delegate = self
        applyLevel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Status-item click: hide if the window is up and in front, otherwise bring it forward.
    func toggle() {
        if isShowing, NSApp.isActive {
            hide()
        } else {
            show()
        }
    }

    /// The red close button hides instead of closing, which is what "back to the menu bar"
    /// means for a status-item app.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func applyLevel() {
        guard let window else { return }
        window.level = floatOnTop ? .floating : .normal
        // A floating utility follows the user to other Spaces and stays visible over
        // full-screen apps; a normal window behaves like any other document window.
        let utilityBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if floatOnTop {
            window.collectionBehavior.insert(utilityBehavior)
        } else {
            window.collectionBehavior.remove(utilityBehavior)
        }
    }
}
