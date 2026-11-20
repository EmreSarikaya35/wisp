import Carbon.HIToolbox
import WispCore

/// Option uses Carbon so unrelated keystrokes never wake Wisp.
@MainActor final class HotKey {
    private static let signature: OSType = 0x57495350  // WISP
    private let onTrigger: (_ shift: Bool, _ repeatPress: Bool) -> Void
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private(set) var shortcut: Shortcut?

    init(onTrigger: @escaping (_ shift: Bool, _ repeatPress: Bool) -> Void) { self.onTrigger = onTrigger }

    func install(_ requested: Shortcut) -> Bool {
        guard requested != shortcut else { return true }
        switch requested {
        case .option:
            guard installCarbon() else { return false }
            removeTap()
        case .command:
            guard installTap() else { return false }
            removeCarbon()
        }
        shortcut = requested
        return true
    }

    func uninstall() {
        removeCarbon()
        removeTap()
        shortcut = nil
    }

    private func removeCarbon() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func removeTap() {
        if let tap { CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    /// Cmd+Tab belongs to the system, so replacing it requires a key-down event tap.
    private func installTap() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo in
                let me = Unmanaged<HotKey>.fromOpaque(userInfo!).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { me.handle(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { log.error("Cmd+Tab tap creation failed"); return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        tapSource = source
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == kVK_Tab,
              event.flags.contains(.maskCommand),
              event.flags.intersection([.maskControl, .maskAlternate]).isEmpty else { return false }
        onTrigger(event.flags.contains(.maskShift), event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        return true
    }

    private func installCarbon() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard status == noErr, hotKey.signature == 0x57495350, hotKey.id == 1 || hotKey.id == 2
            else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue()
            MainActor.assumeIsolated { me.onTrigger(hotKey.id == 2, false) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            log.error("InstallEventHandler failed: \(status)")
            return false
        }
        for (id, mods) in [(UInt32(1), optionKey), (2, optionKey | shiftKey)] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(mods), EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
            guard status == noErr, let ref else {
                log.error("RegisterEventHotKey failed: \(status)")
                removeCarbon()
                return false
            }
            refs.append(ref)
        }
        return true
    }
}
