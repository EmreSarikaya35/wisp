import Foundation

public struct Selection: Equatable {
    public private(set) var index: Int
    public let count: Int

    /// Starts on the previous window (index 1), like Windows Alt+Tab. When the frontmost app has no listed
    /// window (desktop focused, windowless app), the top window is the one to go to, so start at 0.
    public init(count: Int, frontmostListed: Bool = true, reverse: Bool = false) {
        self.count = count
        index = reverse ? max(0, count - 1) : count >= 2 && frontmostListed ? 1 : 0
    }

    public mutating func next() { if count > 0 { index = (index + 1) % count } }
    public mutating func previous() { if count > 0 { index = (index - 1 + count) % count } }
    public mutating func set(_ i: Int) { if (0..<count).contains(i) { index = i } }

    private mutating func moveRow(by direction: Int, columns: Int) {
        guard count > 0, columns > 0 else { return }
        let rows = (count - 1) / columns + 1
        let row = (index / columns + direction + rows) % rows
        index = min(row * columns + index % columns, count - 1)
    }

    public mutating func move(_ action: KeyAction, columns: Int) {
        switch action {
        case .next: next()
        case .previous: previous()
        case .up: moveRow(by: -1, columns: columns)
        case .down: moveRow(by: 1, columns: columns)
        case .accept, .cancel, .swallow: break
        }
    }
}

public enum PressKind { case tap, hold }

public let tapThreshold: TimeInterval = 0.15

public func classifyPress(duration: TimeInterval) -> PressKind { duration < tapThreshold ? .tap : .hold }

public enum KeyAction: Equatable, Sendable { case next, previous, up, down, accept, cancel, swallow }

/// What a keyDown does while the switcher is open. Every key is swallowed so that, e.g., Cmd+Q or
/// Option+letter never reaches the app behind the panel.
public func keyAction(keyCode: Int, shift: Bool) -> KeyAction {
    switch keyCode {
    case 48: shift ? .previous : .next  // Tab
    case 124: .next                     // →
    case 123: .previous                 // ←
    case 126: .up                       // ↑
    case 125: .down                     // ↓
    case 36, 76: .accept                // Return, keypad Enter
    case 53: .cancel                    // Esc
    default: .swallow
    }
}
