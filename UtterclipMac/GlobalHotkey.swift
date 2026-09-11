import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut that starts a dictation from whatever app you are in.
///
/// Carbon's `RegisterEventHotKey` is the only API that does this without Accessibility
/// permission and from inside the sandbox: the system delivers the key to us, we never watch
/// the keyboard. `NSEvent.addGlobalMonitorForEvents` would see every keystroke and demands
/// Input Monitoring for it — far too much for one shortcut.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// What the shortcut does when pressed. Set once at launch.
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    /// 'UTRC' — so the handler ignores hotkeys registered by anything else in this process.
    private static let signature = OSType(0x5554_5243)

    private init() {}

    /// One of the offered chords, or nil for "off". Registering replaces any previous one.
    func register(_ shortcut: Shortcut?) {
        unregister()
        guard let shortcut else { return }
        installHandler()
        var id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers),
            id, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil } // taken by another app; the menu bar still works
        _ = id
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Registered once for the process; the handler outlives individual shortcuts.
    private func installHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.signature == GlobalHotkey.signature else { return noErr }
            Task { @MainActor in GlobalHotkey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    /// The chords on offer. Deliberately a short list of combinations macOS itself leaves
    /// alone, rather than a recorder that lets you shadow ⌘C.
    enum Shortcut: String, CaseIterable, Identifiable {
        case controlOptionCommandSpace, optionSpace, controlOptionSpace, controlOptionCommandD

        var id: String { rawValue }

        var keyCode: Int {
            switch self {
            case .controlOptionCommandD: kVK_ANSI_D
            default: kVK_Space
            }
        }

        var carbonModifiers: Int {
            switch self {
            case .controlOptionCommandSpace, .controlOptionCommandD: controlKey | optionKey | cmdKey
            case .optionSpace: optionKey
            case .controlOptionSpace: controlKey | optionKey
            }
        }

        var label: String {
            switch self {
            case .controlOptionCommandSpace: "⌃⌥⌘Space"
            case .optionSpace: "⌥Space"
            case .controlOptionSpace: "⌃⌥Space"
            case .controlOptionCommandD: "⌃⌥⌘D"
            }
        }
    }
}
