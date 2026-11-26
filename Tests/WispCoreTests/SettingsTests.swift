import Foundation
import Testing
@testable import WispCore

private func fresh() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

@Test func defaultsWhenEmpty() {
    let s = Settings(defaults: fresh())
    #expect(s.shortcut == .option)
    #expect(s.mode == .preview)
    #expect(s.scope == .currentSpace)
    #expect(s.liquidGlass == false)
}

@Test func macOSStyleAndLiquidGlassRoundTrip() {
    let d = fresh()
    let s = Settings(defaults: d)
    s.mode = .macOS
    s.liquidGlass = true
    #expect(d.string(forKey: "mode") == "macos")
    let r = Settings(defaults: d)
    #expect(r.mode == .macOS)
    #expect(r.liquidGlass)
    #expect(effectiveMode(.macOS, screenRecordingAllowed: false) == .macOS)
}

@Test func roundTrips() {
    let d = fresh()
    let s = Settings(defaults: d)
    s.shortcut = .command
    s.mode = .list
    s.scope = .allSpaces
    let r = Settings(defaults: d)
    #expect(r.shortcut == .command)
    #expect(r.mode == .list)
    #expect(r.scope == .allSpaces)
}

@Test func invalidRawFallsBack() {
    let d = fresh()
    d.set("xyz", forKey: "shortcut")
    #expect(Settings(defaults: d).shortcut == .option)
}

@Test func effectiveModeFallsBack() {
    #expect(effectiveMode(.preview, screenRecordingAllowed: false) == .icons)
    #expect(effectiveMode(.preview, screenRecordingAllowed: true) == .preview)
    #expect(effectiveMode(.icons, screenRecordingAllowed: true) == .icons)
    #expect(effectiveMode(.list, screenRecordingAllowed: false) == .list)
}
