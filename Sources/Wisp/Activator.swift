import AppKit
import ApplicationServices
import WispCore

@MainActor enum Activator {
    static func activate(_ w: WindowInfo, element: AXUIElement?) {
        let app = NSRunningApplication(processIdentifier: w.pid)
        if w.isHidden { app?.unhide() }
        guard let el = element else { app?.activate(); return }
        if w.isMinimized { AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        let raised = AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
        // activate() without .activateAllWindows keeps the app's other windows where they are (MRU order).
        if app?.activate(options: []) != true || raised != .success {
            let appEl = AXUIElementCreateApplication(w.pid)
            AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
    }
}
