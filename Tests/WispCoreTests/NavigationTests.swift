import Testing
@testable import WispCore

@Test func selectionStartsAtSecond() { #expect(Selection(count: 5).index == 1) }

@Test func selectionSingle() {
    var s = Selection(count: 1)
    #expect(s.index == 0)
    s.next()
    #expect(s.index == 0)
}

@Test func selectionEmpty() {
    var s = Selection(count: 0)
    #expect(s.index == 0)
    s.next(); s.previous()
    #expect(s.index == 0)
}

@Test func selectionWraps() {
    var s = Selection(count: 3)
    s.next(); s.next()
    #expect(s.index == 0)
    s.previous()
    #expect(s.index == 2)
}

@Test func setIgnoresOutOfRange() {
    var s = Selection(count: 3)
    s.set(2)
    #expect(s.index == 2)
    s.set(3); s.set(-1)
    #expect(s.index == 2)
}

@Test func tapVsHold() {
    #expect(classifyPress(duration: 0.10) == .tap)
    #expect(classifyPress(duration: 0.15) == .hold)
    #expect(classifyPress(duration: 0.40) == .hold)
}

@Test func selectionStartsAtFirstWhenFrontAppHasNoListedWindow() {
    #expect(Selection(count: 5, frontmostListed: false).index == 0)
    #expect(Selection(count: 5, frontmostListed: true).index == 1)
}

@Test func keyActionsWhileSwitcherOpen() {
    #expect(keyAction(keyCode: 48, shift: false) == .next)       // Tab
    #expect(keyAction(keyCode: 48, shift: true) == .previous)    // Shift+Tab
    #expect(keyAction(keyCode: 124, shift: false) == .next)      // →
    #expect(keyAction(keyCode: 123, shift: false) == .previous)  // ←
    #expect(keyAction(keyCode: 36, shift: false) == .accept)     // Return
    #expect(keyAction(keyCode: 53, shift: false) == .cancel)     // Esc
    #expect(keyAction(keyCode: 12, shift: false) == .swallow)    // Q: Cmd+Q must not reach the app behind
}
