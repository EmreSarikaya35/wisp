import AppKit
import WispCore

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Metrics of the built-in macOS app switcher, in points at scale 1.
private enum MacStyle {
    static let panelRadius: CGFloat = 57
    /// The selection plate is the 128 pt icon cell inset by this much (118 pt square).
    static let plateInset: CGFloat = 5
    static let plateRadius: CGFloat = 27
}

/// Colors that depend on the backdrop and, with Liquid Glass, on the light or dark appearance.
/// The glass values are measured from screenshots of the system switcher on macOS 26 (dark mode).
@MainActor struct PanelLook {
    var plateFill: NSColor
    var plateEdge: NSColor = .clear
    /// The system adds the plate's light to the glass instead of covering it, so it keeps the color behind.
    var plateAdditive = false
    var caption: NSColor = .white
    /// Only before macOS 26, where a plain see-through fill stands in for glass.
    var fallbackFill: NSColor = .clear
    /// Opacity of the plain 1 pt edge. Real glass gets the lit rim below instead.
    var rim: CGFloat = 0
    /// Real glass: slight darkening, how far colors are pushed toward full saturation, and the rim that is
    /// lit along the top and bottom edges and shaded along the sides.
    var glassDim: CGFloat = 0
    var glassSaturation: CGFloat = 0
    var rimLight: CGFloat = 0
    var rimShade: CGFloat = 0
    /// Light that falls on the glass from above, and the soft glow just inside its edge.
    var sheen: CGFloat = 0
    var glow: CGFloat = 0

    /// The plain dark panel of the macOS style without glass.
    static let dark = PanelLook(plateFill: NSColor(white: 1, alpha: 0.2), plateEdge: NSColor(white: 1, alpha: 0.13),
                                rim: 0.14)
    static let glassDark = PanelLook(plateFill: NSColor(white: 1, alpha: 0.255), plateAdditive: true,
                                     rimLight: 0.24, rimShade: 0.3)
    static let glassLight = PanelLook(plateFill: NSColor(white: 1, alpha: 0.3), plateAdditive: true,
                                      caption: NSColor(white: 0, alpha: 0.85),
                                      rimLight: 0.4, rimShade: 0.12)
    /// Before macOS 26.
    static let paneDark = PanelLook(plateFill: NSColor(white: 1, alpha: 0.3), plateEdge: NSColor(white: 1, alpha: 0.2),
                                    fallbackFill: NSColor(white: 0, alpha: 0.16), rim: 0.2)
    static let paneLight = PanelLook(plateFill: NSColor(white: 1, alpha: 0.5), plateEdge: NSColor(white: 1, alpha: 0.6),
                                     caption: NSColor(white: 0, alpha: 0.85),
                                     fallbackFill: NSColor(white: 1, alpha: 0.3), rim: 0.5)

    static func current(glass: Bool) -> PanelLook {
        guard glass else { return .dark }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if Backdrop.glassAvailable { return dark ? .glassDark : .glassLight }
        return dark ? .paneDark : .paneLight
    }
}

/// What the system switcher adds on top of clear glass: richer color and a lit rim. Drawn with Core Animation
/// blend modes, so the layers work on whatever shows through the glass.
private final class GlassChrome: NSView {
    private let dim = CALayer(), saturate = CALayer(), light = CALayer(), shade = CALayer()
    private let lightMask = CAGradientLayer(), shadeMask = CAGradientLayer()
    private let sheen = CAGradientLayer(), glow = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        // Keeps hue and brightness of what is behind and raises its saturation.
        saturate.compositingFilter = "saturationBlendMode"
        light.compositingFilter = "plusL"
        light.borderWidth = 1
        shade.borderWidth = 0.5
        sheen.compositingFilter = "plusL"
        sheen.locations = [0, 0.5, 1]
        sheen.masksToBounds = true
        glow.compositingFilter = "plusL"
        glow.borderWidth = 3
        let solid = NSColor.black.cgColor, none = NSColor.clear.cgColor
        lightMask.colors = [solid, none, none, solid]
        lightMask.locations = [0, 0.3, 0.7, 1]
        shadeMask.colors = [none, solid, solid, none]
        shadeMask.locations = [0.1, 0.33, 0.67, 0.9]
        light.mask = lightMask
        shade.mask = shadeMask
        for sub in [dim, saturate, sheen, glow, light, shade] {
            sub.cornerCurve = .continuous
            layer?.addSublayer(sub)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(radius: CGFloat, look: PanelLook) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sub in [dim, saturate, sheen, glow, light, shade] {
            sub.frame = bounds
            sub.cornerRadius = radius
        }
        lightMask.frame = bounds
        shadeMask.frame = bounds
        dim.backgroundColor = NSColor(white: 0, alpha: look.glassDim).cgColor
        saturate.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: look.glassSaturation).cgColor
        light.borderColor = NSColor(white: 1, alpha: look.rimLight).cgColor
        shade.borderColor = NSColor(white: 0, alpha: look.rimShade).cgColor
        sheen.colors = [NSColor(white: 1, alpha: look.sheen).cgColor, NSColor(white: 1, alpha: 0).cgColor,
                        NSColor(white: 1, alpha: look.sheen / 3).cgColor]
        // Gradient layers run from y = 0, which is the bottom edge in AppKit.
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0)
        glow.borderColor = NSColor(white: 1, alpha: look.glow).cgColor
        CATransaction.commit()
    }
}

