import CoreGraphics

public struct GridLayout: Equatable {
    public var columns: Int
    public var rows: Int
    public var scale: CGFloat
    public init(columns: Int, rows: Int, scale: CGFloat) { self.columns = columns; self.rows = rows; self.scale = scale }
}

/// Largest scale ≤ 1 at which `count` items fit in `maxSize`, with as many columns as the width allows.
public func gridLayout(count: Int, item: CGSize, spacing: CGFloat, maxSize: CGSize) -> GridLayout {
    guard count > 0 else { return GridLayout(columns: 0, rows: 0, scale: 1) }
    func layout(_ s: CGFloat) -> GridLayout {
        let width = item.width * s + spacing
        let fit = width > 0 ? (maxSize.width + spacing) / width : CGFloat(count)
        let cols = fit >= CGFloat(count) ? count : Int(max(1, fit))
        return GridLayout(columns: cols, rows: (count - 1) / cols + 1, scale: s)
    }
    func fits(_ g: GridLayout) -> Bool {
        CGFloat(g.columns) * (item.width * g.scale + spacing) - spacing <= maxSize.width
            && CGFloat(g.rows) * (item.height * g.scale + spacing) - spacing <= maxSize.height
    }
    if fits(layout(1)) { return layout(1) }
    var lo: CGFloat = 0, hi: CGFloat = 1
    for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if fits(layout(mid)) { lo = mid } else { hi = mid }
    }
    return layout(lo)
}

public struct SwitcherLayout: Sendable {
    public static let padding: CGFloat = 16
    public static let spacing: CGFloat = 8
    /// Lower bound for the icon scale of the macOS style before it starts paging.
    public static let macOSMinimumScale: CGFloat = 0.5

    public let columns: Int
    public let pageSize: Int
    public let itemSize: CGSize
    public let scale: CGFloat
    /// Gap between items.
    public let spacing: CGFloat
    /// Space between the panel edge and the items (width: left/right, height: top/bottom).
    public let inset: CGSize
    private let count: Int

    public init(count: Int, mode: Mode, screenSize: CGSize) {
        self.count = count
        let macOS = mode == .macOS
        // macOS style: 128 pt icons on a 134 pt pitch, measured from the system app switcher.
        let spacing: CGFloat = macOS ? 6 : Self.spacing
        let inset = macOS ? CGSize(width: 23, height: 23) : CGSize(width: Self.padding, height: Self.padding)
        self.spacing = spacing
        self.inset = inset
        var available = CGSize(width: max(1, screenSize.width * 0.9 - 2 * inset.width),
                               height: max(1, screenSize.height * 0.9 - 2 * inset.height))
        let item: CGSize = switch mode {
        case .preview: CGSize(width: 236, height: 180)
        case .icons: CGSize(width: 96, height: 96)
        case .list: CGSize(width: min(380, available.width), height: 44)
        case .macOS: CGSize(width: 128, height: 128)
        }
        // The macOS style is always a single row: icons shrink to fit the width, then it pages.
        if macOS { available.height = min(available.height, item.height) }
        let floor: CGFloat = macOS ? Self.macOSMinimumScale : 0.75
        let minimumScale = min(floor, available.width / item.width, available.height / item.height)
        let fitted = gridLayout(count: count, item: item, spacing: spacing, maxSize: available)
        scale = mode == .list ? min(1, available.height / item.height) : max(minimumScale, fitted.scale)
        itemSize = CGSize(width: item.width * scale, height: item.height * scale)
        let cols = Int((available.width + spacing) / (itemSize.width + spacing))
        columns = mode == .list ? 1 : max(1, min(count, cols))
        let rows = macOS ? 1 : Int((available.height + spacing) / (itemSize.height + spacing))
        pageSize = columns * max(1, rows)
    }

    public var pageCount: Int { count > 0 ? (count - 1) / pageSize + 1 : 0 }

    public func page(containing index: Int) -> Range<Int> {
        guard (0..<count).contains(index) else { return 0..<0 }
        let first = index / pageSize * pageSize
        return first..<(first + min(pageSize, count - first))
    }
}
