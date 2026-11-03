import Foundation
import Testing
@testable import WispCore

private func fresh() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

@Test func defaultsWhenEmpty() {
    let s = Settings(defaults: fresh())
    #expect(s.shortcut == .option)
    #expect(s.mode == .preview)
    #expect(s.scope == .currentSpace)
    #expect(s.launchAtLogin == false)
}

@Test func roundTrips() {
    let d = fresh()
    let s = Settings(defaults: d)
    s.shortcut = .command; s.mode = .icons; s.scope = .allSpaces; s.launchAtLogin = true
    let r = Settings(defaults: d)
    #expect(r.shortcut == .command)
    #expect(r.mode == .icons)
    #expect(r.scope == .allSpaces)
    #expect(r.launchAtLogin == true)
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
}
