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
    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionWindow: NSWindow?
    private var axObserver: NSObjectProtocol?
    private var accessibilityItem: NSMenuItem?
    private var retryShortcutItem: NSMenuItem?
    private let settings = Settings()
    private lazy var panel = Panel()
    private lazy var hotKey = HotKey { [weak self] shift, repeatPress in self?.trigger(shift: shift, repeatPress: repeatPress) }
    private var session: Session?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        WindowSource.trackWorkspace()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Wisp")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",").target = self
        accessibilityItem = menu.addItem(withTitle: "Enable Accessibility…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem?.target = self
        retryShortcutItem = menu.addItem(withTitle: "Retry Shortcut Registration", action: #selector(retryShortcut), keyEquivalent: "")
        retryShortcutItem?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Wisp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item

        log.info("launch: accessibility=\(Permissions.accessibility), screenRecording=\(Permissions.screenRecording)")
        watchAccessibility()
        refreshAccessibility()
        if !Permissions.accessibility { askForAccessibility() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { refreshAccessibility() }

    func applicationWillTerminate(_ notification: Notification) {
        session?.cancel()
        hotKey.uninstall()
        if let axObserver { DistributedNotificationCenter.default().removeObserver(axObserver) }
    }

    private func trigger(shift: Bool, repeatPress: Bool) {
        // In Cmd+Tab mode the always-on tap may see Tab before the session's tap; hand it over.
        if let session { return session.step(forward: !shift) }
        guard !repeatPress, let shortcut = hotKey.shortcut else { return }
        let s = Session(settings: settings, shortcut: shortcut, makePanel: { [unowned self] in panel }) { [weak self] in
            self?.session = nil
        }
        session = s  // assign before start: start may end the session synchronously
        s.start(reverse: shift)
    }

    private func refreshAccessibility() {
        let trusted = Permissions.accessibility
        accessibilityItem?.isHidden = trusted
        if trusted {
            permissionWindow?.close()
            permissionWindow = nil
            retryShortcutItem?.isHidden = hotKey.install(settings.shortcut)
        } else {
            session?.cancel()
            hotKey.uninstall()
            retryShortcutItem?.isHidden = true
        }
    }

    private func watchAccessibility() {
        // The system posts this when any app's accessibility trust changes; the flag updates slightly later.
        axObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refreshAccessibility()
            }
        }
    }

    private func askForAccessibility() {
        let label = NSTextField(wrappingLabelWithString:
            "Wisp needs Accessibility permission to switch windows.")
        let button = NSButton(title: "Open System Settings", target: self, action: #selector(openAccessibilitySettings))
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

    @objc private func openAccessibilitySettings() { Permissions.openAccessibilitySettings() }

    @objc private func retryShortcut() { refreshAccessibility() }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(settings: settings, applyShortcut: { [weak self] shortcut in
                self?.applyShortcut(shortcut) ?? false
            }) { [weak self] in self?.settingsWindow = nil }
        }
        settingsWindow?.show()
    }

    private func applyShortcut(_ shortcut: Shortcut) -> Bool {
        if Permissions.accessibility {
            guard hotKey.install(shortcut) else { return false }
            session?.cancel()
            retryShortcutItem?.isHidden = true
        }
        settings.shortcut = shortcut
        return true
    }
}
