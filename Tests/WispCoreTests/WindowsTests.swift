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

@Test func fullscreenKeepsOnlyTheLastDesktopPerDisplay() {
    let secondary = DisplaySpaces(id: "secondary", current: 4, desktops: [3, 4], fullscreen: [8])
    var history = DesktopHistory()
    #expect(history.update([DisplaySpaces(id: "main", current: 2, desktops: [1, 2], fullscreen: [9]), secondary])
            == [2, 4, 8, 9])
    #expect(history.update([DisplaySpaces(id: "main", current: 9, desktops: [1, 2], fullscreen: [9]), secondary])
            == [2, 4, 8, 9])
    #expect(history.update([DisplaySpaces(id: "main", current: 9, desktops: [1], fullscreen: [9]), secondary])
            == [1, 4, 8, 9])
}

@Test func firstWindowEntryWinsAndInactiveWindowsStayAtTheEnd() {
    let input = [w(1), w(2), w(1, onScreen: false), w(3)]
    let facts: [UInt32: AXFacts] = [1: AXFacts(title: nil, isMinimized: true)]
    let out = buildList(cg: input, ax: facts, ownPID: 0, scope: .allSpaces)
    #expect(out.map(\.id) == [2, 3, 1])
    #expect(out.last?.isMinimized == true)
}

@Test func extraWindowsKeptInCurrentSpace() {
    let input = [w(1), w(2, onScreen: false), w(3, onScreen: false)]
    let out = buildList(cg: input, ax: [:], ownPID: 0, scope: .currentSpace, alsoInclude: [2])
    #expect(out.map(\.id) == [1, 2])
}

@Test func dropsHelperWindowsAXDoesNotKnow() {
    // Chrome in fullscreen puts an on-screen toolbar window above the real one; AX doesn't list it.
    let input = [w(1, pid: 10), w(2, pid: 10), w(3, pid: 11)]
    let ax: [UInt32: AXFacts] = [2: AXFacts(title: "Real", isMinimized: false)]
    let out = buildList(cg: input, ax: ax, ownPID: 0, scope: .currentSpace, axAnswered: [10])
    #expect(out.map(\.id) == [2, 3])  // pid 11 didn't answer AX (frozen/accessory): keep its windows
}

@Test func otherSpaceWindowsFollowAppRecency() {
    // Desktop: Claude (front), Safari, Discord. Fullscreen Chrome (pid 4) was used just before Claude.
    let input = [w(1, pid: 1), w(2, pid: 2), w(3, pid: 3), w(4, pid: 4, onScreen: false), w(5, pid: 5, onScreen: false)]
    let ax: [UInt32: AXFacts] = [5: AXFacts(title: nil, isMinimized: true)]
    let out = buildList(cg: input, ax: ax, ownPID: 0, scope: .currentSpace, alsoInclude: [4], appRecency: [1, 4, 2])
    #expect(out.map(\.id) == [1, 4, 2, 3, 5])  // Chrome right after Claude; minimized stays last
}

@Test func fromFullscreenDesktopWindowsFollowAppRecency() {
    // Inside fullscreen Chrome (pid 4): only it is on screen; desktop windows come by recency.
    let input = [w(4, pid: 4), w(3, pid: 3, onScreen: false), w(1, pid: 1, onScreen: false), w(2, pid: 2, onScreen: false)]
    let out = buildList(cg: input, ax: [:], ownPID: 0, scope: .currentSpace, alsoInclude: [1, 2, 3], appRecency: [4, 1, 3])
    #expect(out.map(\.id) == [4, 1, 3, 2])  // unknown recency (pid 2) last
}
