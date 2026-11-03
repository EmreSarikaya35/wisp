import Foundation

public enum Shortcut: String, Sendable { case option, command }
public enum Mode: String, Sendable { case preview, icons }
public enum Scope: String, Sendable { case currentSpace, allSpaces }

public extension Notification.Name {
    static let wispSettingsChanged = Notification.Name("wispSettingsChanged")
}

/// Reads and writes straight through to UserDefaults; no in-memory copy.
public struct Settings {
    let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var shortcut: Shortcut {
        get { read("shortcut", .option) }
        nonmutating set { write("shortcut", newValue.rawValue) }
    }
    public var mode: Mode {
        get { read("mode", .preview) }
        nonmutating set { write("mode", newValue.rawValue) }
    }
    public var scope: Scope {
        get { read("scope", .currentSpace) }
        nonmutating set { write("scope", newValue.rawValue) }
    }
    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        nonmutating set { write("launchAtLogin", newValue) }
    }

    private func read<T: RawRepresentable<String>>(_ key: String, _ fallback: T) -> T {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
    private func write(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .wispSettingsChanged, object: nil)
    }
}

public func effectiveMode(_ mode: Mode, screenRecordingAllowed: Bool) -> Mode {
    screenRecordingAllowed ? mode : .icons
}
