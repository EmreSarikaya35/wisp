import AppKit
import ApplicationServices
import WispCore
#if DEBUG
import os
private let perf = Logger(subsystem: "io.github.emresarikaya35.wisp", category: "perf")
#endif

struct Snapshot: Sendable {
    let windows: [WindowInfo]
    let frontmostListed: Bool
}

enum WindowSource {
    fileprivate static let queue = DispatchQueue(label: "io.github.emresarikaya35.wisp.windows", qos: .userInitiated,
                                                 autoreleaseFrequency: .workItem)
    @MainActor private static var appRecency: [pid_t] = []
    @MainActor private static var desktopHistory = DesktopHistory()

    @MainActor static func trackWorkspace() {
        let workspace = NSWorkspace.shared
        if let pid = workspace.frontmostApplication?.processIdentifier { appRecency = [pid] }
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier,
                  pid != getpid() else { return }
            MainActor.assumeIsolated {
                appRecency.removeAll { $0 == pid }
                appRecency.insert(pid, at: 0)
                if appRecency.count > 64 { appRecency.removeLast() }
            }
        }
        guard Private.allSpacesAvailable else { return }
        desktopHistory.update(Private.desktopSpaces())
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = desktopHistory.update(Private.desktopSpaces()) }
        }
    }

    @MainActor static func request(scope: Scope, receive: @escaping @MainActor @Sendable (Snapshot) -> Void) -> SnapshotRequest {
        SnapshotRequest(scope: scope, appRecency: appRecency, desktopHistory: desktopHistory, receive: receive)
    }

    @MainActor static func diagnosticSnapshot(scope: Scope) -> (Snapshot, [UInt32: AXUIElement]) {
        snapshot(scope: scope, frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                 appRecency: [], desktopHistory: DesktopHistory())
    }

    fileprivate static func snapshot(scope requestedScope: Scope, frontPID: pid_t?, appRecency: [pid_t],
                                     desktopHistory: DesktopHistory) -> (Snapshot, [UInt32: AXUIElement]) {
        let scope = Private.allSpacesAvailable ? requestedScope : .currentSpace
        func list(_ options: CGWindowListOption) -> [WindowInfo] {
            (CGWindowListCopyWindowInfo(options.union(.excludeDesktopElements), kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap(WindowInfo.init(cgDict:))
        }
        // Use the on-screen list for z-order. Include new windows even if their visibility changed between calls.
        let ownPID = getpid()
        let onScreen = list(.optionOnScreenOnly).map { window in
            var window = window
            window.isOnScreen = true
            return window
        }
        let cg = (onScreen + list(.optionAll)).filter { $0.isCandidate(excluding: ownPID) }
        let ids = Set(cg.map(\.id))
        let trusted = AXIsProcessTrusted()

        var ax: [UInt32: AXFacts] = [:], elements: [UInt32: AXUIElement] = [:]
        var regular: [pid_t: Bool] = [:]
        var axAnswered = Set<pid_t>()
        var focusedID: UInt32?
        if trusted, Private.windowIDsAvailable {
            for pid in Set(cg.map(\.pid)) {
                guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { continue }
                let hidden = app.isHidden
                regular[pid] = hidden
                let appElement = AXUIElementCreateApplication(pid)
                guard let windows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }
                var identifiedWindow = false
                for element in windows {
                    guard let id = Private.windowID(of: element) else { continue }
                    identifiedWindow = true
                    guard ids.contains(id) else { continue }
                    elements[id] = element
                    ax[id] = facts(element, hidden: hidden)
                }
                if windows.isEmpty || identifiedWindow { axAnswered.insert(pid) }

                if pid == frontPID { focusedID = focusedWindowID(in: appElement) }
            }
        }

        var extra = Set<UInt32>()
        if trusted, Private.allSpacesAvailable {
            var history = desktopHistory
            let included = scope == .currentSpace ? history.update(Private.desktopSpaces()) : []
            var wanted: [pid_t: Set<UInt32>] = [:]
            var queried = Set<UInt32>()
            for w in cg where !w.isOnScreen && regular[w.pid] != nil && queried.insert(w.id).inserted {
                if let facts = ax[w.id], scope == .allSpaces || facts.isHidden || facts.isMinimized { continue }
                let spaces = Private.spaces(of: w.id)
                guard scope == .allSpaces ? !spaces.isEmpty : !spaces.isDisjoint(with: included) else { continue }
                extra.insert(w.id)
                if ax[w.id] == nil { wanted[w.pid, default: []].insert(w.id) }
            }
            for (pid, ids) in wanted {
                for (id, element) in Private.remoteWindowElements(pid: pid, wanted: ids) {
                    elements[id] = element
                    ax[id] = facts(element, hidden: regular[pid] == true)
                }
            }
            extra = extra.filter { ax[$0] != nil }
        }
        var windows = buildList(cg: cg, ax: ax, ownPID: ownPID, scope: scope, alsoInclude: extra,
                                axAnswered: axAnswered, appRecency: appRecency)
        let focused = windows.firstIndex { window in
            window.pid == frontPID && (focusedID.map { window.id == $0 } ?? window.isOnScreen)
                && !window.isMinimized && !window.isHidden
        }
        if let focused, focused != 0 {
            let window = windows.remove(at: focused)
            windows.insert(window, at: 0)
        }
        return (Snapshot(windows: windows, frontmostListed: focused != nil), elements)
    }

    private static func facts(_ el: AXUIElement, hidden: Bool) -> AXFacts {
        var values: CFArray?
        let names = [kAXTitleAttribute, kAXMinimizedAttribute] as CFArray
        let result = AXUIElementCopyMultipleAttributeValues(el, names, [], &values)
        guard result == .success, let attributes = values as? [AnyObject], attributes.count == 2 else {
            return AXFacts(title: nil, isMinimized: false, isHidden: hidden)
        }
        return AXFacts(title: attributes[0] as? String, isMinimized: attributes[1] as? Bool ?? false, isHidden: hidden)
    }

    static func focusedWindowID(in app: AXUIElement) -> CGWindowID? {
        guard let value = attribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return Private.windowID(of: value as! AXUIElement)
    }

    static func windowElement(withID id: CGWindowID, in app: AXUIElement) -> AXUIElement? {
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement]
        return windows?.first { Private.windowID(of: $0) == id }
    }

    private static func attribute(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }
}

