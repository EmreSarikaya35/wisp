import ApplicationServices
import Darwin
import Foundation

/// Private symbols, resolved at runtime so a missing one disables a feature instead of crashing.
enum Private {
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateRemoteFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }
    private static let getWindow = sym("_AXUIElementGetWindow", GetWindowFn.self)
    private static let createRemote = sym("_AXUIElementCreateWithRemoteToken", CreateRemoteFn.self)
    private static let connection = sym("CGSMainConnectionID", ConnectionFn.self)
    private static let spacesForWindows = sym("CGSCopySpacesForWindows", SpacesForWindowsFn.self)

    static func windowID(of el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(el, &id) == .success else { return nil }
        return id
    }

    static var allSpacesAvailable: Bool {
        getWindow != nil && createRemote != nil && connection != nil && spacesForWindows != nil
    }

    /// Real windows belong to a Space; the many invisible helper windows apps own do not.
    static func isOnAnySpace(_ id: CGWindowID) -> Bool {
        guard let connection, let spacesForWindows,
              let spaces = spacesForWindows(connection(), 7 /* all spaces */, [id] as CFArray)?.takeRetainedValue()
        else { return false }
        return CFArrayGetCount(spaces) > 0
    }

    /// AX elements for windows on other Spaces, which kAXWindowsAttribute does not return.
    /// Brute-forces element ids of the remote token; stops once every wanted window is found.
    static func remoteWindowElements(pid: pid_t, wanted: Set<CGWindowID>) -> [CGWindowID: AXUIElement] {
        guard let createRemote, !wanted.isEmpty else { return [:] }
        var found: [CGWindowID: AXUIElement] = [:]
        // shortcut: element ids ≥ 1000 (windows opened late in a long-lived app) are missed; raise the cap if users report it.
        for elementID in UInt64(0)..<1000 where found.count < wanted.count {
            var token = Data(count: 20)
            token.withUnsafeMutableBytes { p in
                p.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
                p.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
                p.storeBytes(of: Int32(0x636f636f), toByteOffset: 8, as: Int32.self)  // "coco"
                p.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self)
            }
            guard let el = createRemote(token as CFData)?.takeRetainedValue() else { continue }
            var role: AnyObject?
            let err = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            if err == .cannotComplete { break }  // app is not answering; don't wait 0.1 s × 1000
            guard err == .success, role as? String == kAXWindowRole,
                  let id = windowID(of: el), wanted.contains(id) else { continue }
            found[id] = el
        }
        return found
    }
}
