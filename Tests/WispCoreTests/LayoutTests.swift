import CoreGraphics
import Testing
@testable import WispCore

private let item = CGSize(width: 200, height: 150)

@Test func gridSingleRow() {
    #expect(gridLayout(count: 3, item: item, spacing: 10, maxSize: CGSize(width: 1000, height: 800))
            == GridLayout(columns: 3, rows: 1, scale: 1))
}

@Test func gridWraps() {
    #expect(gridLayout(count: 8, item: item, spacing: 10, maxSize: CGSize(width: 1000, height: 800))
            == GridLayout(columns: 4, rows: 2, scale: 1))
}

@Test func gridShrinksToFitHeight() {
    let g = gridLayout(count: 60, item: item, spacing: 10, maxSize: CGSize(width: 1000, height: 600))
    #expect(g.scale < 1)
    #expect(g.columns * g.rows >= 60)
    #expect(CGFloat(g.rows) * (150 * g.scale + 10) - 10 <= 600)
    #expect(CGFloat(g.columns) * (200 * g.scale + 10) - 10 <= 1000)
}

@Test func gridEmpty() {
    #expect(gridLayout(count: 0, item: item, spacing: 10, maxSize: CGSize(width: 1000, height: 800))
            == GridLayout(columns: 0, rows: 0, scale: 1))
}
