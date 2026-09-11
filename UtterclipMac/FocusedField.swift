import AppKit
import ApplicationServices

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
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focusedValue, to: AXUIElement.self)

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""
        // Web text fields and editors report AXTextArea or AXTextField too; a content-editable
        // div shows up as AXWebArea with a selection, which the range check below catches.
        let textRoles: Set<String> = [
            kAXTextFieldRole as String, kAXTextAreaRole as String,
            kAXComboBoxRole as String, "AXSearchField", "AXWebArea",
        ]
        guard textRoles.contains(role) else { return nil }

        // The caret: the bounds of the (empty) selected range.
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let range = rangeValue {
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

    /// Accessibility measures from the top-left of the primary display; Cocoa from the
    /// bottom-left.
    private static func cocoaRect(fromAccessibility rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