private final class ItemView: NSView {
    private var plate: NSView?
    private var thumbView: NSImageView?
    private var thumbArea: NSRect = .zero

    init(frame: NSRect, window: WindowInfo, icon: NSImage?, mode: Mode, scale: CGFloat, look: PanelLook) {
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
        case .macOS:
            // Icon only; the name of the selected entry is drawn by the panel, below the row.
            label.isHidden = true
            imageView.frame = bounds
            let plate = NSView(frame: bounds.insetBy(dx: MacStyle.plateInset * k, dy: MacStyle.plateInset * k))
            plate.wantsLayer = true
            let fill = CALayer()
            fill.frame = plate.bounds
            fill.cornerRadius = MacStyle.plateRadius * k
            fill.cornerCurve = .continuous
            fill.backgroundColor = look.plateFill.cgColor
            fill.borderWidth = 1
            fill.borderColor = look.plateEdge.cgColor
            if look.plateAdditive { fill.compositingFilter = "plusL" }
            plate.layer?.addSublayer(fill)
            plate.isHidden = true
            addSubview(plate, positioned: .below, relativeTo: imageView)
            self.plate = plate
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    var isSelected = false {
        didSet {
            if let plate { plate.isHidden = !isSelected; return }
            layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.34).cgColor : nil
        }
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
    /// macOS style: the name under the selected icon.
    private let caption = NSTextField(labelWithString: "")
    /// Apps with more than one listed window; their caption is the window title, so the entries can be told apart.
    private var multiWindowApps = Set<Int32>()
    private var items: [ItemView] = []
    private var windows: [WindowInfo] = []
    private var mode: Mode = .icons
    private var look = PanelLook.dark
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
        caption.alignment = .center
        caption.font = .systemFont(ofSize: 13, weight: .semibold)
        caption.textColor = .white
        caption.lineBreakMode = .byTruncatingMiddle
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        caption.shadow = shadow
        caption.isHidden = true
        content.addSubview(caption)
    }

