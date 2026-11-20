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
    var inactive: [WindowInfo] = []
    var seen = Set<UInt32>()
    for var w in cg {
        guard w.isCandidate(excluding: ownPID), seen.insert(w.id).inserted else { continue }
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
        if w.isMinimized || w.isHidden { inactive.append(w) }
        else if w.isOnScreen { onScreen.append(w) }
        else { offScreen.append(w) }
    }
    // Windows on other Spaces have no z-order with the visible ones, so place them by app recency (most recent
    // first): each goes before the first visible window of a less recently used app. Minimized/hidden stay last.
    let rank = Dictionary(appRecency.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    func recency(_ w: WindowInfo) -> Int { rank[w.pid] ?? Int.max }
    offScreen.sort { recency($0) < recency($1) }
    var result: [WindowInfo] = []
    result.reserveCapacity(onScreen.count + offScreen.count + inactive.count)
    var remote = offScreen.startIndex
    for window in onScreen {
        let visibleRank = recency(window)
        while remote < offScreen.endIndex, recency(offScreen[remote]) < visibleRank {
            result.append(offScreen[remote])
            remote += 1
        }
        result.append(window)
    }
    result.append(contentsOf: offScreen[remote...])
    result.append(contentsOf: inactive)
    return result
}

public extension WindowInfo {
    func isCandidate(excluding ownPID: Int32) -> Bool {
        layer == 0 && bounds.width >= 50 && bounds.height >= 50 && pid != ownPID
    }
}

public struct DisplaySpaces: Sendable {
    public let id: String
    public let current: UInt64
    public let desktops: [UInt64]
    public let fullscreen: Set<UInt64>

    public init(id: String, current: UInt64, desktops: [UInt64], fullscreen: Set<UInt64>) {
        self.id = id
        self.current = current
        self.desktops = desktops
        self.fullscreen = fullscreen
    }
}

public struct DesktopHistory: Sendable {
    private var lastDesktop: [String: UInt64] = [:]

    public init() {}

    /// Fullscreen apps are always available. For a fullscreen display, include its last normal desktop too.
    @discardableResult
    public mutating func update(_ displays: [DisplaySpaces]) -> Set<UInt64> {
        var included = Set<UInt64>()
        for display in displays {
            included.insert(display.current)
            included.formUnion(display.fullscreen)
            if display.desktops.contains(display.current) { lastDesktop[display.id] = display.current }
            if display.fullscreen.contains(display.current) {
                let previous = lastDesktop[display.id].flatMap { display.desktops.contains($0) ? $0 : nil }
                if let desktop = previous ?? display.desktops.first { included.insert(desktop) }
            }
        }
        return included
    }
}
