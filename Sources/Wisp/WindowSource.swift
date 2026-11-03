import AppKit
import ApplicationServices
import WispCore

struct Snapshot {
    let windows: [WindowInfo]
    let elements: [UInt32: AXUIElement]
    let icons: [Int32: NSImage]
}

@MainActor enum WindowSource {
    static func snapshot(scope: Scope) -> Snapshot {
        // .optionAll is not in z-order; only .optionOnScreenOnly is, so on-screen order comes from there.
        func list(_ o: CGWindowListOption) -> [WindowInfo] {
            (CGWindowListCopyWindowInfo(o.union(.excludeDesktopElements), kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap(WindowInfo.init(cgDict:))
        }
        let cg = list(.optionOnScreenOnly) + list(.optionAll).filter { !$0.isOnScreen }
        let ownPID = getpid()

        var ax: [UInt32: AXFacts] = [:], elements: [UInt32: AXUIElement] = [:], icons: [Int32: NSImage] = [:]
        var regular = Set<pid_t>()
        // shortcut: AX is queried app by app on the main thread; parallelize if Task 10 shows it misses 50 ms.
        for pid in Set(cg.lazy.filter { $0.layer == 0 && $0.pid != ownPID }.map(\.pid)) {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { continue }
            icons[pid] = app.icon
            regular.insert(pid)
            for el in axWindows(pid: pid) {
                guard let id = Private.windowID(of: el) else { continue }
                elements[id] = el
                ax[id] = facts(el, hidden: app.isHidden)
            }
        }
        if scope == .allSpaces, Private.allSpacesAvailable {
            var wanted: [pid_t: Set<UInt32>] = [:]
            for w in cg where !w.isOnScreen && w.layer == 0 && w.bounds.width >= 50 && w.bounds.height >= 50
                && ax[w.id] == nil && regular.contains(w.pid) && Private.isOnAnySpace(w.id) {
                wanted[w.pid, default: []].insert(w.id)
            }
            for (pid, ids) in wanted {
                for (id, el) in Private.remoteWindowElements(pid: pid, wanted: ids) {
                    elements[id] = el
                    ax[id] = facts(el, hidden: NSRunningApplication(processIdentifier: pid)?.isHidden ?? false)
                }
            }
        }
        let windows = buildList(cg: cg, ax: ax, ownPID: ownPID, scope: scope)
        for w in windows where icons[w.pid] == nil { icons[w.pid] = NSRunningApplication(processIdentifier: w.pid)?.icon }
        return Snapshot(windows: windows, elements: elements, icons: icons)
    }

    private static func facts(_ el: AXUIElement, hidden: Bool) -> AXFacts {
        AXFacts(title: attribute(el, kAXTitleAttribute) as? String,
                isMinimized: attribute(el, kAXMinimizedAttribute) as? Bool ?? false, isHidden: hidden)
    }

    static func axWindows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        return attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    static func attribute(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }
}
