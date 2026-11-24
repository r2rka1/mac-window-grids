import AppKit
import ApplicationServices

/// Thin wrappers over the Accessibility API. All rects here are in Accessibility
/// coordinates (origin at the top-left of the primary screen, y down).
enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    static func app(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 1.0)  // do not hang on an unresponsive app
        return el
    }

    private static func value(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let v = value(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    /// Standard, non-minimised windows of an app.
    static func windows(pid: pid_t) -> [AXUIElement] {
        guard let list = value(app(pid), kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return list.filter { w in
            let subrole = value(w, kAXSubroleAttribute) as? String
            let minimized = value(w, kAXMinimizedAttribute) as? Bool ?? false
            return subrole == kAXStandardWindowSubrole && !minimized
        }
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        element(app(pid), kAXFocusedWindowAttribute) ?? element(app(pid), kAXMainWindowAttribute)
    }

    static func frame(of w: AXUIElement) -> CGRect? {
        guard let p = value(w, kAXPositionAttribute), let s = value(w, kAXSizeAttribute),
            CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin),
            AXValueGetValue(s as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        var origin = r.origin
        var size = r.size
        guard let p = AXValueCreate(.cgPoint, &origin), let s = AXValueCreate(.cgSize, &size) else { return }
        // Size first so a window near a screen edge is not clamped, then position,
        // then size again because moving can change the allowed size.
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
    }

    static func raise(_ w: AXUIElement) {
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }

    static func setFrontmost(pid: pid_t) {
        AXUIElementSetAttributeValue(app(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    /// Some apps (Chrome, Electron) animate every resize while "enhanced user interface"
    /// is on, which makes moves slow and imprecise. Turn it off around `body`.
    static func withoutEnhancedUI(pid: pid_t, _ body: () -> Void) {
        let el = app(pid)
        let attr = "AXEnhancedUserInterface"
        let wasOn = value(el, attr) as? Bool ?? false
        if wasOn { AXUIElementSetAttributeValue(el, attr as CFString, kCFBooleanFalse) }
        body()
        if wasOn { AXUIElementSetAttributeValue(el, attr as CFString, kCFBooleanTrue) }
    }
}
