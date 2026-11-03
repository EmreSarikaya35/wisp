import AppKit
import WispCore

// Process-wide AX timeout: a per-element timeout does not carry over to the window elements an app returns,
// which otherwise wait 1.5 s each on a frozen app.
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.1)

// Debug entry points for manual verification from a terminal.
let args = CommandLine.arguments
if args.contains("--list") {
    let t = Date()
    let scope: Scope = args.contains("--all") ? .allSpaces : .currentSpace
    let windows = MainActor.assumeIsolated { WindowSource.snapshot(scope: scope).windows }
    FileHandle.standardError.write("snapshot \(Int(Date().timeIntervalSince(t) * 1000)) ms\n".data(using: .utf8)!)
    for w in windows {
        print(w.id, w.pid, w.appName, "—", w.title, w.isMinimized ? "[min]" : "")
    }
    exit(0)
}
if let i = args.firstIndex(of: "--activate"), i + 1 < args.count, let id = UInt32(args[i + 1]) {
    MainActor.assumeIsolated {
        let snap = WindowSource.snapshot(scope: .currentSpace)
        guard let w = snap.windows.first(where: { $0.id == id }) else { print("not found"); exit(1) }
        Activator.activate(w, element: snap.elements[id])
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
