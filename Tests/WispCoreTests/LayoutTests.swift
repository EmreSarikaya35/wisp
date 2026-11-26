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

@Test func previewPagesKeepTheTilesReadable() {
    let screen = CGSize(width: 800, height: 650)
    let layout = SwitcherLayout(count: 100, mode: .preview, screenSize: screen)
    #expect(layout.scale >= 0.75)
    #expect(layout.pageCount > 1)
    #expect(layout.pageSize.isMultiple(of: layout.columns))
    #expect(layout.page(containing: layout.pageSize).lowerBound == layout.pageSize)
    #expect(layout.page(containing: 99).upperBound == 100)
    #expect(layout.page(containing: 100).isEmpty)
    let rows = layout.pageSize / layout.columns
    let height = CGFloat(rows) * (layout.itemSize.height + SwitcherLayout.spacing) - SwitcherLayout.spacing
    #expect(height + 2 * SwitcherLayout.padding <= screen.height * 0.9)
}

@Test func compactListRetainsItsOneColumnAndFixedRowHeightAcrossPages() {
    let layout = SwitcherLayout(count: 100, mode: .list, screenSize: CGSize(width: 1440, height: 900))
    #expect(layout.columns == 1)
    #expect(layout.itemSize.height == 44)
    #expect(layout.pageCount > 1)
}

@Test func macOSStyleIsOneRowOfFullSizeIconsWhenTheyFit() {
    let layout = SwitcherLayout(count: 5, mode: .macOS, screenSize: CGSize(width: 1470, height: 956))
    #expect(layout.scale == 1)
    #expect(layout.columns == 5)
    #expect(layout.pageSize == 5)
    #expect(layout.itemSize == CGSize(width: 128, height: 128))
    // 5 icons on a 134 pt pitch plus the side insets: the 710 pt wide system panel.
    let width = CGFloat(layout.columns) * (layout.itemSize.width + layout.spacing) - layout.spacing
    #expect(width + 2 * layout.inset.width == 710)
}

@Test func macOSStyleShrinksThenPagesButStaysOneRow() {
    let screen = CGSize(width: 1470, height: 956)
    let some = SwitcherLayout(count: 14, mode: .macOS, screenSize: screen)
    #expect(some.scale < 1)
    #expect(some.columns == 14)
    #expect(some.pageCount == 1)
    let many = SwitcherLayout(count: 80, mode: .macOS, screenSize: screen)
    #expect(many.scale >= SwitcherLayout.macOSMinimumScale)
    #expect(many.pageSize == many.columns)
    #expect(many.pageCount > 1)
    let width = CGFloat(many.columns) * (many.itemSize.width + many.spacing) - many.spacing
    #expect(width + 2 * many.inset.width <= screen.width * 0.9)
}
