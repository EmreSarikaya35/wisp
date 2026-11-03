import AppKit
import WispCore
#if DEBUG
import os
private let perf = Logger(subsystem: "io.github.emresarikaya35.wisp", category: "perf")
#endif

/// One switcher invocation: lives from the shortcut press until the modifier is released.
@MainActor final class Session {
    private let settings: Settings
    private let modifier: CGEventFlags
    private let panel: Panel
    private let onEnd: () -> Void

    private var snapshot: Snapshot?
    private var selection = Selection(count: 0)
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var showWork: DispatchWorkItem?
    private var shown = false
    private var capture: Task<Void, Never>?
    private var modifierWatch: Timer?
    private var ended = false

    init(settings: Settings, modifier: CGEventFlags, panel: Panel, onEnd: @escaping () -> Void) {
        self.settings = settings
        self.modifier = modifier
        self.panel = panel
        self.onEnd = onEnd
    }

    func start(reverse: Bool) {
        #if DEBUG
        let t0 = DispatchTime.now()
        defer { perf.info("snapshot \(ms(since: t0)) ms, \(self.snapshot?.windows.count ?? 0) windows") }
        #endif
        let snap = WindowSource.snapshot(scope: settings.scope)
        guard !snap.windows.isEmpty else { return finish(activate: false) }
        snapshot = snap
        selection = Selection(count: snap.windows.count,
                              frontmostListed: NSWorkspace.shared.frontmostApplication?.processIdentifier == snap.windows[0].pid)
        if reverse { selection.set(snap.windows.count - 1) }

        guard installTap() else { return finish(activate: false) }
        // The modifier may already be up if the press was very fast: treat it as a tap.
        guard modifierHeld else { return finish(activate: true) }
        // Backstop: a release that happens while the tap is being installed never reaches it, which left the
        // panel stuck open. While the session lives, it only stays if the modifier is actually held.
        let watch = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkModifier() }
        }
        RunLoop.main.add(watch, forMode: .common)  // keep firing during mouse/menu tracking
        modifierWatch = watch

        let work = DispatchWorkItem { [weak self] in self?.showPanel() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + tapThreshold, execute: work)
    }

    private var modifierHeld: Bool { CGEventSource.flagsState(.combinedSessionState).contains(modifier) }

    private func checkModifier() {
        guard !ended, !modifierHeld else { return }
        log.info("session: modifier release missed by the tap, caught by watch")
        finish(activate: true)
    }

    private func showPanel() {
        guard !shown, !ended, let snap = snapshot else { return }
        guard modifierHeld else { return finish(activate: true) }
        shown = true
        showWork?.cancel()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.onHover = { [weak self] i in self?.select(i) }
        panel.onClick = { [weak self] i in self?.select(i); self?.finish(activate: true) }
        let mode = effectiveMode(settings.mode, screenRecordingAllowed: Permissions.screenRecording)
        #if DEBUG
        let t0 = DispatchTime.now()
        #endif
        panel.show(items: snap.windows, icons: snap.icons, mode: mode, selected: selection.index, on: screen)
        #if DEBUG
        perf.info("panel shown \(ms(since: t0)) ms (\(mode.rawValue))")
        #endif
        guard mode == .preview else { return }
        capture = Thumbnails.capture(ids: snap.windows.map(\.id), size: panel.thumbnailSize,
                                     scale: screen.backingScaleFactor) { [weak self] i, img in
            guard let self, !self.ended else { return }  // a late frame must not land in a later session's panel
            self.panel.setThumbnail(img, at: i)
        }
        #if DEBUG
        let task = capture
        Task { await task?.value; perf.info("thumbnails done \(ms(since: t0)) ms") }
        #endif
    }

    private func select(_ i: Int) {
        selection.set(i)
        panel.select(selection.index)
    }

    func step(forward: Bool) { move(forward) }

    private func move(_ forward: Bool) {
        if forward { selection.next() } else { selection.previous() }
        if shown { panel.select(selection.index) } else { showPanel() }
    }

    /// Returns true to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .flagsChanged:
            if !event.flags.contains(modifier) { finish(activate: true) }
            return false
        case .keyDown:
            switch keyAction(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                             shift: event.flags.contains(.maskShift)) {
            case .next: move(true)
            case .previous: move(false)
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
        modifierWatch = nil
        capture?.cancel()
        capture = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        if shown { panel.hide() }
        panel.onHover = nil
        panel.onClick = nil
        if activate, let snap = snapshot, snap.windows.indices.contains(selection.index) {
            let w = snap.windows[selection.index]
            Activator.activate(w, element: snap.elements[w.id])
        }
        snapshot = nil
        onEnd()
    }
}

#if DEBUG
private func ms(since t: DispatchTime) -> Int { Int((DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1_000_000) }
#endif
