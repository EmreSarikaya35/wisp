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
        let fit = Int((maxSize.width + spacing) / (item.width * s + spacing))
        let cols = min(count, max(1, fit))
        return GridLayout(columns: cols, rows: (count + cols - 1) / cols, scale: s)
    }
    func fits(_ g: GridLayout) -> Bool {
        CGFloat(g.columns) * (item.width * g.scale + spacing) - spacing <= maxSize.width
            && CGFloat(g.rows) * (item.height * g.scale + spacing) - spacing <= maxSize.height
    }
    if fits(layout(1)) { return layout(1) }
    var lo: CGFloat = 0, hi: CGFloat = 1  // fits(lo) holds as scale → 0; bisect for the largest fitting scale
    for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if fits(layout(mid)) { lo = mid } else { hi = mid }
    }
    return layout(lo)
}
