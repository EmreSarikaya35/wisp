import Foundation

public enum Shortcut: String, Sendable { case option, command }
public enum Mode: String, Sendable {
    case preview, icons, list
    /// One row of large app icons, styled after the built-in macOS app switcher.
    case macOS = "macos"
}
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

    /// Liquid Glass backdrop for the switcher panel. Off unless the user turns it on.
    public var liquidGlass: Bool {
        get { defaults.bool(forKey: "liquidGlass") }
        nonmutating set { defaults.set(newValue, forKey: "liquidGlass") }
    }

    private func read<T: RawRepresentable<String>>(_ key: String, _ fallback: T) -> T {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}

public func effectiveMode(_ mode: Mode, screenRecordingAllowed: Bool) -> Mode {
    mode == .preview && !screenRecordingAllowed ? .icons : mode
}
