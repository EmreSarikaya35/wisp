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

    public let columns: Int
    public let pageSize: Int
    public let itemSize: CGSize
    public let scale: CGFloat
    private let count: Int

    public init(count: Int, mode: Mode, screenSize: CGSize) {
        self.count = count
        let available = CGSize(width: max(1, screenSize.width * 0.9 - 2 * Self.padding),
                               height: max(1, screenSize.height * 0.9 - 2 * Self.padding))
        let item: CGSize = switch mode {
        case .preview: CGSize(width: 236, height: 180)
        case .icons: CGSize(width: 96, height: 96)
        case .list: CGSize(width: min(380, available.width), height: 44)
        }
        let minimumScale = min(0.75, available.width / item.width, available.height / item.height)
        let fitted = gridLayout(count: count, item: item, spacing: Self.spacing, maxSize: available)
        scale = mode == .list ? min(1, available.height / item.height) : max(minimumScale, fitted.scale)
        itemSize = CGSize(width: item.width * scale, height: item.height * scale)
        let cols = Int((available.width + Self.spacing) / (itemSize.width + Self.spacing))
        columns = mode == .list ? 1 : max(1, min(count, cols))
        let rows = Int((available.height + Self.spacing) / (itemSize.height + Self.spacing))
        pageSize = columns * max(1, rows)
    }

    public var pageCount: Int { count > 0 ? (count - 1) / pageSize + 1 : 0 }

    public func page(containing index: Int) -> Range<Int> {
        guard (0..<count).contains(index) else { return 0..<0 }
        let first = index / pageSize * pageSize
        return first..<(first + min(pageSize, count - first))
    }
}
