import CoreGraphics
import Testing
@testable import WispCore

private func w(_ id: UInt32, pid: Int32 = 10, layer: Int = 0, size: CGSize = CGSize(width: 800, height: 600),
               onScreen: Bool = true, title: String = "T") -> WindowInfo {
    WindowInfo(id: id, pid: pid, appName: "App", title: title, layer: layer,
               bounds: CGRect(origin: .zero, size: size), isOnScreen: onScreen, isMinimized: false)
}

@Test func dropsNonZeroLayerTinyAndOwn() {
    let input = [w(1, layer: 25), w(2, size: CGSize(width: 40, height: 300)), w(3, pid: 99), w(4)]
    let out = buildList(cg: input, ax: [:], ownPID: 99, scope: .currentSpace)
    #expect(out.map(\.id) == [4])
}

@Test func keepsZOrderMinimizedLast() {
    let input = [w(1), w(2, onScreen: false), w(3)]
    let out = buildList(cg: input, ax: [2: AXFacts(title: nil, isMinimized: true)], ownPID: 0, scope: .currentSpace)
    #expect(out.map(\.id) == [1, 3, 2])
    #expect(out.last?.isMinimized == true)
    #expect(out.first?.isMinimized == false)
}

@Test func currentSpaceDropsOffscreenNonMinimized() {
    let input = [w(1, onScreen: false)]
    let ax = [UInt32(1): AXFacts(title: nil, isMinimized: false)]
    #expect(buildList(cg: input, ax: ax, ownPID: 0, scope: .currentSpace).isEmpty)
    #expect(buildList(cg: input, ax: ax, ownPID: 0, scope: .allSpaces).map(\.id) == [1])
}

@Test func allSpacesDropsUnknownOffscreen() {
    #expect(buildList(cg: [w(1, onScreen: false)], ax: [:], ownPID: 0, scope: .allSpaces).isEmpty)
}

@Test func titleFallsBackToAppName() {
    #expect(buildList(cg: [w(1, title: "")], ax: [:], ownPID: 0, scope: .currentSpace).first?.title == "App")
    let ax = [UInt32(1): AXFacts(title: "Doc", isMinimized: false)]
    #expect(buildList(cg: [w(1, title: "")], ax: ax, ownPID: 0, scope: .currentSpace).first?.title == "Doc")
    #expect(buildList(cg: [w(1, title: "CG")], ax: ax, ownPID: 0, scope: .currentSpace).first?.title == "CG")
}

@Test func parsesCGDict() {
    let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
    var dict: [String: Any] = [
        kCGWindowNumber as String: 42, kCGWindowOwnerPID as String: 7,
        kCGWindowOwnerName as String: "Safari", kCGWindowName as String: "Start",
        kCGWindowLayer as String: 0, kCGWindowBounds as String: bounds.dictionaryRepresentation,
        kCGWindowIsOnscreen as String: true,
    ]
    #expect(WindowInfo(cgDict: dict) == WindowInfo(id: 42, pid: 7, appName: "Safari", title: "Start", layer: 0,
                                                   bounds: bounds, isOnScreen: true, isMinimized: false))
    dict[kCGWindowName as String] = nil
    dict[kCGWindowIsOnscreen as String] = nil
    #expect(WindowInfo(cgDict: dict)?.title == "")
    #expect(WindowInfo(cgDict: dict)?.isOnScreen == false)
    dict[kCGWindowNumber as String] = nil
    #expect(WindowInfo(cgDict: dict) == nil)
}

@Test func hiddenAppWindowsListedLastInCurrentSpace() {
    let input = [w(1, onScreen: false), w(2)]
    let ax: [UInt32: AXFacts] = [1: AXFacts(title: nil, isMinimized: false, isHidden: true)]
    let out = buildList(cg: input, ax: ax, ownPID: 0, scope: .currentSpace)
    #expect(out.map(\.id) == [2, 1])
    #expect(out.last?.isHidden == true)
    #expect(out.first?.isHidden == false)
}

@Test func fullscreenSpacesCountAsCurrentDesktop() {
    let normal: Set<UInt64> = [1], other: Set<UInt64> = [2], full: Set<UInt64> = [9]
    // On the normal desktop: fullscreen apps are listed, other normal desktops are not.
    #expect(onCurrentDesktop(windowSpaces: full, current: normal, fullscreen: full))
    #expect(!onCurrentDesktop(windowSpaces: other, current: normal, fullscreen: full))
    // Inside a fullscreen app: the desktop behind it is listed too.
    #expect(onCurrentDesktop(windowSpaces: normal, current: full, fullscreen: full))
    // Helper windows that belong to no Space never count.
    #expect(!onCurrentDesktop(windowSpaces: [], current: full, fullscreen: full))
}

@Test func extraWindowsKeptInCurrentSpace() {
    let input = [w(1), w(2, onScreen: false), w(3, onScreen: false)]
    let out = buildList(cg: input, ax: [:], ownPID: 0, scope: .currentSpace, alsoInclude: [2])
    #expect(out.map(\.id) == [1, 2])
}
