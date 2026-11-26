import AppKit
import WispCore

/// One invocation, from the shortcut press to release, acceptance, or cancellation.
@MainActor final class Session {
    private let scope: Scope
    private let preferredMode: Mode
    private let glass: Bool
    private let modifier: CGEventFlags
    private let makePanel: () -> Panel
    private let onEnd: () -> Void

    private var request: SnapshotRequest?
    private var snapshot: Snapshot?
    private var selection = Selection(count: 0)
    private var pendingMoves: [KeyAction] = []
    private var reverse = false
    private var mode: Mode = .icons
    private var screen: NSScreen?
    private var screenSize: CGSize = .zero
    private var layout: SwitcherLayout?

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var showWork: DispatchWorkItem?
    private var wantsPanel = false
    private var renderScheduled = false
    private var panel: Panel?
    private var capture: Task<Void, Never>?
    private var modifierWatch: Timer?
    private var ended = false

    init(settings: Settings, shortcut: Shortcut, makePanel: @escaping () -> Panel, onEnd: @escaping () -> Void) {
        scope = settings.scope
        preferredMode = settings.mode
        glass = settings.liquidGlass
        modifier = shortcut == .option ? .maskAlternate : .maskCommand
        self.makePanel = makePanel
        self.onEnd = onEnd
    }

    func start(reverse: Bool) {
        self.reverse = reverse
        let mouse = NSEvent.mouseLocation
        screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        screenSize = screen?.visibleFrame.size ?? CGSize(width: 1024, height: 768)
        mode = effectiveMode(preferredMode, screenRecordingAllowed: preferredMode != .preview || Permissions.screenRecording)

        let listening = installTap()
        if !listening, modifierHeld { return finish(activate: false) }
        request = WindowSource.request(scope: scope) { [weak self] in self?.receive($0) }
        guard listening else { return finish(activate: true) }

        // Carbon can deliver the shortcut after the modifier has already been released.
        let watch = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkModifier() }
        }
        watch.tolerance = 0.005
        RunLoop.main.add(watch, forMode: .common)
        modifierWatch = watch

        let work = DispatchWorkItem { [weak self] in self?.requestPanel() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + tapThreshold, execute: work)
    }

    private var modifierHeld: Bool { CGEventSource.flagsState(.combinedSessionState).contains(modifier) }

    private func checkModifier() {
        if !ended, !modifierHeld { finish(activate: true) }
    }

    private func receive(_ snapshot: Snapshot) {
        guard !ended else { return }
        guard !snapshot.windows.isEmpty else { return finish(activate: false) }
        self.snapshot = snapshot
        let layout = SwitcherLayout(count: snapshot.windows.count, mode: mode, screenSize: screenSize)
        self.layout = layout
        selection = Self.initialSelection(snapshot, reverse: reverse, moves: pendingMoves, columns: layout.columns)
        pendingMoves.removeAll()
        if wantsPanel { scheduleRender() }
    }

    nonisolated private static func initialSelection(_ snapshot: Snapshot, reverse: Bool, moves: [KeyAction],
                                                    columns: Int) -> Selection {
        var selection = Selection(count: snapshot.windows.count, frontmostListed: snapshot.frontmostListed,
                                  reverse: reverse)
        for action in moves { selection.move(action, columns: columns) }
        return selection
    }

    private func requestPanel() {
        wantsPanel = true
        if snapshot != nil { scheduleRender() }
    }

    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in self?.render() }
    }

    private func render() {
        renderScheduled = false
        guard !ended, let snapshot, let screen, let layout else { return }
        guard modifierHeld else { return finish(activate: true) }
        let panel = self.panel ?? makePanel()
        let pageChanged: Bool
        if self.panel != nil {
            pageChanged = panel.select(selection.index)
        } else {
            self.panel = panel
            panel.onHover = { [weak self] in self?.select($0) }
            panel.onClick = { [weak self] index in
                self?.select(index)
                self?.finish(activate: true)
            }
            panel.show(windows: snapshot.windows, mode: mode, layout: layout, selected: selection.index,
                       glass: glass, on: screen)
            pageChanged = true
        }
        guard mode == .preview, pageChanged else { return }
        capture?.cancel()
        let page = layout.page(containing: selection.index)
        let indices = [selection.index] + page.filter { $0 != selection.index }
        let targets = indices.compactMap { index -> (Int, UInt32)? in
            let window = snapshot.windows[index]
            return window.isMinimized || window.isHidden ? nil : (index, window.id)
        }
        let size = CGSize(width: 220 * layout.scale, height: 140 * layout.scale)
        capture = Thumbnails.capture(targets: targets, size: size, scale: screen.backingScaleFactor) { [weak self] index, image in
            guard let self, !ended else { return }
            panel.setThumbnail(image, at: index)
        }
    }

    private func select(_ index: Int) {
        selection.set(index)
        scheduleRender()
    }

    func step(forward: Bool) { move(forward ? .next : .previous) }

    func cancel() { finish(activate: false) }

    private func move(_ action: KeyAction) {
        if let layout { selection.move(action, columns: layout.columns) }
        else { pendingMoves.append(action) }
        requestPanel()
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            checkModifier()
            return false
        case .flagsChanged:
            if !event.flags.contains(modifier) { finish(activate: true) }
            return false
        case .keyDown:
            switch keyAction(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                             shift: event.flags.contains(.maskShift)) {
            case .next: move(.next)
            case .previous: move(.previous)
            case .up: move(.up)
            case .down: move(.down)
            case .accept: finish(activate: true)
            case .cancel: finish(activate: false)
            case .swallow: break
            }
            return true
        default:
            return false
        }
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                let me = Unmanaged<Session>.fromOpaque(userInfo!).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { me.handle(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { log.error("session tap creation failed"); return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        tapSource = source
        return true
    }

    private func finish(activate: Bool) {
        guard !ended else { return }
        ended = true
        showWork?.cancel()
        modifierWatch?.invalidate()
        capture?.cancel()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        panel?.hide()
        panel?.onHover = nil
        panel?.onClick = nil
        if activate {
            if snapshot != nil {
                request?.activate { [index = selection.index] _ in index }
            } else {
                request?.activate { [reverse, pendingMoves, mode, screenSize] snapshot in
                    let layout = SwitcherLayout(count: snapshot.windows.count, mode: mode, screenSize: screenSize)
                    return Self.initialSelection(snapshot, reverse: reverse, moves: pendingMoves, columns: layout.columns).index
                }
            }
        }
        request = nil
        onEnd()
    }
}
