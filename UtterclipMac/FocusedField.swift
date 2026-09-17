import AppKit
import ApplicationServices
import os

/// Where the text cursor is in the app you are typing in, so the window can open next to it
/// instead of wherever it last sat.
///
/// This needs Accessibility permission — it is the only way to ask another app what its
/// focused element is. Without it (or when the focus is not a text field) the caller falls
/// back to the pointer, which is usually close enough.
@MainActor
enum FocusedField {
    /// True once the user has granted Accessibility access in System Settings.
    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility access, opening System Settings at the right pane.
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// The caret (or the whole field, if the caret has no bounds) in Cocoa screen
    /// coordinates. Nil when access is missing or the focus is not a text input.
    static func caretRect() -> CGRect? {
        guard isAllowed else { return nil }
        enableAccessibilityForFrontmostApp()
        guard let element = focusedElement() else { return nil }

        // Behaviour first, role second. Gating on the role rejected anything that names
        // itself unusually — an Electron composer among them — even though it answers every
        // text question correctly. Carrying a selected text range is the honest test.
        var rangeValue: CFTypeRef?
        let hasSelection = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""
        let textRoles: Set<String> = [
            kAXTextFieldRole as String, kAXTextAreaRole as String,
            kAXComboBoxRole as String, "AXSearchField", "AXWebArea", "AXTextView",
        ]
        guard hasSelection || textRoles.contains(role) else {
            logger.notice("Focused element is not a text input (role \(role, privacy: .public)).")
            return nil
        }

        // The caret: the bounds of the (empty) selected range.
        if hasSelection, let range = rangeValue {
            var boundsValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue) == .success,
               let bounds = boundsValue, CFGetTypeID(bounds) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(unsafeBitCast(bounds, to: AXValue.self), .cgRect, &rect),
                   rect.width.isFinite, rect.height > 0 {
                    return cocoaRect(fromAccessibility: rect)
                }
            }
        }

        // No caret bounds (common in web views): fall back to the field itself.
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size),
              size.height > 0 else { return nil }
        return cocoaRect(fromAccessibility: CGRect(origin: origin, size: size))
    }

    /// The element with the keyboard focus. The system-wide handle answers for most apps but
    /// comes back empty for some — Electron among them — so the frontmost application is asked
    /// directly as well before giving up.
    private static func focusedElement() -> AXUIElement? {
        if let element = focusedElement(of: AXUIElementCreateSystemWide()) { return element }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            logger.notice("No frontmost application to ask.")
            return nil
        }
        if let element = focusedElement(of: AXUIElementCreateApplication(pid)) { return element }
        logger.notice("Neither the system nor the frontmost app reported a focused element.")
        return nil
    }

    private static func focusedElement(of parent: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /// Chromium — and so every Electron app, Claude's own included — keeps its accessibility
    /// tree switched off until an assistive client asks for it. Setting `AXManualAccessibility`
    /// on the application element is the documented way to ask. Harmless elsewhere.
    private static var accessibilityEnabledFor: Set<pid_t> = []

    private static func enableAccessibilityForFrontmostApp() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              !accessibilityEnabledFor.contains(pid) else { return }
        accessibilityEnabledFor.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        logger.notice("Asked \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?", privacy: .public) to switch its accessibility on.")
    }

    private static let logger = Logger(subsystem: "com.ralfchille.utterclip", category: "focused-field")

    /// Accessibility measures from the top-left of the primary display; Cocoa from the
    /// bottom-left.
    private static func cocoaRect(fromAccessibility rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
