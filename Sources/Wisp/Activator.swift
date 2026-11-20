import AppKit
import ApplicationServices
import WispCore

enum Activator {
    static func activate(_ w: WindowInfo, element: AXUIElement?) {
        guard let app = NSRunningApplication(processIdentifier: w.pid), !app.isTerminated else { return }
        if w.isHidden || app.isHidden { app.unhide() }
        guard let el = element else { app.activate(); return }
        if w.isMinimized { AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        let raised = AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
        // activate() without .activateAllWindows keeps the app's other windows where they are (MRU order).
        if !app.activate(options: []) || raised != .success {
            let appEl = AXUIElementCreateApplication(w.pid)
            AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
    }
}
