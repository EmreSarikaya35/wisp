import AppKit
import ApplicationServices
import WispCore

enum Activator {
    static func activate(_ window: WindowInfo, element: AXUIElement?) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        let appElement = AXUIElementCreateApplication(window.pid)
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
        if window.isHidden || app?.isHidden == true { app?.unhide() }

        // A cold AX window list can time out, especially when Chrome opens an Incognito window.
        // Retry the selected ID once with a little more time without slowing down the list itself.
        func resolveWindow() -> AXUIElement? {
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            return WindowSource.windowElement(withID: window.id, in: appElement)
        }

        guard var target = element ?? resolveWindow() else {
            if !isFrontmost { activateApp(app, element: appElement) }
            return
        }

        var raised = raise(target, restore: window.isMinimized)
        if element != nil, raised == .invalidUIElement || raised == .cannotComplete,
           let refreshed = resolveWindow() {
            target = refreshed
            raised = raise(target, restore: window.isMinimized)
        }

        // Activating an app that's already frontmost can restore its previous key window.
        if !isFrontmost { activateApp(app, element: appElement) }
        if let focused = WindowSource.focusedWindowID(in: appElement), focused != window.id {
            let result = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
            if result != .success, raised == .success { _ = raise(target, restore: false) }
        }
    }

    private static func raise(_ target: AXUIElement, restore: Bool) -> AXError {
        if restore { AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(target, kAXRaiseAction as CFString)
    }

    private static func activateApp(_ app: NSRunningApplication?, element: AXUIElement) {
        if app?.activate(options: []) != true {
            AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
    }
}
