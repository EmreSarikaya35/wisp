import ApplicationServices
import Darwin
import Foundation
import WispCore

/// Private symbols, resolved at runtime so a missing one disables a feature instead of crashing.
enum Private {
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateRemoteFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias DisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }
    private static let getWindow = sym("_AXUIElementGetWindow", GetWindowFn.self)
    private static let createRemote = sym("_AXUIElementCreateWithRemoteToken", CreateRemoteFn.self)
    private static let connection = sym("CGSMainConnectionID", ConnectionFn.self)
    private static let spacesForWindows = sym("CGSCopySpacesForWindows", SpacesForWindowsFn.self)
    private static let displaySpaces = sym("CGSCopyManagedDisplaySpaces", DisplaySpacesFn.self)

    static func windowID(of el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(el, &id) == .success, id != kCGNullWindowID else { return nil }
        return id
    }

    static var windowIDsAvailable: Bool { getWindow != nil }

    static var allSpacesAvailable: Bool {
        getWindow != nil && createRemote != nil && connection != nil && spacesForWindows != nil && displaySpaces != nil
    }

    /// Spaces a window is on. Real windows belong to one; the many invisible helper windows apps own do not.
    static func spaces(of id: CGWindowID) -> Set<UInt64> {
        guard let connection, let spacesForWindows,
              let spaces = spacesForWindows(connection(), 7 /* all spaces */, [id] as CFArray)?.takeRetainedValue()
        else { return [] }
        return Set((spaces as? [NSNumber] ?? []).map(\.uint64Value))
    }

    static func desktopSpaces() -> [DisplaySpaces] {
        guard let connection, let displaySpaces,
              let displays = displaySpaces(connection())?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return displays.compactMap { display in
            guard let id = display["Display Identifier"] as? String,
                  let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            else { return nil }
            var desktops: [UInt64] = [], fullscreen = Set<UInt64>()
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let spaceID = space["id64"] as? NSNumber, let type = space["type"] as? NSNumber else { continue }
                if type.intValue == 0 { desktops.append(spaceID.uint64Value) }
                else { fullscreen.insert(spaceID.uint64Value) }
            }
            return DisplaySpaces(id: id, current: current.uint64Value, desktops: desktops, fullscreen: fullscreen)
        }
    }

    /// AX elements for windows on other Spaces, which kAXWindowsAttribute does not return.
    /// Brute-forces element ids of the remote token; stops once every wanted window is found.
    static func remoteWindowElements(pid: pid_t, wanted: Set<CGWindowID>) -> [CGWindowID: AXUIElement] {
        guard let createRemote, !wanted.isEmpty else { return [:] }
        var found: [CGWindowID: AXUIElement] = [:]
        // The 64-bit element ID starts at byte 12. Two 32-bit words keep every field naturally aligned.
        var token = (UInt32(bitPattern: pid), UInt32(0), UInt32(0x636f636f), UInt32(0), UInt32(0))
        for elementID in UInt32(0)..<1000 where found.count < wanted.count {
            token.3 = elementID
            let data = withUnsafeBytes(of: &token) { Data($0) }
            guard let el = createRemote(data as CFData)?.takeRetainedValue() else { continue }
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
