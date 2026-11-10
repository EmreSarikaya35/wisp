import AppKit
import ApplicationServices
import WispCore

struct Snapshot {
    let windows: [WindowInfo]
    let elements: [UInt32: AXUIElement]
    let icons: [Int32: NSImage]
}

@MainActor enum WindowSource {
    /// Apps, most recently activated first. Fed by app-switch notifications only, so it costs nothing while idle.
    private static var appRecency: [pid_t] = []

    static func trackAppRecency() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { appRecency = [pid] }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            else { return }
            MainActor.assumeIsolated {
                appRecency.removeAll { $0 == pid }
                appRecency.insert(pid, at: 0)
                if appRecency.count > 64 { appRecency.removeLast() }
            }
        }
    }

    static func snapshot(scope: Scope) -> Snapshot {
        // .optionAll is not in z-order; only .optionOnScreenOnly is, so on-screen order comes from there.
        func list(_ o: CGWindowListOption) -> [WindowInfo] {
            (CGWindowListCopyWindowInfo(o.union(.excludeDesktopElements), kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap(WindowInfo.init(cgDict:))
        }
        let cg = list(.optionOnScreenOnly) + list(.optionAll).filter { !$0.isOnScreen }
        let ownPID = getpid()

        var ax: [UInt32: AXFacts] = [:], elements: [UInt32: AXUIElement] = [:], icons: [Int32: NSImage] = [:]
        var regular = Set<pid_t>(), axAnswered = Set<pid_t>()
        // shortcut: AX is queried app by app on the main thread; parallelize if Task 10 shows it misses 50 ms.
        for pid in Set(cg.lazy.filter { $0.layer == 0 && $0.pid != ownPID }.map(\.pid)) {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { continue }
            icons[pid] = app.icon
            regular.insert(pid)
            guard let windows = axWindows(pid: pid) else { continue }  // frozen app: keep its CG windows as-is
            axAnswered.insert(pid)
            for el in windows {
                guard let id = Private.windowID(of: el) else { continue }
                elements[id] = el
                ax[id] = facts(el, hidden: app.isHidden)
            }
        }
        // Windows on other Spaces: all of them in allSpaces mode; fullscreen apps (and, from inside one, the
        // desktop behind it) in currentSpace mode.
        var extra = Set<UInt32>()
        if Private.allSpacesAvailable {
            let layout = Private.desktopSpaces()
            var wanted: [pid_t: Set<UInt32>] = [:]
            for w in cg where !w.isOnScreen && w.layer == 0 && w.bounds.width >= 50 && w.bounds.height >= 50
                && regular.contains(w.pid) {
                let spaces = Private.spaces(of: w.id)
                guard scope == .allSpaces ? !spaces.isEmpty
                    : onCurrentDesktop(windowSpaces: spaces, current: layout.current, fullscreen: layout.fullscreen)
                else { continue }
                extra.insert(w.id)
                if ax[w.id] == nil { wanted[w.pid, default: []].insert(w.id) }
            }
            for (pid, ids) in wanted {
                for (id, el) in Private.remoteWindowElements(pid: pid, wanted: ids) {
                    elements[id] = el
                    ax[id] = facts(el, hidden: NSRunningApplication(processIdentifier: pid)?.isHidden ?? false)
                }
            }
            extra = extra.filter { ax[$0] != nil }  // only windows we can actually raise
        }
        let windows = buildList(cg: cg, ax: ax, ownPID: ownPID, scope: scope, alsoInclude: extra, axAnswered: axAnswered,
                                appRecency: appRecency)
        for w in windows where icons[w.pid] == nil { icons[w.pid] = NSRunningApplication(processIdentifier: w.pid)?.icon }
        return Snapshot(windows: windows, elements: elements, icons: icons)
    }

    private static func facts(_ el: AXUIElement, hidden: Bool) -> AXFacts {
        AXFacts(title: attribute(el, kAXTitleAttribute) as? String,
                isMinimized: attribute(el, kAXMinimizedAttribute) as? Bool ?? false, isHidden: hidden)
    }

    /// nil when the app didn't answer (frozen or timed out).
    static func axWindows(pid: pid_t) -> [AXUIElement]? {
        attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]
    }

    static func attribute(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }
}
