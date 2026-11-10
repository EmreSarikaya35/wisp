import CoreGraphics
import Foundation

public struct WindowInfo: Equatable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var appName: String
    public var title: String
    public var layer: Int
    public var bounds: CGRect
    public var isOnScreen: Bool
    public var isMinimized: Bool
    public var isHidden: Bool

    public init(id: UInt32, pid: Int32, appName: String, title: String, layer: Int,
                bounds: CGRect, isOnScreen: Bool, isMinimized: Bool, isHidden: Bool = false) {
        self.id = id; self.pid = pid; self.appName = appName; self.title = title
        self.layer = layer; self.bounds = bounds; self.isOnScreen = isOnScreen; self.isMinimized = isMinimized
        self.isHidden = isHidden
    }

    /// One entry of `CGWindowListCopyWindowInfo`.
    public init?(cgDict d: [String: Any]) {
        guard let id = d[kCGWindowNumber as String] as? NSNumber,
              let pid = d[kCGWindowOwnerPID as String] as? NSNumber,
              let layer = d[kCGWindowLayer as String] as? NSNumber,
              let b = d[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: b as CFDictionary)
        else { return nil }
        self.init(id: id.uint32Value, pid: pid.int32Value, appName: d[kCGWindowOwnerName as String] as? String ?? "",
                  title: d[kCGWindowName as String] as? String ?? "", layer: layer.intValue, bounds: bounds,
                  isOnScreen: (d[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
                  isMinimized: false)
    }
}

public struct AXFacts: Equatable, Sendable {
    public var title: String?
    public var isMinimized: Bool
    /// The owning app is hidden (Cmd+H).
    public var isHidden: Bool
    public init(title: String?, isMinimized: Bool, isHidden: Bool = false) {
        self.title = title; self.isMinimized = isMinimized; self.isHidden = isHidden
    }
}

/// Filters CG windows to real user windows and orders them: on-screen (z-order) first, then the rest.
/// `alsoInclude`: off-screen windows that still count as the current desktop (see `onCurrentDesktop`).
/// `axAnswered`: apps whose AX window list was read; their windows AX doesn't know are helpers (toolbars, overlays).
public func buildList(cg: [WindowInfo], ax: [UInt32: AXFacts], ownPID: Int32, scope: Scope,
                      alsoInclude: Set<UInt32> = [], axAnswered: Set<Int32> = [],
                      appRecency: [Int32] = []) -> [WindowInfo] {
    var onScreen: [WindowInfo] = [], offScreen: [WindowInfo] = []
    for var w in cg {
        guard w.layer == 0, w.bounds.width >= 50, w.bounds.height >= 50, w.pid != ownPID else { continue }
        let facts = ax[w.id]
        if facts == nil, axAnswered.contains(w.pid) { continue }
        let keep = switch scope {
        case .currentSpace: w.isOnScreen || facts?.isMinimized == true || facts?.isHidden == true
            || alsoInclude.contains(w.id)
        case .allSpaces: w.isOnScreen || facts != nil
        }
        guard keep else { continue }
        w.isMinimized = facts?.isMinimized ?? false
        w.isHidden = facts?.isHidden ?? false
        if w.title.isEmpty { w.title = facts?.title.flatMap { $0.isEmpty ? nil : $0 } ?? w.appName }
        if w.isOnScreen { onScreen.append(w) } else { offScreen.append(w) }
    }
    // Windows on other Spaces have no z-order with the visible ones, so place them by app recency (most recent
    // first): each goes before the first visible window of a less recently used app. Minimized/hidden stay last.
    let rank = Dictionary(appRecency.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    func r(_ w: WindowInfo) -> Int { rank[w.pid] ?? Int.max }
    let tail = offScreen.filter { $0.isMinimized || $0.isHidden }
    var result = onScreen
    for e in offScreen.filter({ !$0.isMinimized && !$0.isHidden }).enumerated().sorted(by: {
        (r($0.element), $0.offset) < (r($1.element), $1.offset)
    }).map(\.element) {
        let i = r(e) == Int.max ? nil : result.firstIndex { r($0) > r(e) }
        result.insert(e, at: i ?? result.count)
    }
    return result + tail
}

/// A fullscreen app lives in its own Space, but to the user it is part of the desktop: fullscreen windows are
/// always listed, and from inside a fullscreen app the desktop behind it is listed too.
public func onCurrentDesktop(windowSpaces: Set<UInt64>, current: Set<UInt64>, fullscreen: Set<UInt64>) -> Bool {
    guard !windowSpaces.isEmpty else { return false }
    // shortcut: from a fullscreen app, windows of *every* normal desktop are listed; pick the last-used one if users with many desktops object.
    return !windowSpaces.isDisjoint(with: current) || !windowSpaces.isDisjoint(with: fullscreen)
        || !current.isDisjoint(with: fullscreen)
}
