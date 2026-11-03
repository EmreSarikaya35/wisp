import AppKit
import ApplicationServices
import CoreGraphics
import WispCore
import os

let log = Logger(subsystem: "io.github.emresarikaya35.wisp", category: "app")

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }
    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func requestScreenRecording() { CGRequestScreenCaptureAccess() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionWindow: NSWindow?
    private var axObserver: NSObjectProtocol?
    private let settings = Settings()
    private lazy var panel = Panel()
    private lazy var hotKey = HotKey { [weak self] shift in self?.trigger(shift: shift) }
    private var session: Session?
    private var settingsWindow: SettingsWindow?
    private var installedShortcut: Shortcut?

    func applicationDidFinishLaunching(_ note: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Wisp")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Wisp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item

        log.info("launch: accessibility=\(Permissions.accessibility), screenRecording=\(Permissions.screenRecording)")
        if Permissions.accessibility { accessibilityReady() } else { askForAccessibility() }
    }

    private func trigger(shift: Bool) {
        // In Cmd+Tab mode the always-on tap may see Tab before the session's tap; hand it over.
        if let session { return session.step(forward: !shift) }
        let s = Session(settings: settings, modifier: settings.shortcut == .option ? .maskAlternate : .maskCommand,
                        panel: panel) { [weak self] in self?.session = nil }
        session = s  // assign before start: start may end the session synchronously
        s.start(reverse: shift)
    }

    private func accessibilityReady() {
        installShortcut()
        NotificationCenter.default.addObserver(forName: .wispSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.installShortcut() }
        }
        _ = WindowSource.snapshot(scope: settings.scope)  // first AX contact per app costs ~30 ms; pay it now, not on the first Option+Tab
        permissionWindow?.close()
        permissionWindow = nil
        if let axObserver { DistributedNotificationCenter.default().removeObserver(axObserver) }
        axObserver = nil
    }

    private func askForAccessibility() {
        // The system posts this when any app's accessibility trust changes; the flag updates slightly later.
        axObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { if Permissions.accessibility { self?.accessibilityReady() } }
            }
        }

        let label = NSTextField(wrappingLabelWithString:
            "Wisp needs Accessibility permission to switch windows.")
        let button = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        button.keyEquivalent = "\r"
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Wisp"
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating  // a background app can't take focus at launch; keep the prompt visible
        permissionWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @objc private func openSettings() { Permissions.openAccessibilitySettings() }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(settings: settings) { [weak self] in self?.settingsWindow = nil }
        }
        settingsWindow?.show()
    }

    /// Applies the shortcut setting live; no restart needed.
    private func installShortcut() {
        guard installedShortcut != settings.shortcut else { return }
        hotKey.install(settings.shortcut)
        installedShortcut = settings.shortcut
    }
}