/// AX elements and the result stay on the window queue. Only plain window metadata crosses to the UI.
final class SnapshotRequest: @unchecked Sendable {
    private var result: (Snapshot, [UInt32: AXUIElement])?

    init(scope: Scope, appRecency: [pid_t], desktopHistory: DesktopHistory,
         receive: @escaping @MainActor @Sendable (Snapshot) -> Void) {
        WindowSource.queue.async { [weak self] in
            guard let self else { return }
            #if DEBUG
            let start = DispatchTime.now()
            #endif
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let result = WindowSource.snapshot(scope: scope, frontPID: frontPID, appRecency: appRecency,
                                               desktopHistory: desktopHistory)
            self.result = result
            let snapshot = result.0
            #if DEBUG
            let ms = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            perf.info("snapshot \(ms) ms, \(snapshot.windows.count) windows")
            #endif
            DispatchQueue.main.async { receive(snapshot) }
        }
    }

    func activate(select: @escaping @Sendable (Snapshot) -> Int) {
        // Queue immediately on release, so a subsequent shortcut cannot scan ahead of this activation.
        WindowSource.queue.async { [self] in
            guard let (snapshot, elements) = result else { return }
            let index = select(snapshot)
            guard snapshot.windows.indices.contains(index) else { return }
            let window = snapshot.windows[index]
            Activator.activate(window, element: elements[window.id])
        }
    }
}
