import SwiftUI

// The views are shared by the iPhone app and the Mac app. Everything that differs
// between the two platforms is funneled through this file, so the views themselves
// read the same on both and the `#if os(...)` noise lives in one place.

extension Color {
    /// The window/screen background: `systemBackground` on iOS, the window color on macOS.
    static var appBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    /// Flat fill for an unselected pill (the iOS `systemGray6`).
    static var pillFill: Color {
        #if os(macOS)
        Color.primary.opacity(0.07)
        #else
        Color(.systemGray6)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Leading/trailing bar buttons: the iOS navigation-bar slots, or the closest macOS
    /// toolbar slots (navigation area / primary action).
    static var barLeading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    static var barTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
}

extension View {
    /// Small inline navigation title on iOS; macOS has no such mode.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// iOS-only text input hints; macOS text fields have no autocapitalization.
    @ViewBuilder
    func autocapitalizationNever() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.never)
        #endif
    }

    @ViewBuilder
    func autocapitalizationWords() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.words)
        #endif
    }

    /// iOS forms are grouped by default; macOS needs to be told, or it renders a flat
    /// column of controls.
    @ViewBuilder
    func groupedFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    /// macOS sheets size to their content and would otherwise come up tiny; iOS sheets
    /// fill the screen and ignore this.
    @ViewBuilder
    func sheetFrame(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: minWidth, minHeight: minHeight, idealHeight: minHeight)
        #else
        self
        #endif
    }

    /// The text editor takes the whole screen on iOS; on macOS it is a sheet.
    @ViewBuilder
    func editorPresentation<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item, content: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }
}

/// Wording that names the input device.
enum PlatformText {
    /// The idle-screen hint.
    static var readyHint: String {
        #if os(macOS)
        "Click the mic, speak, click again.\nYour words land on the clipboard."
        #else
        "Tap the mic, speak, tap again.\nYour words land on the clipboard."
        #endif
    }

    /// "…on your iPhone" / "…on this Mac" for the Apple Intelligence hints.
    static var deviceName: String {
        #if os(macOS)
        "this Mac"
        #else
        "your iPhone"
        #endif
    }
}

/// App-level commands (menu items and keyboard shortcuts on macOS) reach the main view
/// through notifications, so the view owns the view model and the scene owns the menus.
extension Notification.Name {
    static let utterclipToggleRecording = Notification.Name("utterclip.toggleRecording")
    static let utterclipContinueRecording = Notification.Name("utterclip.continueRecording")
    static let utterclipShowHistory = Notification.Name("utterclip.showHistory")
    static let utterclipShowSettings = Notification.Name("utterclip.showSettings")
}
