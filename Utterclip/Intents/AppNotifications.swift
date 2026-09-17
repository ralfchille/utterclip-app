import Foundation

/// App-level commands (menu items and keyboard shortcuts on macOS, the Action button and the
/// widget on iOS) reach the main view through notifications, so the view owns the view model
/// and the scene owns the menus.
///
/// They live beside the intents rather than with the views because the widget extension is
/// built from this folder and gets no views — the record intent posts one of these.
extension Notification.Name {
    static let utterclipToggleRecording = Notification.Name("utterclip.toggleRecording")
    /// Start only (never stop): the URL scheme's meaning on both platforms.
    static let utterclipStartRecording = Notification.Name("utterclip.startRecording")
    static let utterclipContinueRecording = Notification.Name("utterclip.continueRecording")
    static let utterclipShowHistory = Notification.Name("utterclip.showHistory")
    static let utterclipShowSettings = Notification.Name("utterclip.showSettings")
    #if DEBUG
    /// Debug builds only: puts a fixed result on screen without dictating one, so a layout
    /// question can be looked at the same way twice. See `DebugSeed`.
    static let utterclipDebugResult = Notification.Name("utterclip.debugResult")
    #endif
}
