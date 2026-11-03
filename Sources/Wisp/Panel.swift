import AppKit
import WispCore

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ItemView: NSView {
    let index: Int
    let imageView = NSImageView()
    let label = NSTextField(labelWithString: "")
    let thumbView = NSImageView()
    var thumbArea: NSRect = .zero

    init(index: Int, frame: NSRect) {
        self.index = index
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        imageView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .labelColor
        addSubview(imageView)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    var isSelected = false {
        didSet { layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : nil }
    }
}

/// One reusable floating panel; holds item views only while shown.
@MainActor final class Panel {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let panel: SwitcherPanel
    private let content: PanelContentView
    private var items: [ItemView] = []

    static let padding: CGFloat = 16, spacing: CGFloat = 8
    static let iconItem = CGSize(width: 96, height: 96)
    static let previewItem = CGSize(width: 236, height: 180)  // 220×140 thumbnail + title row
    private(set) var thumbnailSize: CGSize = .zero

    init() {
        panel = SwitcherPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                              backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        content = PanelContentView()
        panel.contentView = content
        content.panel = self
    }

    func show(items windows: [WindowInfo], icons: [Int32: NSImage], mode: Mode, selected: Int, on screen: NSScreen) {
        let maxSize = NSSize(width: screen.visibleFrame.width * 0.9 - 2 * Self.padding,
                             height: screen.visibleFrame.height * 0.9 - 2 * Self.padding)
        let item = mode == .preview ? Self.previewItem : Self.iconItem
        let grid = gridLayout(count: windows.count, item: item, spacing: Self.spacing, maxSize: maxSize)
        let w = item.width * grid.scale, h = item.height * grid.scale
        let size = NSSize(width: CGFloat(grid.columns) * (w + Self.spacing) - Self.spacing + 2 * Self.padding,
                          height: CGFloat(grid.rows) * (h + Self.spacing) - Self.spacing + 2 * Self.padding)
        content.setFrameSize(size)

        let k = grid.scale
        thumbnailSize = CGSize(width: 220 * k, height: 140 * k)
        for (i, win) in windows.enumerated() {
            let col = i % grid.columns, row = i / grid.columns
            let frame = NSRect(x: Self.padding + CGFloat(col) * (w + Self.spacing),
                               y: size.height - Self.padding - CGFloat(row + 1) * h - CGFloat(row) * Self.spacing,
                               width: w, height: h)
            let v = ItemView(index: i, frame: frame)
            if mode == .preview {
                v.thumbArea = NSRect(x: 8 * k, y: 32 * k, width: 220 * k, height: 140 * k)
                v.thumbView.frame = v.thumbArea.insetBy(dx: (220 - 48) / 2 * k, dy: (140 - 48) / 2 * k)
                v.thumbView.image = icons[win.pid]  // placeholder until the screenshot arrives
                v.addSubview(v.thumbView)
                v.imageView.frame = NSRect(x: 8 * k, y: 8 * k, width: 16 * k, height: 16 * k)
                v.label.frame = NSRect(x: 28 * k, y: 8 * k, width: w - 36 * k, height: 16 * k)
                v.label.alignment = .left
            } else {
                let icon = 64 * k
                v.imageView.frame = NSRect(x: (w - icon) / 2, y: h - icon - 6, width: icon, height: icon)
                v.label.frame = NSRect(x: 4, y: 4, width: w - 8, height: 16)
            }
            v.imageView.image = icons[win.pid]
            v.label.stringValue = win.title
            v.toolTip = win.title
            v.alphaValue = win.isMinimized || win.isHidden ? 0.5 : 1
            content.addSubview(v)
            items.append(v)
        }
        select(selected)

        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)
        content.mouseOrigin = NSEvent.mouseLocation
        panel.orderFrontRegardless()
    }

    func select(_ i: Int) { for v in items { v.isSelected = v.index == i } }

    func setThumbnail(_ img: CGImage, at i: Int) {
        guard items.indices.contains(i) else { return }
        let v = items[i]
        v.thumbView.frame = v.thumbArea
        v.thumbView.image = NSImage(cgImage: img, size: .zero)
    }

    func hide() {
        panel.orderOut(nil)
        items.forEach { $0.removeFromSuperview() }
        items = []
    }

    fileprivate func index(at point: NSPoint) -> Int? { items.first { $0.frame.contains(point) }?.index }
}

private final class PanelContentView: NSVisualEffectView {
    weak var panel: Panel?
    var mouseOrigin: NSPoint = .zero
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        // Ignore the synthetic "move" when the panel appears under a still cursor.
        guard NSEvent.mouseLocation != mouseOrigin else { return }
        mouseOrigin = NSEvent.mouseLocation
        if let i = panel?.index(at: convert(event.locationInWindow, from: nil)) { panel?.onHover?(i) }
    }

    override func mouseDown(with event: NSEvent) {
        if let i = panel?.index(at: convert(event.locationInWindow, from: nil)) { panel?.onClick?(i) }
    }
}
