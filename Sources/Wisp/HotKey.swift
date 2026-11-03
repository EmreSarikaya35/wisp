import Carbon.HIToolbox
import WispCore

/// Registers the switcher shortcut. Option mode uses a Carbon hotkey, so no code runs for other keystrokes.
@MainActor final class HotKey {
    private let onTrigger: (_ shift: Bool) -> Void
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    init(onTrigger: @escaping (_ shift: Bool) -> Void) { self.onTrigger = onTrigger }

    func install(_ shortcut: Shortcut) {
        uninstall()
        switch shortcut {
        case .option: installCarbon(modifier: optionKey)
        case .command: installTap()
        }
    }

    func uninstall() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    /// Cmd+Tab belongs to the system, so it can only be taken over by an always-on tap (keyDown only).
    private func installTap() {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo in
                let me = Unmanaged<HotKey>.fromOpaque(userInfo!).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { me.handle(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { log.error("Cmd+Tab tap creation failed"); return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        tapSource = source
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == kVK_Tab,
              event.flags.contains(.maskCommand) else { return false }
        onTrigger(event.flags.contains(.maskShift))
        return true
    }

    private func installCarbon(modifier: Int) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let me = Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue()
            MainActor.assumeIsolated { me.onTrigger(hk.id == 2) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for (id, mods) in [(UInt32(1), modifier), (2, modifier | shiftKey)] {
            var ref: EventHotKeyRef?
            let err = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(mods), EventHotKeyID(signature: 0x57495350, id: id),
                                          GetApplicationEventTarget(), 0, &ref)
            if err == noErr, let ref { refs.append(ref) } else { log.error("RegisterEventHotKey failed: \(err)") }
        }
    }
}
