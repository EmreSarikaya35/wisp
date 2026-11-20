import AppKit
import WispCore

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ItemView: NSView {
    private var thumbView: NSImageView?
    private var thumbArea: NSRect = .zero

    init(frame: NSRect, window: WindowInfo, icon: NSImage?, mode: Mode, scale: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        let imageView = NSImageView()
        let label = NSTextField(labelWithString: "")
        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: max(9, 11 * scale))
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = window.title
        toolTip = window.title
        alphaValue = window.isMinimized || window.isHidden ? 0.5 : 1
        addSubview(imageView)
        addSubview(label)

        let w = frame.width, h = frame.height, k = scale
        switch mode {
        case .preview:
            thumbArea = NSRect(x: 8 * k, y: 32 * k, width: 220 * k, height: 140 * k)
            let thumbView = NSImageView()
            thumbView.imageScaling = .scaleProportionallyUpOrDown
            thumbView.frame = thumbArea.insetBy(dx: 86 * k, dy: 46 * k)
            thumbView.image = icon
            addSubview(thumbView)
            self.thumbView = thumbView
            imageView.frame = NSRect(x: 8 * k, y: 8 * k, width: 16 * k, height: 16 * k)
            label.frame = NSRect(x: 28 * k, y: 6 * k, width: w - 36 * k, height: 18 * k)
        case .icons:
            let side = 64 * k
            imageView.frame = NSRect(x: (w - side) / 2, y: h - side - 6 * k, width: side, height: side)
            label.frame = NSRect(x: 4 * k, y: 4 * k, width: w - 8 * k, height: 18 * k)
            label.alignment = .center
        case .list:
            let side = 26 * k
            let textX = 46 * k
            let textWidth = max(0, w - textX - 10 * k)
            imageView.frame = NSRect(x: 10 * k, y: (h - side) / 2, width: side, height: side)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            if window.appName.isEmpty || window.title == window.appName {
                label.frame = NSRect(x: textX, y: (h - 17 * k) / 2, width: textWidth, height: 17 * k)
            } else {
                label.frame = NSRect(x: textX, y: 21 * k, width: textWidth, height: 17 * k)
                let appLabel = NSTextField(labelWithString: window.appName)
                appLabel.font = .systemFont(ofSize: 11)
                appLabel.textColor = .secondaryLabelColor
                appLabel.lineBreakMode = .byTruncatingTail
                appLabel.frame = NSRect(x: textX, y: 6 * k, width: textWidth, height: 14 * k)
                addSubview(appLabel)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    var isSelected = false {
        didSet { layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.34).cgColor : nil }
    }

    func setThumbnail(_ image: CGImage) {
        guard let thumbView else { return }
        thumbView.frame = thumbArea
        thumbView.image = NSImage(cgImage: image, size: .zero)
    }
}

/// One reusable panel. Views, icons and previews are retained only for the visible page.
@MainActor final class Panel {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private let panel: SwitcherPanel
    private let content: PanelContentView
    private let footer = NSTextField(labelWithString: "")
    private var items: [ItemView] = []
    private var windows: [WindowInfo] = []
    private var mode: Mode = .icons
    private var layout: SwitcherLayout?
    private var page: Range<Int> = 0..<0
    private var selected: Int?

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
        footer.alignment = .center
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        footer.textColor = .secondaryLabelColor
        footer.isHidden = true
        content.addSubview(footer)
    }

    func show(windows: [WindowInfo], mode: Mode, layout: SwitcherLayout, selected: Int, on screen: NSScreen) {
        self.windows = windows
        self.mode = mode
        self.layout = layout
        let rows = (min(windows.count, layout.pageSize) - 1) / layout.columns + 1
        let width = CGFloat(layout.columns) * (layout.itemSize.width + SwitcherLayout.spacing) - SwitcherLayout.spacing
        let height = CGFloat(rows) * (layout.itemSize.height + SwitcherLayout.spacing) - SwitcherLayout.spacing
        let size = NSSize(width: width + 2 * SwitcherLayout.padding, height: height + 2 * SwitcherLayout.padding)
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)
        content.setFrameSize(size)
        footer.frame = NSRect(x: 0, y: 2, width: size.width, height: 12)
        footer.isHidden = layout.pageCount <= 1
        select(selected)
        content.mouseOrigin = NSEvent.mouseLocation
        panel.orderFrontRegardless()
    }

    @discardableResult
    func select(_ index: Int) -> Bool {
        guard let layout, windows.indices.contains(index), selected != index else { return false }
        let newPage = layout.page(containing: index)
        let pageChanged = page != newPage
        if pageChanged {
            page = newPage
            buildPage(layout)
        } else if let selected {
            items[selected - page.lowerBound].isSelected = false
        }
        items[index - page.lowerBound].isSelected = true
        selected = index
        return pageChanged
    }

    private func buildPage(_ layout: SwitcherLayout) {
        clearPage()
        let w = layout.itemSize.width, h = layout.itemSize.height
        let spacing = SwitcherLayout.spacing, padding = SwitcherLayout.padding
        var icons: [Int32: NSImage] = [:]
        for (offset, index) in page.enumerated() {
            let window = windows[index]
            if icons[window.pid] == nil { icons[window.pid] = NSRunningApplication(processIdentifier: window.pid)?.icon }
            let col = offset % layout.columns, row = offset / layout.columns
            let frame = NSRect(x: padding + CGFloat(col) * (w + spacing),
                               y: content.bounds.height - padding - h - CGFloat(row) * (h + spacing),
                               width: w, height: h)
            let view = ItemView(frame: frame, window: window, icon: icons[window.pid] ?? NSImage(named: NSImage.applicationIconName),
                                mode: mode, scale: layout.scale)
            content.addSubview(view)
            items.append(view)
        }
        if layout.pageCount > 1 { footer.stringValue = "\(page.lowerBound / layout.pageSize + 1) / \(layout.pageCount)" }
    }

    func setThumbnail(_ image: CGImage, at index: Int) {
        if page.contains(index) { items[index - page.lowerBound].setThumbnail(image) }
    }

    func hide() {
        panel.orderOut(nil)
        clearPage()
        page = 0..<0
        selected = nil
        windows = []
        layout = nil
    }

    private func clearPage() {
        items.forEach { $0.removeFromSuperview() }
        items.removeAll()
    }

    fileprivate func index(at point: NSPoint) -> Int? {
        items.firstIndex { $0.frame.contains(point) }.map { page.lowerBound + $0 }
    }
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

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        // Ignore the synthetic move when the panel appears under a stationary cursor.
        guard NSEvent.mouseLocation != mouseOrigin else { return }
        mouseOrigin = NSEvent.mouseLocation
        if let index = panel?.index(at: convert(event.locationInWindow, from: nil)) { panel?.onHover?(index) }
    }

    override func mouseDown(with event: NSEvent) {
        if let index = panel?.index(at: convert(event.locationInWindow, from: nil)) { panel?.onClick?(index) }
    }
}