    func show(windows: [WindowInfo], mode: Mode, layout: SwitcherLayout, selected: Int, glass: Bool, on screen: NSScreen) {
        self.windows = windows
        self.mode = mode
        self.layout = layout
        let macOS = mode == .macOS
        multiWindowApps = []
        if macOS {
            var seen = Set<Int32>()
            for window in windows where !seen.insert(window.pid).inserted { multiWindowApps.insert(window.pid) }
        }
        let rows = (min(windows.count, layout.pageSize) - 1) / layout.columns + 1
        let width = CGFloat(layout.columns) * (layout.itemSize.width + layout.spacing) - layout.spacing
        let height = CGFloat(rows) * (layout.itemSize.height + layout.spacing) - layout.spacing
        let size = NSSize(width: width + 2 * layout.inset.width, height: height + 2 * layout.inset.height)
        let f = screen.visibleFrame
        // Without glass the macOS style is the dark panel in both appearances. Glass follows the system theme.
        panel.appearance = macOS && !glass ? NSAppearance(named: .darkAqua) : nil
        look = PanelLook.current(glass: glass)
        caption.textColor = look.caption
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)
        content.setFrameSize(size)
        content.setBackdrop(glass: glass, cornerRadius: macOS ? min(MacStyle.panelRadius, size.height / 2) : 14,
                            plainRim: macOS || glass, look: look)
        // The caption owns the bottom strip in the macOS style, so the page counter moves to the top.
        footer.frame = NSRect(x: 0, y: macOS ? size.height - 16 : 2, width: size.width, height: 12)
        footer.isHidden = layout.pageCount <= 1
        caption.isHidden = !macOS
        select(selected)
        content.mouseOrigin = NSEvent.mouseLocation
        // A window shadow is also drawn underneath see-through content and would darken the glass.
        panel.hasShadow = !glass
        panel.invalidateShadow()
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
        if mode == .macOS { placeCaption(for: index, layout: layout) }
        return pageChanged
    }

    /// Centers the name under the selected icon, like the system switcher, and keeps it inside the panel.
    private func placeCaption(for index: Int, layout: SwitcherLayout) {
        let window = windows[index]
        let useTitle = multiWindowApps.contains(window.pid) && !window.title.isEmpty
        caption.stringValue = useTitle || window.appName.isEmpty ? window.title : window.appName
        let margin: CGFloat = 12
        let fitting = caption.fittingSize
        let width = min(ceil(fitting.width), content.bounds.width - 2 * margin)
        let item = items[index - page.lowerBound].frame
        let x = min(max(margin, item.midX - width / 2), content.bounds.width - margin - width)
        // Midway between the bottom of the selection plate and the bottom edge of the panel.
        let strip = layout.inset.height + MacStyle.plateInset * layout.scale
        caption.frame = NSRect(x: x.rounded(), y: ((strip - fitting.height) / 2).rounded(),
                               width: width, height: ceil(fitting.height))
    }

    private func buildPage(_ layout: SwitcherLayout) {
        clearPage()
        let w = layout.itemSize.width, h = layout.itemSize.height
        let spacing = layout.spacing, inset = layout.inset
        var icons: [Int32: NSImage] = [:]
        for (offset, index) in page.enumerated() {
            let window = windows[index]
            if icons[window.pid] == nil { icons[window.pid] = NSRunningApplication(processIdentifier: window.pid)?.icon }
            let col = offset % layout.columns, row = offset / layout.columns
            let frame = NSRect(x: inset.width + CGFloat(col) * (w + spacing),
                               y: content.bounds.height - inset.height - h - CGFloat(row) * (h + spacing),
                               width: w, height: h)
            let view = ItemView(frame: frame, window: window, icon: icons[window.pid] ?? NSImage(named: NSImage.applicationIconName),
                                mode: mode, scale: layout.scale, look: look)
            content.addSubview(view, positioned: .below, relativeTo: footer)
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
        caption.stringValue = ""
        multiWindowApps = []
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

/// The material behind the switcher: the standard blur, or Liquid Glass when the user turns it on.
@MainActor enum Backdrop {
    /// `NSGlassEffectView` exists from macOS 26. It is looked up at run time, so Wisp still builds with older SDKs.
    private static let glassClass: NSView.Type? = NSClassFromString("NSGlassEffectView") as? NSView.Type
    static var glassAvailable: Bool { glassClass != nil }

    static func make(glass: Bool) -> NSView {
        if glass, let glassClass {
            let view = glassClass.init(frame: .zero)
            // NSGlassEffectView.Style.clear (1): see-through glass colored by what is behind it, as in the
            // system switcher. The default, .regular (0), is the frosted kind.
            set(view, "style", 1)
            set(view, "contentView", NSView())
            return view
        }
        if glass {
            // Before macOS 26 there is no glass, and every system blur material is dark gray in dark mode.
            // A plain see-through pane keeps the color of what is behind it instead.
            let pane = NSView()
            pane.wantsLayer = true
            return pane
        }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.masksToBounds = true
        return blur
    }

    static func style(_ view: NSView, glass: Bool, radius: CGFloat, fill: NSColor) {
        if glass, glassAvailable {
            set(view, "cornerRadius", radius)
        } else {
            view.layer?.cornerRadius = radius
            view.layer?.cornerCurve = .continuous
            if glass { view.layer?.backgroundColor = fill.cgColor }
        }
    }

    /// Key-value coding, but only when the setter exists, so an API change can't crash the app.
    private static func set(_ view: NSView, _ key: String, _ value: Any) {
        let setter = "set\(key.prefix(1).uppercased())\(key.dropFirst()):"
        if view.responds(to: NSSelectorFromString(setter)) { view.setValue(value, forKey: key) }
    }
}

private final class PanelContentView: NSView {
    weak var panel: Panel?
    var mouseOrigin: NSPoint = .zero
    private var tracking: NSTrackingArea?
    private var backdrop: NSView?
    private var backdropIsGlass = false
    private var chrome: GlassChrome?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }

    func setBackdrop(glass: Bool, cornerRadius: CGFloat, plainRim: Bool, look: PanelLook) {
        if backdrop == nil || backdropIsGlass != glass {
            backdrop?.removeFromSuperview()
            let view = Backdrop.make(glass: glass)
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view, positioned: .below, relativeTo: nil)
            backdrop = view
            backdropIsGlass = glass
        }
        backdrop?.frame = bounds
        if let backdrop { Backdrop.style(backdrop, glass: glass, radius: cornerRadius, fill: look.fallbackFill) }

        let realGlass = glass && Backdrop.glassAvailable
        if realGlass {
            let chrome = self.chrome ?? GlassChrome()
            if chrome.superview == nil { addSubview(chrome, positioned: .above, relativeTo: backdrop) }
            self.chrome = chrome
            chrome.frame = bounds
            chrome.update(radius: cornerRadius, look: look)
        } else {
            chrome?.removeFromSuperview()
            chrome = nil
        }
        let rim = plainRim && !realGlass ? look.rim : 0
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = rim > 0 ? 1 : 0
        layer?.borderColor = rim > 0 ? NSColor(white: 1, alpha: rim).cgColor : nil
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
