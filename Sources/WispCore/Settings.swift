import Foundation

public enum Shortcut: String, Sendable { case option, command }
public enum Mode: String, Sendable { case preview, icons, list }
public enum Scope: String, Sendable { case currentSpace, allSpaces }

/// Reads and writes straight through to UserDefaults; no in-memory copy.
public struct Settings {
    let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var shortcut: Shortcut {
        get { read("shortcut", .option) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "shortcut") }
    }
    public var mode: Mode {
        get { read("mode", .preview) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "mode") }
    }
    public var scope: Scope {
        get { read("scope", .currentSpace) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "scope") }
    }

    private func read<T: RawRepresentable<String>>(_ key: String, _ fallback: T) -> T {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}

public func effectiveMode(_ mode: Mode, screenRecordingAllowed: Bool) -> Mode {
    mode == .preview && !screenRecordingAllowed ? .icons : mode
}
