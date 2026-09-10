import AppKit
import UtterclipCore
import SwiftUI
import os

/// Menu bar presence and the one window. Left-click on the status item is the whole
/// workflow: window hidden → it drops down under the icon and a dictation starts;
/// recording → it stops and the rewrite runs; window open and idle → it hides again.
/// Right-click shows a menu with the same commands the keyboard shortcuts offer, plus
/// Show/Hide, Float on Top and Quit (the only way to quit an app without a Dock tile).
@MainActor
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

    private static let pushLogger = Logger(subsystem: "com.ralfchille.utterclip", category: "push")
    private let syncNudger = SyncNudger()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        UserDefaults.standard.register(defaults: [Self.floatOnTopKey: true])
        // CloudKit tells us about the phone's changes through silent pushes; without this
        // registration the Mac only imported when it exported something itself.
        NSApp.registerForRemoteNotifications()
        // Pushes reach a Mac late or not at all often enough that the mirror needs a fallback:
        // a periodic sync nudge, paced by how likely the phone is to have news.
        syncNudger.start()

        let controller = MainWindowController(rootView: ContentView())
        controller.floatOnTop = floatOnTop
        windowController = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(named: "MenuBarIcon") // template: follows the menu bar's light/dark
            button.toolTip = "Utterclip — click to dictate, right-click for commands"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        // Launched deliberately (Finder, Spotlight, login item): show the window once, so a
        // first launch isn't "nothing happened". Closing it returns the app to the icon.
        showWindowOnceAnchored()
    }

    /// The status item only gets its place in the menu bar a few run-loop turns after it is
    /// created — until then its window reports a placeholder frame at the screen origin, and
    /// anchoring to that would pin the app window to the bottom-left corner. Wait (up to
    /// three seconds) for a frame that sits in a menu bar, then show the window under it.
    private func showWindowOnceAnchored(attempt: Int = 0) {
        if statusItemFrame != nil || attempt >= 60 {
            showWindow()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.showWindowOnceAnchored(attempt: attempt + 1)
            }
        }
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
            case "show":
                #if DEBUG
                showWindow() // the status-item click without the recording part
                #endif
            default:
                break
            }
        }
    }

    // MARK: - Window

    /// Brings the window forward; when the status item is on screen, right under its icon.
    func showWindow() {
        if let anchor = statusItemFrame {
            windowController?.show(under: anchor)
        } else {
            windowController?.show()
        }
    }

    /// The status item's frame in screen coordinates (it has its own little window), or nil
    /// until that frame actually sits in a screen's menu bar.
    private var statusItemFrame: NSRect? {
        guard let frame = statusItem?.button?.window?.frame, !frame.isEmpty,
              NSScreen.screens.contains(where: { screen in
                  screen.frame.intersects(frame) && frame.maxY > screen.frame.maxY - 40
              })
        else { return nil }
        return frame
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            statusItemPrimaryAction()
        }
    }

    // MARK: - Remote notifications (CloudKit change pushes)

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.pushLogger.notice("Registered for CloudKit pushes.")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Self.pushLogger.error("Push registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Core Data's mirroring imports on its own when a CloudKit push lands; a nudge makes sure
    /// the import happens even if it would otherwise wait for the next export.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Self.pushLogger.notice("CloudKit push received.")
        ActivitySync.touch()
    }

    /// Recording → stop it (the rewrite follows). Window in front, nothing running → hide it.
    /// Otherwise the click means "dictate": a hidden window is shown under the icon, a window
    /// buried behind other apps (only possible with Float on Top off) is brought forward, and
    /// in both cases recording starts right away.
    private func statusItemPrimaryAction() {
        guard let controller = windowController else { return }
        if RecordingState.isRecording {
            NotificationCenter.default.post(name: .utterclipToggleRecording, object: nil)
        } else if controller.isInFront {
            controller.hide()
        } else {
            if controller.isShowing {
                controller.show()
            } else {
                showWindow()
            }
            // The phone has a dictation on screen (finished or in progress): show that, no
            // recording — recording would replace it. Otherwise the click means "dictate".
            if let remote = ActivitySync.latestRemote(within: 30 * 60),
               remote.phase == "done" || remote.isInProgress {
                NotificationCenter.default.post(name: .utterclipShowRemote, object: nil)
            } else {
                ActivitySync.touch() // pull whatever the phone did since the last push
                NotificationCenter.default.post(name: .utterclipStartRecording, object: nil)
            }
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

    /// Visible *and* actually in front of the user: a floating window always is; a normal
    /// one only while it is the key window of the active app.
    var isInFront: Bool {
        guard let window, window.isVisible else { return false }
        return floatOnTop || (NSApp.isActive && window.isKeyWindow)
    }

    init(rootView: some View) {
        let hosting = NSHostingController(rootView: rootView)
        // The view draws its own header (title left, History/Settings right); no AppKit
        // toolbar or title bar chrome.
        hosting.sceneBridgingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Utterclip" // for the window list / accessibility; not drawn
        // Titled (so ⌘W and edge-resizing keep working) but with the bar invisible: no
        // traffic lights, no separator line, content running to the top edge.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.setContentSize(NSSize(width: 420, height: 720))
        window.contentMinSize = NSSize(width: 380, height: 600)
        window.isReleasedWhenClosed = false // hide on close; keep the view tree alive
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("Utterclip.main")
        if !window.setFrameUsingName("Utterclip.main") { window.center() }
        super.init(window: window)
        window.delegate = self
        applyLevel()
        WindowPresence.isVisible = false // shown under the status item once it has a frame
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        WindowPresence.isVisible = true
        NotificationCenter.default.post(name: .utterclipWindowDidShow, object: nil)
    }

    /// Shows the window centred under a menu bar item, kept within that screen. The size is
    /// whatever the user last resized it to; only the position moves.
    func show(under anchor: NSRect) {
        if let window,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            var frame = window.frame
            frame.origin.x = anchor.midX - frame.width / 2
            frame.origin.y = anchor.minY - frame.height - 6 // just below the menu bar
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = max(frame.origin.y, visible.minY)
            window.setFrame(frame, display: false)
        }
        show()
    }

    func hide() {
        window?.orderOut(nil)
        WindowPresence.isVisible = false
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

/// Keeps the Mac's copy of the synced store fresh when CloudKit pushes don't arrive. Each
/// nudge is one small save (this device's activity record), which makes Core Data run an
/// export cycle — and the import of the other devices' changes rides along. Cadence: every
/// 3 s while the phone is mid-dictation or its finished dictation is still on its way, 5 s
/// while the window is on screen, 30 s while hidden; never while this Mac is recording.
@MainActor
final class SyncNudger {
    private var timer: Timer?
    private var lastNudge = Date.distantPast

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard !RecordingState.isRecording else { return }
        let remote = ActivitySync.latestRemote()
        let remoteBusy = remote?.isInProgress == true || remote?.awaitsDictation == true
        let interval: TimeInterval = remoteBusy ? 3 : (WindowPresence.isVisible ? 5 : 30)
        guard Date().timeIntervalSince(lastNudge) >= interval else { return }
        lastNudge = .now
        ActivitySync.touch()
    }
}
