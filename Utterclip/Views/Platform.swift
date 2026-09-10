import SwiftUI
import UtterclipCore

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

    /// Buttons in a sheet's bar. On macOS the semantic placements put them where a sheet
    /// expects them and wire Return (confirm) and Escape (cancel) for free.
    static var sheetConfirm: ToolbarItemPlacement {
        #if os(macOS)
        .confirmationAction
        #else
        .topBarTrailing
        #endif
    }

    static var sheetCancel: ToolbarItemPlacement {
        #if os(macOS)
        .cancellationAction
        #else
        .topBarTrailing
        #endif
    }

    static var sheetDestructive: ToolbarItemPlacement {
        #if os(macOS)
        .destructiveAction
        #else
        .topBarLeading
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

    /// The Mac window hides its title bar but SwiftUI still reserves its height as a safe
    /// area; the header row takes that space instead. No-op on iOS.
    @ViewBuilder
    func ignoreHiddenTitleBar() -> some View {
        #if os(macOS)
        ignoresSafeArea(.container, edges: .top)
        #else
        self
        #endif
    }

    /// Breathing room between the Mac header and the editor text; iOS already has that gap.
    @ViewBuilder
    func editorTopInset() -> some View {
        #if os(macOS)
        padding(.top, 8)
        #else
        self
        #endif
    }

    /// History and Settings: a sheet on iOS; on the Mac they open in place, pushed inside the
    /// window's navigation stack, so the compact window never spawns a second one.
    @ViewBuilder
    func panel<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(macOS)
        navigationDestination(isPresented: isPresented, destination: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// The text editor takes the whole screen on iOS; on macOS it opens in place inside the
    /// window, like History and Settings.
    @ViewBuilder
    func editorPresentation<Item: Identifiable & Hashable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        navigationDestination(item: item, destination: content)
        #else
        fullScreenCover(item: item, content: content)
        #endif
    }
}

#if os(macOS)
/// The Mac's replacement for a navigation bar, used by the main window and every sheet:
/// title flush with the content margin on the left, actions on the right, no lines.
struct MacHeader<Actions: View>: View {
    let title: String
    var back: (() -> Void)? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 2) { // the button style adds the breathing room
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
                .keyboardShortcut(.cancelAction)
            }
            Text(title)
                .font(.headline)
            Spacer()
            actions
        }
        .font(.system(size: 17, weight: .medium))
        .buttonStyle(HeaderActionButtonStyle())
        .foregroundStyle(.primary)
        .padding(.leading, 20)
        .padding(.trailing, 8) // the buttons carry 6 pt of their own; glyph edges stay ~20 pt in
        .padding(.top, 6) // the 36 pt buttons give the row its height; keep the title where it was
        .padding(.bottom, 0)
    }
}

/// Header buttons are small glyphs; give each a comfortable 36-point target and a light
/// pressed state, so a click a few points off the mark still lands.
struct HeaderActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
#endif

extension View {
    /// iOS: inline navigation title plus the bar items. macOS: no system bar at all — the
    /// view draws a `MacHeader` instead — so the window toolbar is hidden.
    @ViewBuilder
    func barChrome<T: ToolbarContent>(title: String, @ToolbarContentBuilder toolbar: () -> T) -> some View {
        #if os(macOS)
        self.toolbar(.hidden, for: .windowToolbar)
        #else
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: toolbar)
        #endif
    }

    /// Same as `barChrome(title:toolbar:)` for a page with no bar items of its own.
    @ViewBuilder
    func barTitle(_ title: String) -> some View {
        #if os(macOS)
        self.toolbar(.hidden, for: .windowToolbar)
        #else
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Mac list rows line up with the `MacHeader` margin; iOS keeps the system insets.
    @ViewBuilder
    func headerAlignedRow() -> some View {
        #if os(macOS)
        listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) // + the list's own 8 pt = the 20 pt header margin
        #else
        self
        #endif
    }

    /// Hairline row separators on macOS, where the default ones read heavy against the
    /// otherwise monochrome sheets. iOS keeps the system look.
    @ViewBuilder
    func subtleSeparators() -> some View {
        #if os(macOS)
        listRowSeparatorTint(Color.primary.opacity(0.08))
        #else
        self
        #endif
    }
}

/// The root of History and Settings. iOS presents them as sheets, each with its own
/// navigation stack; on the Mac they are pushed inside the window's stack and must not nest
/// another one (their NavigationLinks push onto the window's stack instead).
struct SheetNavigation<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        content
        #else
        NavigationStack { content }
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

    /// Settings footer under the style list; there is no swipe on a Mac.
    static var stylesFooter: String {
        #if os(macOS)
        "Click a style to edit its name and instructions, or delete it from its editor. Deleted defaults can be restored. Up to \(maxStyles) styles."
        #else
        "Tap a style to edit its name and instructions; swipe to delete. Deleted defaults can be restored. Up to \(maxStyles) styles."
        #endif
    }
    private static let maxStyles = StyleStore.maxStyles

    /// "…on your iPhone" / "…on this Mac" for the Apple Intelligence hints.
    static var deviceName: String {
        #if os(macOS)
        "this Mac"
        #else
        "your iPhone"
        #endif
    }
}

/// What the AppKit side (status item) needs to know about the recorder without owning the
/// view model: is a recording running right now. `ContentView` keeps it current.
enum RecordingState {
    @MainActor static var isRecording = false
}

/// App-level commands (menu items and keyboard shortcuts on macOS) reach the main view
/// through notifications, so the view owns the view model and the scene owns the menus.
extension Notification.Name {
    static let utterclipToggleRecording = Notification.Name("utterclip.toggleRecording")
    /// Start only (never stop): the URL scheme's meaning on both platforms.
    static let utterclipStartRecording = Notification.Name("utterclip.startRecording")
    static let utterclipContinueRecording = Notification.Name("utterclip.continueRecording")
    static let utterclipShowHistory = Notification.Name("utterclip.showHistory")
    static let utterclipShowSettings = Notification.Name("utterclip.showSettings")
}

/// Text roles whose size differs between the platforms: the Mac window is denser, so its
/// history rows read at body size while the raw transcript steps down to caption
/// (matched to the Figma spec, page "Mac app"); iOS keeps callout for both.
enum PlatformFont {
    #if os(macOS)
    static let historyTranscript: Font = .body
    static let rawTranscript: Font = .caption
    #else
    static let historyTranscript: Font = .callout
    static let rawTranscript: Font = .callout
    #endif
}
